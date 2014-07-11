
// sync operation
// scan config folders and plugins for updates
//

// todo: bug sourcemod peeps to add SetFileTime...
//
enum {
	SYNCMODE_ALL,
	SYNCMODE_GROUP,
	SYNCMODE_DIR,
	SYNCMODE_FILE
};

//-------------------------------------------------------------------------------------------------
bool:SyncValidateTarget( const String:target[], &mode ) {
	if( StrEqual( target, "all" ) ) {
		mode = SYNCMODE_ALL;
		return true;
	}
	
	ResetPack( g_sync_paths );
	while( IsPackReadable( g_sync_paths, 1 ) ) {
		decl String:group[128];
		ReadPackString( g_sync_paths, group, sizeof group ); // path
		ReadPackString( g_sync_paths, group, sizeof group ); // group
		ReadPackCell( g_sync_paths ); // flags
		
		if( StrEqual( group, target ) ) {
			mode = SYNCMODE_GROUP;
			return true;
		}
	}
	
	decl String:path[128];
	if( FormatLocalPath( path, sizeof path, target ) ) {
		if( DirExists( path ) ) {
			mode = SYNCMODE_DIR;
			return true;
		}
		if( FileExists( path ) ) {
			mode = SYNCMODE_FILE;
			return true;
		}
	}
	strcopy( path, sizeof path, target );
	AddPathSlash( path, sizeof path );
	
	if( FormatLocalPath( path, sizeof path, path ) ) {
		StripPathSlash(path);
		
		if( path[0] == 0 || DirExists( path ) ) {
			
			mode = SYNCMODE_DIR;
			return true;
		}
	}
	
	return false;
}

//-------------------------------------------------------------------------------------------------
public Action:Command_sync( args ) {
	if( args == 0 ) {
		PrintToServer( "[ST] Usage: st_sync <target> [-f] [-r] [-a] [-p]" );
		PrintToServer( "     Synchronizes files" );
		PrintToServer( "     -m : don't reload map" );
		PrintToServer( "     -f : force update" );
		PrintToServer( "     -r : directory recursive" );
		PrintToServer( "     -a : sync all files in directory" );
		PrintToServer( "     -p : plugins" );
		PrintToServer( "     target can be a syncpath, \"all\", a file path, or a directory." );
		return Plugin_Handled;
	}
	
	decl String:target[128];
	target[0] = 0;
	new flags;
	
	for( new i = 0; i < args; i++ ) {
		decl String:arg[64];
		GetCmdArg( 1+i, arg, sizeof arg );
		if( arg[0] == '-' ) {
			// flag
			for( new j = 1; arg[j]; j++ ) {
				if( arg[j] == 'm' ) {
					flags |= SYNCFLAG_NORELOAD;
				} else if( arg[j] == 'f' ) {
					flags |= SYNCPATHFLAG_FORCE;
				} else if( arg[j] == 'r' ) {
					flags |= SYNCPATHFLAG_RECURSIVE;
				} else if( arg[j] == 'a' ) {
					flags |= SYNCPATHFLAG_ALL;
				} else if( arg[j] == 'p' ) {
					flags |= SYNCPATHFLAG_PLUGINS;
				} else {
					PrintToServer( "[ST] st_sync - Unknown option: \"%c\"", arg[j] );
					return Plugin_Handled;
				}
			}
		} else {
			if( target[0] != 0 ) {
				PrintToServer( "[ST] st_sync - bad arguments" );
				return Plugin_Handled;
			}
			strcopy( target, sizeof target, arg );
		}
	}
	
	
	// validate target
	if( target[0] == 0 ) {
		PrintToServer( "[ST] st_sync - missing target" );
		return Plugin_Handled;
	}
	
	if( g_remote_url[0] == 0 ) {
		PrintToServer( "[ST] st_sync - remote is not set up." );
		return Plugin_Handled;
	}
	
	new mode;
	if( !SyncValidateTarget( target, mode ) ) {
		PrintToServer( "[ST] st_sync - target is not valid." );
		return Plugin_Handled;
	}
	
	StartSync( target, flags );
	return Plugin_Handled;
}

