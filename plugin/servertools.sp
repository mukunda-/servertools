//
// ServerTools Program Definition
//
// (c) 2014 mukunda
//
//-------------------------------------------------------------------------------------------------
#include <sourcemod>
#include <regex>
#include <cURL>

#undef REQUIRE_PLUGIN
#include <updater>

#pragma semicolon 1

#define PLUGIN_VERSION "3.0.3"

// 3.0.3
//   run sync in onpluginstart.
// 3.0.2
//   bugfixes
// 3.0.1
//   reload id on sync/get
//   AND in st_id
// 3.0.0 
//   the new era
//   gutted system
//   new st_sync
//   new st_get
// 1.3.3
//   corrected target logic
//
// 1.3.1
//   sync/hibernation fix
//
// 1.3.0
//   auto hibernation wake/sleep during operations 
//   delay updater to avoid collision with sync function
//   insert spaces before - or + in target strings 
//   st_id prints groups 
//   target '+' modifier bugfix 
//   only reload map after auto sync if the teams have no players 
//   change map after auto sync
//
// 1.2.0
//   reworked #if again
//   sync feature
//   new targets function
//   
// 1.1.7alpha
//   more robust viewing function
//
// 1.1.6alpha
//   CreateDirectory bugfix
//
// 1.1.5alpha
//   reworked #if statements
//   line numbers for view
//   added st_edit
//   line endings fix
//   added web/ transfers
// 1.1.4alpha
//   fixed bug in ftp upload
// 1.1.3alpha
//   added st_delete

//-------------------------------------------------------------------------------------------------
public Plugin:myinfo = 
{
	name = "servertools",
	author = "mukunda",
	description = "Server configuration and maintenance tools",
	version = PLUGIN_VERSION,
	url = "http://www.mukunda.com/"
}

#define UPDATE_URL "http://www.mukunda.com/plugins/servertools3/servertools_updatefile.txt"

#define DPERMS ((FPERM_O_READ|FPERM_O_EXEC)|(FPERM_G_EXEC|FPERM_G_READ)|(FPERM_U_EXEC|FPERM_U_WRITE|FPERM_U_READ))

#include "servertools/globals.sp"
#include "servertools/operations.sp"
#include "servertools/hibernation.sp"
#include "servertools/curl.sp"
#include "servertools/get.sp"
#include "servertools/sync.sp"
 


#define SYNC_INTERVAL 60*60 // sync if server is started at least one hour after last sync

new tempfile_index;

//-------------------------------------------------------------------------------------------------
enum FileDomain {
	DOMAIN_ERROR,
	DOMAIN_FTP,
	DOMAIN_HTTP,
	DOMAIN_LOCAL,
	DOMAIN_WEB
	//DOMAIN_GAME
};

//-------------------------------------------------------------------------------------------------
public OnLibraryAdded(const String:name[]) {
    if( StrEqual(name, "updater") ) {
		Updater_AddPlugin(UPDATE_URL);
	}
}

//-------------------------------------------------------------------------------------------------
public OnPluginStart() {

	CreateConVar( "servertools_plugin_version", PLUGIN_VERSION, "ServerTools Plugin Version", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_DONTRECORD|FCVAR_REPLICATED );
	BuildPath( Path_SM, g_logfile, sizeof g_logfile, "logs/servertools.log" );
	InitTempFiles();
	
	g_text_extensions = CreateTrie(); 
	termcount_trie = CreateTrie();
	//g_pending_transfers = CreateArray();
	
	SetTrieValue( termcount_trie, "sm_cvar", 2 );
	SetTrieValue( termcount_trie, "exec", 2 );
	// todo...

	Operations_Init();
	
	RegServerCmd( "st_id", Command_id, "Print ID and groups" );
	RegServerCmd( "st_status", Command_status, "Get Operation Status" );
	RegServerCmd( "st_test", Command_test, "test function" );
	
	RegServerCmd( "st_sync", Command_sync, "Synchronize server files" );
	RegServerCmd( "st_get", Command_get, "Get file" );
	RegServerCmd( "st_remove", Command_remove, "Delete file" );
	
	LoadConfigs();
	
	if( LibraryExists("updater") ) {
		Updater_AddPlugin(UPDATE_URL);
	}
	
	if( GetTime() >= (GetLastSync() + SYNC_INTERVAL) ) {
		LogToFile( g_logfile, "Performing sync..." );
		StartSync( "all" );
	}
}

