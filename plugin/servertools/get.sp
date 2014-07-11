
enum {
	//GET_SYNC=1 //TODO
};
enum {
	GETMODE_SINGLE=1,
	GETMODE_PACKAGE=2
};

//-------------------------------------------------------------------------------------------------
public Action:Command_remove( args ) {
	if( args == 0 ) {
		PrintToServer( "[ST] Usage: st_remove <target>" );
		return Plugin_Handled;
	}
	
	decl String:arg[128];
	GetCmdArg( 1, arg ,sizeof arg );
	if( !FormatLocalPath( arg, sizeof arg, arg ) ) {
		PrintToServer( "[ST] st_remove - bad path" );
		return Plugin_Handled;
	}
	
	if( !FileExists( arg ) ) {
		PrintToServer( "[ST] File doesn't exist." );
		return Plugin_Handled;
	}
	if( !DeleteFile( arg ) ) {
		PrintToServer( "[ST] Couldn't delete file." );
		return Plugin_Handled;
	}
	
	PrintToServer( "[ST] File deleted." );
	return Plugin_Handled;
}

//-------------------------------------------------------------------------------------------------
public Action:Command_get( args ) {
	if( args == 0 ) {
		PrintToServer( "[ST] Usage: st_get <target> [remote]" );
		//PrintToServer( "[ST]   -s : create sync file" );
		return Plugin_Handled;
	}
	if( g_remote_url[0] == 0 ) {
		PrintToServer( "[ST] st_get - remote is not set up." );
		return Plugin_Handled;
	}
	
	decl String:target[128];
	target[0] = 0;
	decl String:remote[128];
	remote[0] = 0;
	new flags;
	for( new i = 0; i < args; i++ ) {
		decl String:arg[128];
		GetCmdArg( 1+i, arg, sizeof arg );
		if( arg[0] == '-' ) {
			//if( arg[1] == 's' ) {
		//		flags |= GET_SYNC;
		//	} else {
			PrintToServer( "[ST] st_get - Unknown option: \"%c\"", arg[1] );
			return Plugin_Handled;
		//	}
		} else {
			if( target[0] == 0 ){
				strcopy( target, sizeof target, arg );
			} else if( remote[0] == 0 ) {
				strcopy( remote, sizeof remote, arg );
			} else {
				PrintToServer( "[ST] st_get - bad args" );
				return Plugin_Handled;
			}
		}
	}
	
	// validate target
	if( target[0] == 0 ) {
		PrintToServer( "[ST] st_get - missing target" );
		return Plugin_Handled;
	}
	
	if( strncmp( target, "pkg/", 4 ) == 0 ){ 
		// package is desired
		Format( target, sizeof target, "%s", target[4] );
		if( target[0] == 0 ) return Plugin_Handled;
		DoGetPackage( target, flags );
		return Plugin_Handled;
	}
	
	if( !FormatLocalPath( target, sizeof target, target ) ) {
		PrintToServer( "[ST] st_get - bad path" );
		return Plugin_Handled;
	}
	
	if( !TranslateRemotePath( target, remote, sizeof remote ) ) {
		PrintToServer( "[ST] st_get - bad remote path" );
		return Plugin_Handled;
	}
	
	
	DoGet( target, remote, flags );
	return Plugin_Handled;
}

//-------------------------------------------------------------------------------------------------
DoGetPackage( const String:package[], flags ) {
	
	LoadIDConfig();

	new Handle:op = CreateOperation( "Server Get", OnGetStart );
	KvSetNum( op, "user/mode", GETMODE_PACKAGE );
	KvSetString( op, "user/target", package );
	KvSetNum( op, "user/flags", flags );
	StartOperation(op);
	
}

//-------------------------------------------------------------------------------------------------
DoGet( const String:localfile[], const String:remotefile[], flags ) {

	LoadIDConfig();

	new Handle:op = CreateOperation( "Server Get", OnGetStart );
	KvSetNum( op, "user/mode", GETMODE_SINGLE );
	KvSetString( op, "user/target", localfile );
	KvSetString( op, "user/remote", remotefile );
	KvSetNum( op, "user/flags", flags );
	 
	StartOperation(op);
}