//-------------------------------------------------------------------------------------------------
GetLastSync() {
	decl String:path[128];
	BuildPath( Path_SM, path ,sizeof path, "data/servertools_sync" );
	if( !FileExists( path ) ) return 0;
	return GetFileTime( path, FileTime_LastChange );
}

//-------------------------------------------------------------------------------------------------
SetLastSync() {
	decl String:path[128];
	BuildPath( Path_SM, path, sizeof path, "data/servertools_sync" );
	new Handle:h = OpenFile( path, "wb" );
	CloseHandle(h);
}

//-------------------------------------------------------------------------------------------------
StartSync( const String:target[], forceflags=0 ) {
	// target may be:
	// "all"
	// syncpath group
	// directory path
	// file path
	if( g_remote_url[0] == 0 ) return;

	LoadIDConfig();
	
	new mode;
	if( !SyncValidateTarget( target, mode ) ) {
		return;
	}
	
	new Handle:op = CreateOperation( "Server Sync", OnSyncStart );
	 
	if( mode == SYNCMODE_GROUP ) {
		KvSetString( op, "user/syncgroup", target );
	} else if( mode == SYNCMODE_DIR || mode == SYNCMODE_FILE ) {
		decl String:path[128];
		strcopy( path, sizeof path, target );
		if( mode == SYNCMODE_DIR ) {
			AddPathSlash(path, sizeof path);
		}
		FormatLocalPath( path, sizeof path, path );
		KvSetString( op, "user/syncpath", path );
	}
	
	KvSetNum( op, "user/syncmode", mode );
	KvSetHandle( op, "user/updatelist", CreateDataPack() );
	KvSetHandle( op, "user/downloadlist", CreateDataPack() );
	KvSetNum( op, "user/forceflags", forceflags );
	KvSetNum( op, "user/updated", 0 );
	
	StartOperation(op);
}

//-------------------------------------------------------------------------------------------------
bool:TranslateRemotePath( const String:localpath[], String:remotepath[], maxlen ) {
	TrimString( remotepath );
	if( remotepath[0] == 0 ) {
		strcopy( remotepath, maxlen, localpath );
		return true;
	}
	if( StrContains( remotepath, "/" ) >= 0 ) {
		// absolute path
		return FormatLocalPath( remotepath, maxlen, remotepath );
	} else {
		decl String:curdir[128];
		StripFileName( curdir, sizeof curdir, localpath );
		Format( remotepath, maxlen, "%s%s", curdir, remotepath );
		return true;
	}
}

//-------------------------------------------------------------------------------------------------
bool:ScanFileForSync( const String:file[], String:syncpath[], maxlen, bool:text ) {
	
	new Handle:f;
	if( text ) {
		f = OpenFile(file,"r");
		
		// search file for ST:SYNC tag
		decl String:line[1024];
		while( ReadFileLine( f, line, sizeof line ) ){
			new index = StrContains( line, "//[ST:SYNC]" );
			if( index == -1 ) continue;
			CloseHandle(f);
			
			// found sync line
			strcopy( syncpath, maxlen, line[index+11] );
			if( !TranslateRemotePath( file, syncpath, maxlen ) ) {
				LogToFile( g_logfile, "bad [ST:SYNC] remote path in file \"%s\"", file );
			}
			 
			return true;
		}
		CloseHandle(f);
	}
	
	// look for .sync file
	decl String:file2[128];
	FormatEx( file2, sizeof file2, "%s.sync", file );
	if( FileExists( file2 ) ) {
		// file exists, first line is sync path

		f = OpenFile( file2, "r" );
		if( ReadFileLine( f, syncpath, maxlen ) ) {
			CloseHandle(f);
			if( !TranslateRemotePath( file, syncpath, maxlen ) ) {
				LogToFile( g_logfile, "bad path in syncfile \"%s\"", file2 );
				return false;
			}
			return true;
		}
		
		// if empty: use original path
		strcopy( syncpath, maxlen, file );
		
		CloseHandle(f);
		return true;
	}
	
	return false;
}