//-------------------------------------------------------------------------------------------------
public OnConfigsExecuted() {
	
}
 


//-------------------------------------------------------------------------------------------------
public Action:Command_id( args ) {
	LoadIDConfig();
	PrintToServer( "[ST] id = \"%s\"", my_id );
	PrintToServer( "[ST] groups = \"%s\"", my_groups );
	return Plugin_Handled;
}

//-------------------------------------------------------------------------------------------------
KvSetHandle( Handle:kv, const String:key[], Handle:value ) {
	KvSetNum( kv, key, _:value );
}

//-------------------------------------------------------------------------------------------------
Handle:KvGetHandle( Handle:kv, const String:key[] ) {
	return Handle:KvGetNum( kv, key, _:INVALID_HANDLE );
}

//-------------------------------------------------------------------------------------------------
Handle:LoadKVConfig( const String:name[], const String:path[] ) {
	decl String:configpath[256];
	BuildPath( Path_SM, configpath, sizeof(configpath), "configs/%s", path );
	if( !FileExists( configpath ) ) {
		LogToFile( g_logfile, "Config file missing: \"%s\"", path );
		return INVALID_HANDLE;
	}
	new Handle:kv = CreateKeyValues( name );
	if( !FileToKeyValues( kv, configpath ) ) {
		LogToFile( g_logfile, "Error loading config file \"%s\"", path );
		CloseHandle(kv);
		return INVALID_HANDLE;
	}
	return kv;
}

//-------------------------------------------------------------------------------------------------
LoadMainConfig() {
	new Handle:kv = LoadKVConfig( "servertools", "servertools.cfg" );
	if( kv == INVALID_HANDLE ) return;
	
	if( KvJumpToKey( kv, "remote" ) ) {
		KvGetString( kv, "url", g_remote_url, sizeof g_remote_url, "" );
		KvGetString( kv, "key", g_remote_key, sizeof g_remote_key, "" );
		KvGetString( kv, "dir", g_remote_dir, sizeof g_remote_dir, "files" );
		KvGetString( kv, "dir_nosync", g_remote_dirns, sizeof g_remote_dirns, "files_nosync" );
		KvGoBack(kv);
		
		BuildURLRequestParam();
	}
	
	if( KvJumpToKey( kv, "syncpaths" ) ) {
		if( KvGotoFirstSubKey( kv, false ) ) {
			do {
				decl String:path[128];
				KvGetSectionName( kv, path, sizeof path );
				AddPathSlash( path, sizeof path );
				if( !FormatLocalPath( path, sizeof path, path ) ) {
					LogToFile( g_logfile, "Error: bad path in syncpaths: %s", path );
					continue;
				}
				decl String:flags[64];
				decl String:group[64];
				group = "ungrouped";
				decl String:params[64];
				KvGetString( kv, NULL_STRING, params, sizeof params );
				new index = 0;
				new iflags = 0;
				if( GetNextArg( params, index, flags, sizeof flags ) ) {
					if( StrContains(flags,"a") >= 0 ) iflags |= SYNCPATHFLAG_ALL;
					if( StrContains(flags,"p") >= 0 ) iflags |= SYNCPATHFLAG_PLUGINS;
					if( StrContains(flags,"r") >= 0 ) iflags |= SYNCPATHFLAG_RECURSIVE;
					
					if( index != -1 )
						GetNextArg( params, index, group, sizeof group );
				}
				 
				WritePackString( g_sync_paths, path );
				WritePackString( g_sync_paths, group );
				WritePackCell( g_sync_paths, iflags );
			} while( KvGotoNextKey(kv,false) );
			KvGoBack( kv );
		}
		KvGoBack( kv );
	}
 
	
	
	decl String:list[128];
	decl String:ext[32];
	KvGetString( kv, "textfiles", list, sizeof list );
	new index = 0;
	while( GetNextArg( list, index, ext, sizeof ext ) ) {
		SetTrieValue( g_text_extensions, ext, 1, false );
	}
		
	CloseHandle( kv );
}