//-------------------------------------------------------------------------------------------------
CleanupGetOp( Handle:op ) {
	CloseHandle( KvGetHandle( op, "user/downloadlist" ) );
}

//-------------------------------------------------------------------------------------------------
public OnGetStart( Handle:op ) {
	new mode = KvGetNum( op, "user/mode" );
	new Handle:downloads = CreateDataPack();
	KvSetHandle( op, "user/downloadlist", downloads );
	
	if( mode == GETMODE_SINGLE ) {
		decl String:path[128];
		KvGetString( op, "user/remote", path, sizeof path );
		WritePackString( downloads, path ); 
		KvGetString( op, "user/target", path, sizeof path );
		WritePackString( downloads, path );
		
		ResetPack( downloads );
		GetDownload( op );
	} else if( mode == GETMODE_PACKAGE ) {
		decl String:url[512];
		decl String:target[128];
		KvGetString( op, "user/target", target, sizeof target );
		FormatEx( url, sizeof url, "%spackages/%s.package?%s", g_remote_url, target, g_url_request_params );
		RemoteTransfer( url, OnGetPackage, op );
	}
}

//-------------------------------------------------------------------------------------------------
public OnGetPackage( Handle:hndl, bool:success, any:data ) { 
	new Handle:op = data;
	if( !success ) {
		
		
		decl String:package[64];
		KvGetString( op, "user/target", package, sizeof package );
		if( KvGetNum( hndl, "notfound" ) ) {
			
			OperationError( op, "Package doesn't exist. \"%s.package\"", package );
		} else {
			OperationError( op, "Couldn't retrieve package. \"%s.package\"", package );
		}
		CleanupGetOp( op );
		EndOperation(op);
		return;
	}
	
	new Handle:downloads = KvGetHandle( op, "user/downloadlist" );
	

	new Handle:kv = CreateKeyValues("ServerToolsPackage");
	decl String:file[128];
	KvGetString( hndl, "file", file, sizeof file );
	if( !FileToKeyValues( kv, file ) ) {
		OperationError( op, "bad package file." );
		CloseHandle(kv);
		CleanupGetOp(op);
		EndOperation(op);
		return;
	}
	
	if( !KvGotoFirstSubKey( kv ) ) {
		OperationError( op,  "bad package file." );
		CloseHandle(kv);
		CleanupGetOp(op);
		EndOperation(op);
		return;
	}
	
	new filecount = 0;
	do {
		decl String:target[64];
		KvGetString( kv, "target", target, sizeof target );
		TrimString(target);
		if( target[0] == 0 ) {
			continue;
		}
		if(!IsTarget(target) ) {
			continue;
		}
		decl String:name[64];
		KvGetSectionName( kv, name, sizeof name );
		OperationLog( op, "Getting sub-package: %s", name );
		if( !KvJumpToKey( kv, "files" ) ) {
			OperationLog( op, "Sub-package has no files." );
			continue;
		}
		
		if( !KvGotoFirstSubKey( kv, false ) ) {
			OperationLog( op, "Sub-package has no files." );
			KvGoBack( kv );
			continue;
		}
		
		do {
			decl String:localfile[128];
			decl String:remotefile[128];
			KvGetSectionName( kv, localfile, sizeof localfile );
			
			TrimString( localfile );
			if( localfile[0] == 0 ) continue;
			if( !FormatLocalPath( localfile, sizeof localfile, localfile ) ) {
				OperationError( op, "Bad local file path: %s", localfile );
				continue;
			}
			KvGetString( kv, NULL_STRING, remotefile, sizeof remotefile );
			
			if( !TranslateRemotePath( localfile, remotefile, sizeof remotefile ) ) {
				OperationError( op, "Bad remote file path: %s", remotefile );
				continue;
			}
			
			WritePackString( downloads, remotefile );
			WritePackString( downloads, localfile );
			filecount++;
		} while( KvGotoNextKey( kv, false ) );
		
		KvGoBack( kv );
		KvGoBack( kv );
	} while( KvGotoNextKey( kv ) );
	CloseHandle( kv );
	
	if( filecount == 0 ) {
		OperationLog( op, "No files to download."  );
		CleanupGetOp( op );
		EndOperation( op );
		return;
	}
	ResetPack( downloads );
	GetDownload( op );
}