SyncCheckFile( Handle:updatelist, const String:path[], bool:allflag ) {	
	// skip .sync files
	decl String:ext[32];
	GetFileExt( ext, sizeof ext, path );
	if( StrEqual( ext, "sync" ) ) {
		return;
	} 
	
	decl String:syncpath[128];
	new bool:text = IsTrieSet( g_text_extensions, ext );
	if( ScanFileForSync( path, syncpath, sizeof syncpath, text ) ) {
		WritePackString( updatelist, path );
		WritePackString( updatelist, syncpath );
		WritePackCell( updatelist, 0 ); // not optional
		
	} else if( allflag ) {
		// we didnt find a sync tag, but ALLSYNC is set
		// remote and local paths are the same
		
		WritePackString( updatelist, path );
		WritePackString( updatelist, path );
		WritePackCell( updatelist, 1 ); // optional
	}
}
 
//-------------------------------------------------------------------------------------------------
ScanForSync( Handle:updatelist, const String:path[], level, flags ) {
	
	decl String:entry[128];
	new Handle:dir = OpenDirectory( path ); // todo can you open a dir with a traiiling slash?
	new FileType:ft;
	
	while( ReadDirEntry( dir, entry, sizeof entry, ft ) ) {
		if( ft == FileType_Directory ) {
			if( !(flags & SYNCPATHFLAG_RECURSIVE)  ) continue;
			if( StrEqual( entry, "." ) ||
				StrEqual( entry, ".." ) ) continue;
			
			// skip disabled folder for plugins
			if( flags & SYNCPATHFLAG_PLUGINS ) {
				if( level == 0 && StrEqual( entry, "disabled" ) ) 
					continue;
			}
			
			decl String:subdir[128];
			FormatEx( subdir, sizeof subdir, "%s%s/", path, entry );
			ScanForSync( updatelist, subdir, level+1, flags );
		} else if( ft == FileType_File ) {
			 
			decl String:fullpath[128];
			FormatEx( fullpath, sizeof fullpath, "%s%s", path, entry ); 
			SyncCheckFile( updatelist, fullpath,!!( flags & SYNCPATHFLAG_ALL) ); 
		}
	}
	CloseHandle(dir);
}
/*
//-------------------------------------------------------------------------------------------------
ScanPluginsFolder( Handle:updatelist, const String:folder, level ) {
	
	decl String:path[256];
	
	BuildPath( Path_SM, path, sizeof path, "plugins"
	// todo if dir exists
}*/

//-------------------------------------------------------------------------------------------------
public OnSyncStart( Handle:op ) {
	// generate a file list to be updated
	// list is local path and remote path
	
	new Handle:updatelist = KvGetHandle( op, "user/updatelist" );
	new syncmode = KvGetNum( op, "user/syncmode" );
	new forceflags = KvGetNum( op, "user/forceflags" );
	if( syncmode == SYNCMODE_ALL ) {
	
		ResetPack( g_sync_paths );
		while( IsPackReadable( g_sync_paths, 1 ) ) {
			decl String:path[128];
			decl String:group[128];
			ReadPackString( g_sync_paths, path, sizeof path );
			ReadPackString( g_sync_paths, group, sizeof group );
			new flags = ReadPackCell( g_sync_paths );
			ScanForSync( updatelist, path, 0, flags|forceflags );
		}
	} else if( syncmode == SYNCMODE_GROUP ) {
		decl String:syncgroup[64];
		KvGetString( op, "user/syncgroup", syncgroup, sizeof syncgroup );
		ResetPack( g_sync_paths );
		while( IsPackReadable( g_sync_paths, 1 ) ) {
			decl String:path[128];
			decl String:group[128];
			ReadPackString( g_sync_paths, path, sizeof path );
			ReadPackString( g_sync_paths, group, sizeof group );
			new flags = ReadPackCell( g_sync_paths );
			if( StrEqual( syncgroup, group ) ) {
				
				ScanForSync( updatelist, path, 0, flags|forceflags );
			}
		}
	} else if( syncmode == SYNCMODE_DIR ) {
		decl String:syncpath[64];
		KvGetString( op, "user/syncpath", syncpath, sizeof syncpath );
		ScanForSync( updatelist, syncpath, 0, forceflags );
	} else if( syncmode == SYNCMODE_FILE ) {
		decl String:syncpath[64];
		KvGetString( op, "user/syncpath", syncpath, sizeof syncpath );
		SyncCheckFile( updatelist, syncpath, !!(forceflags&SYNCPATHFLAG_ALL) );
	}
	ResetPack( updatelist );
	ProcessSyncFiles( op );
}