//-------------------------------------------------------------------------------------------------
LoadIDConfig() {
	my_id = "unknown";
	my_groups = "all";
	BuildURLRequestParam();

	new Handle:kv = LoadKVConfig( "servertools_id", "servertools_id.cfg" );
	if( kv == INVALID_HANDLE ) return;
	 
	KvGetString( kv, "id", my_id, sizeof(my_id), "UNKNOWNID" );
	KvGetString( kv, "Groups", my_groups, sizeof(my_groups), "" );
	
	BuildURLRequestParam();
	
	StrCat(my_groups,sizeof my_groups, " all" );
	TrimString(my_groups);
}

//-------------------------------------------------------------------------------------------------
LoadConfigs() {
	if( g_sync_paths ) CloseHandle( g_sync_paths );
	g_sync_paths = CreateDataPack();
	g_remote_url[0] = 0; 
	ClearTrie( g_text_extensions ); 
	
	
	
	LoadIDConfig();
	LoadMainConfig();
	
/*
	if( KvJumpToKey( kv, "ftp" ) ) {
		KvGetString( kv, "url", ftp_url, sizeof ftp_url );
		AddPathSlash( ftp_url, sizeof ftp_url );
		
		decl String:username[256];
		decl String:password[256];
		KvGetString( kv, "username", username, sizeof username );
		KvGetString( kv, "password", password, sizeof password );
		Format( ftp_auth, sizeof ftp_auth, "%s:%s", username, password );
		KvRewind(kv);
	}

	if( KvJumpToKey( kv, "http" ) ) {
		KvGetString( kv, "url", http_url, sizeof http_url );
		AddPathSlash( http_url, sizeof http_url );
		KvGetString( kv, "listing", http_listing_file, sizeof http_listing_file, "listing.php" );
		KvRewind(kv);
	}
	
	if( KvJumpToKey( kv, "sync" ) ) {
		KvGetString( kv, "url", sync_url, sizeof sync_url );
		AddPathSlash( sync_url, sizeof sync_url );
		KvGetString( kv, "manifest", sync_manifest, sizeof sync_manifest, "manifest.php" );
		KvGetString( kv, "listing", sync_listing, sizeof sync_listing, "sync_list.php" );
		sync_checkplugins = KvGetNum( kv, "checkplugins", 0 );
		KvRewind(kv);
	}

	{
		// file filters
		
		ClearTrie( pp_trie );
		ClearTrie( sync_binaries );
		
		decl String:list[128];
		decl String:ext[32];
		KvGetString( kv, "preprocess", list, sizeof list );
		new index = 0;
		while( GetNextArg( list, index, ext, sizeof ext ) ) {
			SetTrieValue( pp_trie, ext, 1, false );
		}
		
		if( KvJumpToKey( kv, "sync" ) ) {
			KvGetString( kv, "binaries", list, sizeof list );
			index = 0;
			while( GetNextArg( list, index, ext, sizeof ext ) ) {
				SetTrieValue( sync_binaries, ext, 1, false );
			}
			KvGoBack( kv );
		}
	}
	*/
 
}

//-------------------------------------------------------------------------------------------------
BuildURLRequestParam() {
	decl String:groups[64][64];
	new count = ExplodeString( my_groups, " ", groups, sizeof groups, sizeof groups[] );
	FormatEx( g_url_request_params, sizeof g_url_request_params, "id=%s&key=%s&groups=", my_id, g_remote_key );
	
	for( new i = 0; i < count; i++ ) {
		TrimString( groups[i] );
		StrCat( g_url_request_params, sizeof g_url_request_params, groups[i] );
		if( i != count-1 )
			StrCat( g_url_request_params, sizeof g_url_request_params, "/" );
	}
}