//-------------------------------------------------------------------------------------------------
GetDownload( Handle:op ) {
 
	new Handle:downloads = KvGetHandle( op, "user/downloadlist" );
	
	if( !IsPackReadable( downloads, 1 ) ) {	
		// we are done.
		
		new count = KvGetNum( op, "user/count" );
		if( count != 0 ) {
			if( count > 1 ) {
				OperationLog( op, "Get complete. %d files transferred.", count );
			} else {
				OperationLog( op, "Get complete."  );
			}
		} else {
			OperationLog( op, "Get failed." );
		}
		
		CleanupGetOp( op );
		EndOperation( op );
		return;
	}
	
	decl String:remotefile[128];
	decl String:localfile[128];
	ReadPackString( downloads, remotefile, sizeof remotefile );
	KvSetString( op, "user/currentfile", remotefile );
	ReadPackString( downloads, localfile, sizeof localfile );
	KvSetString( op, "user/currentlocalfile", localfile );
	KvSetNum( op, "user/downloadmode", 0 );
	decl String:url[512];
	FormatEx( url, sizeof url, "%s%s/%s?%s", g_remote_url, g_remote_dir, remotefile, g_url_request_params );

	OperationLog( op, "getting \"%s\"...", remotefile );
	 
	RemoteTransfer( url, OnGetFile, op );
}

//-------------------------------------------------------------------------------------------------
public OnGetFile( Handle:hndl, bool:success, any:data ) {
	new Handle:op = data;
	
	decl String:remotefile[128];
	KvGetString( op, "user/currentfile", remotefile, sizeof remotefile );
	new downloadmode = KvGetNum( op, "user/downloadmode" );
		
	if( !success ) {
		
		if( downloadmode == 0 ) {
			KvSetNum( op, "user/downloadmode", 1 );
			
			// try to get from nonsync folder.
			decl String:url[512];
			FormatEx( url, sizeof url, "%s%s/%s?%s", g_remote_url, g_remote_dirns, remotefile, g_url_request_params );
			RemoteTransfer( url, OnGetFile, op );
			
		} else if( downloadmode == 1 ) {
			OperationError( op, "Couldn't retrieve file: %s", remotefile );
			
			GetDownload( op );
			
		} else {
			// assumed downloadmode=2
			// sync file doesnt exist; this is not an error.
			
			GetDownload( op );
		}
	} else {
		decl String:localfile[128];
		KvGetString( op, "user/currentlocalfile", localfile, sizeof localfile ); 
		if( downloadmode == 2 ) {
			StrCat( localfile, sizeof localfile, ".sync" );
		}
		
		decl String:outfile[128];
		KvGetString( hndl, "file", outfile, sizeof outfile );
		
		if( downloadmode != 2 ) {
			decl String:ext[32];
			GetFileExt( ext, sizeof ext, localfile );
			if( IsTrieSet( g_text_extensions, ext ) ) {
				PreprocessFile( op, outfile, sizeof outfile );
			}
		}
		
		OperationLog( op, "saving \"%s\"...", localfile );
		PrimeFileTarget( localfile );
		if( RenameFile( localfile, outfile ) ) {
			KvSetNum( op, "user/count", KvGetNum( op, "user/count" ) + 1 );
		} else {
			OperationError( op, "disk error." );
		}
			
		if( downloadmode == 0 ) {
			
			// this was downloaded from the normal files, try to get a sync file.
			KvSetNum( op, "user/downloadmode", 2 );
			decl String:url[512];
			FormatEx( url, sizeof url, "%s%s/%s.sync?%s", g_remote_url, g_remote_dir, remotefile, g_url_request_params );
		
			RemoteTransfer( url, OnGetFile, op );
			return;
		}
		
		GetDownload(op);
	}
}