//-------------------------------------------------------------------------------------------------
ProcessSyncFiles( Handle:op ) {
	new Handle:updatelist = KvGetHandle( op, "user/updatelist" );
	new index = 0;
	if( !IsPackReadable( updatelist, 1 ) ) {
		// no more files in update list, start downloads
		ResetPack( KvGetHandle( op, "user/downloadlist" ) );
		SyncTransfer( op );
		return;
	}
	
	new Handle:list = CreateDataPack();
	new start = GetPackPosition(updatelist);
	while( IsPackReadable( updatelist, 1 ) && index < 50 ) {
		decl String:entry[128];
		ReadPackString( updatelist, entry, sizeof entry ); // local path (skip)
		ReadPackString( updatelist, entry, sizeof entry ); // remote path
		ReadPackCell( updatelist ); // optional
		Format( entry, sizeof entry, "%s/%s", g_remote_dir, entry );
		decl String:name[64];
		FormatEx( name, sizeof name, "%i", index+1 );
		WritePackString( list, name );
		WritePackString( list, entry );
		index++;
	}
	
	// rewind, we go over this data again with the listing result
	SetPackPosition( updatelist, start ); 
	
	// request file info
	decl String:url[512];
	FormatEx( url, sizeof url, "%s%s?%s", g_remote_url, "listing.php", g_url_request_params );
	RemoteTransfer( url, OnSyncGetListing, op, list );
}

//-------------------------------------------------------------------------------------------------
CancelSyncOperation( Handle:op, const String:error[] ) {
	OperationError( op, "%s", error );
	
	// cleanup
	CloseHandle( KvGetHandle( op, "user/updatelist" ) );
	CloseHandle( KvGetHandle( op, "user/downloadlist" ) );
	EndOperation( op );
}

//-------------------------------------------------------------------------------------------------
public OnSyncGetListing( Handle:hndl, bool:success, any:data ) { 
	new Handle:op = data;
	if( !success ) {
		CancelSyncOperation( op, "Couldn't retrieve listing from remote." );
		return;
	}
	
	new bool:force = !!(KvGetNum( op, "user/forceflags" ) & SYNCPATHFLAG_FORCE);
	new Handle:updatelist = KvGetHandle( op, "user/updatelist" );
	new Handle:downloadlist = KvGetHandle( op, "user/downloadlist" );
	decl String:filepath[128];
	KvGetString( hndl, "file", filepath, sizeof filepath );
	new Handle:file = OpenFile( filepath, "r" );
	decl String:line[128];
	if( !ReadFileLine( file, line, sizeof line ) ) {
		CancelSyncOperation( op, "listing error" );
		CloseHandle(file);
		return;
	}
	// check for response header "LISTING"
	TrimString(line);
	if( !StrEqual( line, "LISTING" ) ) {
		CancelSyncOperation( op, "listing error" );
		CloseHandle(file);
		return;
	}
	
	// response is in this format:
	// FILE SIZE or [SKIP]
	// FILE TIME if not [SKIP]
	// <repeat for each file requested>
	
	decl String:localfile[128], localfilesize, localfiletime;
	decl String:remotefile[128], remotefilesize, remotefiletime;
	new index = 0;
	while( ReadFileLine( file, line, sizeof line ) ) {
		index++;
		TrimString( line );
		ReadPackString( updatelist, localfile, sizeof localfile );
		ReadPackString( updatelist, remotefile, sizeof remotefile );
		new optional = ReadPackCell( updatelist );
		
		// [SKIP]: file not present, do not sync
		if( StrEqual( line, "[SKIP]" ) ) {
			if( !optional ) {
				if( StrEqual( remotefile, localfile ) ) {
					OperationError( op, "Remote file not found: %s", remotefile );
				} else {
					OperationError( op, "Remote file not found: %s (for %s)", remotefile, localfile );
				}
			}
			continue; 
		}
		
		decl String:ext[32];
		GetFileExt( ext, sizeof ext, localfile );
		new bool:binary = !IsTrieSet( g_text_extensions, ext );
		
		localfilesize = FileSize( localfile );
		localfiletime = GetFileTime( localfile, FileTime_LastChange );
		remotefilesize = StringToInt( line );
		ReadFileLine( file, line, sizeof line );
		TrimString(line);
		remotefiletime = StringToInt( line );
		
		if( force || 
			remotefiletime > localfiletime || 
			(binary && (remotefilesize != localfilesize)) ) {
			
			// add to downloads
			WritePackString( downloadlist, remotefile );
			WritePackString( downloadlist, localfile );
		} 
	}
	CloseHandle(file);
	// process next batch
	ProcessSyncFiles( op );
}