//-------------------------------------------------------------------------------------------------
public Action:Command_status( args ) {
	decl String:arg[32];
	if( args == 0 ) {
		PrintToServer( "[ST] Usage: st_status <id> - print operation status" );
		return Plugin_Handled;
	}
	GetCmdArg( 1, arg, sizeof arg );
	new id = StringToInt( arg );
	
	PrintOperationStatus( id );
	 
	
	return Plugin_Handled;
}

//-------------------------------------------------------------------------------------------------
bool:GetNextArg( const String:input[], &index, String:arg[], maxlen ) {
	if( index==-1 ) return false;
	new a = BreakString( input[index], arg, maxlen );
	if( a == -1 ) {
		index = -1;
	} else {
		index += a;
	}
	return true;
}

//-------------------------------------------------------------------------------------------------
bool:InGroup( const String:id[] ){
	new index = 0;
	decl String:arg[64];
	
	while( GetNextArg( my_groups, index, arg, sizeof arg ) ) {
		if (StrEqual(id,arg,false) ) return true;
	}
	if( StrEqual( id, my_id ) ) return true;
	return false;
}

//-------------------------------------------------------------------------------------------------
FixupTargetString( const String:source[], String:dest[], maxlen ) {
	new read, write;
	
	new c;
	do {
		c = source[read++];
		if( c == '+' || c == '-' ) {
			dest[write++] = ' '; // insert spaces before + or -
			if( write == maxlen ) break;
			// skip whitespace after + or - 
			if( source[read] == ' ' || source[read] == 9 ) read++;
		}
		dest[write++] = c;
		if( write == maxlen ) break;
	} while( c != 0 );
	
	dest[maxlen-1] = 0; // ensure null termination
}

//-------------------------------------------------------------------------------------------------
bool:IsTarget( const String:target[] ) {
	// target string format: "group -group group+group+group -group+group"
	// - means exclude a group, groups are processed left to right
	// + combines groups, "a+b" means the server must be in both,
	// "-a+b" means exclude servers that are in both
	new index = 0;
	decl String:arg[64];
	decl String:nextarg[64];
	
	decl String:target2[512];
	FixupTargetString( target, target2, sizeof target2 );
	//strcopy( target2, sizeof target2, target );
	//ReplaceString( target2, sizeof target2, "-", " -" );
	//ReplaceString( target2, sizeof target2, "+", " +" );
	
	 
	new bool:is_target = false;
	
	if( !GetNextArg( target2, index, arg, sizeof arg ) ) {
		return false; // empty target string
	} 
	
	new bool:found_new_arg;
	do { 
		new bool:negate;
		
		negate=false;
		if( arg[0] == '-' ) {
			// exclusion mode
			negate=true;
			
			// strip "-"
			Format( arg, sizeof arg, "%s", arg[1] );
		} else if( arg[0] == '+' ) {
			// plus found at start of target, print warning maybe?
			
			// strip plus
			Format( arg, sizeof arg, "%s", arg[1] );
		}
		
		new bool:targetted = InGroup(arg);
		found_new_arg = false;
		
		while( GetNextArg( target2, index, nextarg, sizeof nextarg ) ) {
			if( nextarg[0] == '+' ) {
				// server must match all + groups to be targetted
				if( !targetted ) continue;
				if( !InGroup( nextarg[1] ) ) {
					// break target, we still need to iterate over additional "+" groups
					targetted = false; 
				}
			} else {
				// next target is a new group/combination, copy to arg
				strcopy( arg, sizeof arg, nextarg );
				found_new_arg = true;
				break;
			}
		}
		
		if( targetted ) {
			if( negate ) 
				is_target = false;
			else 
				is_target = true;
		} 
	} while( found_new_arg );
	return is_target;
}

//-------------------------------------------------------------------------------------------------
PreprocessFile( Handle:op, String:file[], maxlen ) {
	// processes a given file (tempfile!) and replaces file (the string passed in) with the new temp filename
	decl String:newfile[256];
	GetTempFile(newfile, sizeof newfile);
	
	new Handle:infile = OpenFile( file, "r" );
	if( !infile ) {
		OperationError( op, "Couldn't read file: %s", file );
		return;
	}
	new Handle:outfile = OpenFile( newfile, "w" );
	if( !outfile ) {
		CloseHandle(infile);
		OperationError( op, "Couldn't write file: %s", file );
		return;
	}

	new bool:output_disabled = false;
	new Handle:nest = CreateStack();

	while( !IsEndOfFile(infile) ) {
		decl String:line[1024];
		decl String:work[1024];
		if( !ReadFileLine( infile, line, sizeof line ) ) continue;
		// strip cr/lr
		ReplaceString( line, sizeof line, "\r", "" );
		ReplaceString( line, sizeof line, "\n", "" );

		strcopy( work, sizeof work, line );
		TrimString(work);

		// strip comments
		new comment = StrContains( work, "//" );
		if( comment != -1 ) {
			work[comment] = 0;
		}

		new argindex = 0;
		decl String:arg[64];
		if( work[0] == '#' ) {
			// preprocessor command
			GetNextArg( work, argindex, arg, sizeof arg );
			if( StrEqual( arg, "#if" ) || StrEqual(arg, "#ifnot") ) {
				// if statement

				new mode = StrEqual( arg, "#if" ) ? 1 : 0;
				decl String:groups[128];
				strcopy( groups, sizeof groups, work[argindex] );
				TrimString(groups);
				StripQuotes(groups);
				TrimString(groups);
				  
				PushStackCell( nest, output_disabled );

				if( output_disabled ) continue;
				
				if( mode ) {
					 
					new bool:found;
					do {
						if( IsTarget( groups ) ) {
							found=true; // group match!
							break;
						}
					} while( GetNextArg( work, argindex, arg ,sizeof arg ) );
					if( !found ) output_disabled = true; // not in group!
				} else {
					do {
						if( IsTarget( groups ) ) {
							output_disabled = true;
							break;
						}
					} while( GetNextArg( work, argindex, arg ,sizeof arg ) );
				}
				 

			} else if( StrEqual( arg, "#endif" ) ) {
				if( IsStackEmpty( nest ) ) {
					OperationError( op, "#endif without #if !!!", arg );
					continue;
				}
				PopStackCell( nest, output_disabled );
				// end if
			} else {
				OperationError( op, "Unknown Preprocessor Directive: %s", arg );
			}
			continue;
		} else {
			if( !output_disabled ) {
				WriteFileLine( outfile, line );
			}
			
		}
	}

	CloseHandle(outfile);
	CloseHandle(infile);
	DeleteFile( file );
	strcopy( file, maxlen, newfile );
}

//-------------------------------------------------------------------------------------------------
GetFileExt( String:ext[], maxlen, const String:file[] ) {
	new index = FindCharInString( file, '.', true );
	if( index == -1 ) {
		Format(ext,maxlen,"");
	} else {
		Format( ext, maxlen, file[index+1] );
	}
}

//-------------------------------------------------------------------------------------------------
bool:IsTrieSet( Handle:trie, const String:entry[] ) {
	new dummy;
	return GetTrieValue( trie, entry, dummy );
} 


//-------------------------------------------------------------------------------------------------
AddPathSlash( String:path[], maxlen ) {
	new sl = strlen(path);
	if( sl != 0 ) {
		if( path[sl-1] != '/' ) {
			StrCat( path, maxlen, "/" );
		}
	} 
}

StripPathSlash( String:path[] ) {
	new sl = strlen(path);
	if( sl != 0 ) {
		if( path[sl-1] == '/' ) {
			path[sl-1] = 0;
		}
	} 
}

//-------------------------------------------------------------------------------------------------
StripFileName( String:stripped[], maxlen, const String:path[] ) {
	strcopy( stripped, maxlen, path );
	new filestart = FindCharInString(path,'/',true);
	if( filestart == -1 ) {
		filestart = 0;
	} else {
		filestart++;
	}
	stripped[filestart] = 0;
}