//-------------------------------------------------------------------------------------------------
SyncTransfer( Handle:op ) {
	new Handle:downloadlist = KvGetHandle( op, "user/downloadlist" );
	if( !IsPackReadable( downloadlist, 1 ) ) {	
		// operation is complete
		
		new updated = KvGetNum( op, "user/updated" );
		
		if( updated > 0 && !(KvGetNum( op, "user/forceflags" )&SYNCFLAG_NORELOAD) ) {
			// files were updated, reload the map if no players are playing
			new bool:reload = true;
			for( new i = 1; i <= MaxClients; i++ ) {
				if( IsClientInGame(i) && GetClientTeam(i) > 1 ) {
					reload=false;
					break;
				}
			}
			if( reload ) {
				decl String:map[64];
				GetCurrentMap( map, sizeof map );
				ForceChangeLevel( map, "Post-Sync" );
			}
		}
		CloseHandle( KvGetHandle( op, "user/updatelist" ) );
		CloseHandle( KvGetHandle( op, "user/downloadlist" ) );
		
		if( KvGetNum( op, "errors" ) == 0 ) {
			SetLastSync();
		}
		
		OperationLog( op, "Sync complete, %d file%s updated.", updated, updated==1?"":"s" );
		EndOperation( op ); 
		return;
	}
	
	decl String:file[128];
	ReadPackString( downloadlist, file, sizeof file );
	
	decl String:url[512];
	FormatEx( url, sizeof url, "%s%s/%s?%s", g_remote_url, g_remote_dir, file, g_url_request_params );
	
	OperationLog( op, "getting update: \"%s\"...", file );
	RemoteTransfer( url, OnSyncTransferred, op );
}

//-------------------------------------------------------------------------------------------------
public OnSyncTransferred( Handle:hndl, bool:success, any:data ) {
	new Handle:op = data;
	new Handle:downloadlist = KvGetHandle( op, "user/downloadlist" );
	
	if( !success ) {
		// failed to download file.
		decl String:url[512];
		KvGetString( hndl, "url", url, sizeof url );
		if( KvGetNum( hndl, "notfound" ) ) {
			OperationError( op, "remote file is missing \"%s\".", url );
		} else {
			OperationError( op, "couldn't retrieve \"%s\".", url );
		}
		ReadPackString( downloadlist, url, sizeof url ); // "discard local path"
		
		SyncTransfer( op );
		return;
	} else {
	
		decl String:localfile[128];
		decl String:outfile[128];
		ReadPackString( downloadlist, localfile, sizeof localfile );
		KvGetString( hndl, "file", outfile, sizeof outfile );
		
		if( FileExists( localfile ) ) {
			if( !DeleteFile( localfile ) ) {
				OperationError( op, "disk error." );
				SyncTransfer( op );
				return;
			}
		}
		
		decl String:ext[32];
		GetFileExt( ext, sizeof ext, localfile );
		if( IsTrieSet( g_text_extensions, ext ) ) {
			PreprocessFile( op, outfile, sizeof outfile );
		}
		
		if( RenameFile( localfile, outfile ) ) {
			KvSetNum( op, "user/updated", KvGetNum( op, "user/updated" ) + 1 );
		} else {
			OperationError( op, "disk error." );
		}
		
		SyncTransfer( op );
		return;
	}
}