//-------------------------------------------------------------------------------------------------
bool:FormatLocalPath( String:output[], maxlen, const String:path[] ) {
	if( strncmp( path, "sm/", 3 ) == 0 ) {
		// sourcemod path
		BuildPath( Path_SM, output, maxlen, "%s", path[3] );
		
	} else if( strncmp( path, "game/", 5 ) == 0 ) {
		Format( output, maxlen, path[5] );
		
	} else if( strncmp( path, "cfg/", 4 ) == 0 ) {
		Format( output, maxlen, "cfg/%s", path[4] );
		
	} else if( strncmp( path, "pl/", 3 ) == 0 ) {
		BuildPath( Path_SM, output, maxlen, "plugins/%s.smx", path[3] ); 
	} else if( strncmp( path, "tr/", 3 ) == 0 ) {
		BuildPath( Path_SM, output, maxlen, "translations/%s.phrases.txt", path[3] ); 
	} else if( strncmp( path, "sc/", 3 ) == 0 ) {
		BuildPath( Path_SM, output, maxlen, "configs/%s", path[3] ); 
	} else {
		return false;
	}
	
	// backslashes are for kids
	ReplaceString( output, maxlen, "\\", "/" );
	return true;
}

//-------------------------------------------------------------------------------------------------
InitTempFiles() {
	decl String:path[128];
	BuildPath( Path_SM, path, sizeof path, "data/servertools_tempfiles" );
	if( !DirExists( path ) ) {
		CreateDirectory( path, DPERMS );
		return;
	} else {
		// cleanup...
		new Handle:dir = OpenDirectory( path );
		decl String:file[128];
		new FileType:ft;
		
		while( ReadDirEntry( dir, file, sizeof file, ft ) ) {
			if( StrEqual( file, "." ) ) continue;
			if( StrEqual( file, ".." ) ) continue;
			if( ft == FileType_File ) {
				decl String:filepath[128];
				Format( filepath, sizeof filepath, "%s/%s", path, file );
				DeleteFile( filepath );
			}
		}
	}
}

//-------------------------------------------------------------------------------------------------
GetTempFile( String:path[], maxlen ) {
	BuildPath( Path_SM, path, maxlen, "data/servertools_tempfiles/servertools.%d.temp", tempfile_index++ );
}


//-------------------------------------------------------------------------------------------------
StripFilePath( String:file[], maxlen, const String:path[] ) {
	new filestart = FindCharInString(path,'/',true);
	if( filestart == -1 ) {
		filestart = 0;
	} else {
		filestart++;
	}
	strcopy( file, maxlen, path[filestart] );
}


//-------------------------------------------------------------------------------------------------
PrimeFileTarget( const String:file[] ) {
	// creates directories from file path if they dont exist and deletes existing file
	// assumes forward slashes "/" are used

	decl String:work[512];
	strcopy( work, sizeof(work), file );

	// example test/test2/../file

	// iterate through directory path and create missing directories
	new position = 0;
	new index;
	do {
		index = FindCharInString( file[position], '/' );
		if( index == -1 ) break;
		index += position;
		position = index+1;

		strcopy( work, sizeof(work), file );
		work[index] = 0;
		decl String:dirname[256];
		StripFilePath( dirname, sizeof(dirname), work );
		if( StrEqual(dirname, ".") ) continue;
		if( StrEqual(dirname, "..") ) continue; // ? um this will break..
		if( !DirExists( work ) ) {
			CreateDirectory( work,DPERMS );
		}
	} while(index!=-1);

	if( FileExists( file ) ) {
		return( DeleteFile(file) );
	}
	return true;
}


//-------------------------------------------------------------------------------------------------
public Action:Command_test( args ) {

	PrintToServer( "[ST] testing testing 1-2-3" );

	return Plugin_Handled;
}
 
bool:TryDeleteFile( const String:file[] ) {
	if( FileExists(file) ) {
		return DeleteFile(file);
	}
	return true;
}
