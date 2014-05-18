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

#define PLUGIN_VERSION "1.3.3"

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
	name = "server tools",
	author = "mukunda",
	description = "Server Configuration/Maintenance Tools",
	version = PLUGIN_VERSION,
	url = "http://www.mukunda.com/"
}

#define UPDATE_URL "http://www.mukunda.com/plugins/servertools/servertools_updatefile.txt"

//-------------------------------------------------------------------------------------------------
new CURLDefaultOpt[][2] = {
	{_:CURLOPT_NOSIGNAL,		1}, ///use for threaded only
	{_:CURLOPT_NOPROGRESS,		1},
	{_:CURLOPT_TIMEOUT,			30},
	{_:CURLOPT_CONNECTTIMEOUT,	60},
	{_:CURLOPT_VERBOSE,			0}
};

#define DPERMS ((FPERM_O_READ|FPERM_O_EXEC)|(FPERM_G_EXEC|FPERM_G_READ)|(FPERM_U_EXEC|FPERM_U_WRITE|FPERM_U_READ))

new Handle:pp_trie; // file extensions that should run the preprocessor
new Handle:termcount_trie; // trie for looking up terms to get default termcount values (for command matching)

new String:my_id[64];
new String:mygroups[256];

new String:logfile[128];

//-------------------------------------------------------------------------------------------------
new String:ftp_url[512]; 
new String:ftp_auth[256];
//new String:ftp_dir[512];

new cfgfind_total;
//new bool:cfgfind_partial;
//new bool:cfgfind_all;
#define CFGFIND_MAX 20

#define SYNC_INTERVAL 60*60*20 // sync after 20 hours

new String:http_url[512];
new String:http_listing_file[256];

new String:sync_url[512];
new String:sync_manifest[256];
new String:sync_listing[256];
new Handle:sync_binaries;
new sync_checkplugins;

new String:url_request_params[256]; // the id and groups for placing in an url

new bool:cfg_updater;

new op_state;
new String:op_name[64];
//new String:operation_response[256];
//new operation_code;

//new operation_files_failed;
new operation_files_transferred;
new operation_errors;
//new operation_threads;

//new Handle:op_curl;
new Handle:op_stack;
new Handle:op_logfile;
new String:op_logfile_path[128];

new Handle:op_filepack = INVALID_HANDLE;

new bool:op_directory_recursive;
new bool:op_delete_source;
new bool:initial_sync = true;

// working directories
new String:path_source[512]; // source path ie "ftp://poop.com/root/" ends with slash
new String:path_source_httplisting[512]; // source path for directory listing ie "http://poop.com/root/listing.php?path=/" ends with slash
new String:path_dest[512]; // dest path ie "addons/sourcemod/configs/" ends with slash or is empty
new FileDomain:dl_source_domain;
new String:op_pattern[128];
new Handle:op_pattern_regex = INVALID_HANDLE;

new tempfile_index;

new Handle:sv_hibernate_when_empty; 
new c_hibernate_when_empty; 
//new bool:ignore_hibernate_change;
//new bool:force_wake;

//-------------------------------------------------------------------------------------------------
// sync operation

new Handle:sync_list = INVALID_HANDLE;
new sync_list_next = 0;
new Handle:sync_updates = INVALID_HANDLE;
new Handle:sync_hashes = INVALID_HANDLE;
new Handle:sync_plugins = INVALID_HANDLE;
new bool:sync_reinstall;

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
enum {
	STATE_READY,	// waiting for operation to be executed
	STATE_BUSY,		// an operation is in progress
	STATE_COMPLETED // waiting for remote to read response and reset
};

//-------------------------------------------------------------------------------------------------
public OnLibraryAdded(const String:name[])
{
    if( cfg_updater && StrEqual(name, "updater") )
    {
        Updater_AddPlugin(UPDATE_URL);
    }
}

//-------------------------------------------------------------------------------------------------
public OnPluginStart() {

	CreateConVar( "servertools_plugin_version", PLUGIN_VERSION, "ServerTools Plugin Version", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_DONTRECORD|FCVAR_REPLICATED );
	BuildPath( Path_SM, logfile, sizeof logfile, "logs/servertools.log" );
	InitTempFiles();
	
	pp_trie = CreateTrie();
	sync_binaries = CreateTrie();
	termcount_trie = CreateTrie();
	SetTrieValue( termcount_trie, "sm_cvar", 2 );
	SetTrieValue( termcount_trie, "exec", 2 );
	// todo...
	
	sv_hibernate_when_empty = FindConVar( "sv_hibernate_when_empty" );
	//if( sv_hibernate_when_empty != INVALID_HANDLE ) {
	//	HookConVarChange( sv_hibernate_when_empty, OnHibernateChanged );
	//}

	RegServerCmd( "st_copy", Command_copy, "Copy File" );
	
	RegServerCmd( "st_rename", Command_rename, "Rename File" );
	RegServerCmd( "st_dir", Command_dir, "Directory Listing" );
	RegServerCmd( "st_delete", Command_delete, "Delete File" );
	RegServerCmd( "st_mkdir", Command_mkdir, "Create Directory" );
	RegServerCmd( "st_id", Command_id, "Get Identifier" );
	RegServerCmd( "st_cfgfind", Command_cfgfind, "Search all cfg files for a cvar/command" );
	RegServerCmd( "st_cfgedit", Command_cfgedit, "Edit config file" );
	RegServerCmd( "st_view", Command_view, "View a file" );
	RegServerCmd( "st_new", Command_new, "Create New File" );
	RegServerCmd( "st_edit", Command_edit, "Edit File" );
	 
	RegServerCmd( "st_reloadconfig", Command_reloadconfig, "Reload Configuration" );
	RegServerCmd( "st_status", Command_status, "Get System Status, pass \"reset\" to reset on complete status" );
	RegServerCmd( "st_reset", Command_reset, "Prepare for another operation" );
	RegServerCmd( "st_test", Command_test, "test function" );
	
	RegServerCmd( "st_sync", Command_sync, "Sychronize server files" );
	
	LoadConfig();
	
	
	
	if( cfg_updater && LibraryExists("updater") ) {
		Updater_AddPlugin(UPDATE_URL);
	}
	
	
}

public OnConfigsExecuted() {
	if( GetTime() >= (GetLastSync() + SYNC_INTERVAL) ) {
		LogToFile( logfile, "Performing daily sync..." );
		PerformSync();
	}
}
/*
//-------------------------------------------------------------------------------------------------
public OnHibernateChanged( Handle:convar, const String:oldval[], const String:newval[] ) {
	if( ignore_hibernate_change ) {
		ignore_hibernate_change = false;
		return;
	}
	
	c_hibernate_when_empty = GetConVarInt( sv_hibernate_when_empty );
	if( force_wake && c_hibernate_when_empty != 0 ) {
		ignore_hibernate_change = true;
		SetConVarInt( sv_hibernate_when_empty, 0 );
	}
}*/
/*
//-------------------------------------------------------------------------------------------------
public Action:UpdaterDelay(Handle:timer) {
	if( cfg_updater && LibraryExists("updater") ) {
		Updater_AddPlugin(UPDATE_URL);
	}
	return Plugin_Handled;
}*/

//-------------------------------------------------------------------------------------------------
PrintFileHelp() {
	PrintToServer( "source,dest can be in these formats:" );
	 
	PrintToServer( "sm/... - local path relative to sourcemod folder" );
	PrintToServer( "game/... - local path relative to game root" );
	PrintToServer( "cfg/... - local path relative to cfg folder" ); 
	PrintToServer( "pl/... - local path relative to plugins folder, \".smx\" is appended" );
	PrintToServer( "tr/... - local path relative to translations folder, \".txt\" is appended" );
	PrintToServer( "sc/... - local path relative to sourcemod configs folder" );
	PrintToServer( "ftp/... - remote path relative to ftp directory" );
	PrintToServer( "http/... - remote path relative to http directory (read only)" );
	PrintToServer( "web/... - remote path to arbitrary http url" );
	
}

//-------------------------------------------------------------------------------------------------
bool:ReadyForNewOperation() {
	if( op_state == STATE_READY ) return true;
	
	if( op_state == STATE_BUSY ) {
		PrintToServer( "[ST] An operation is already in progress!" );
		return false;
	} else if( op_state == STATE_COMPLETED ) {
		PrintToServer( "[ST] An operation result is waiting; use st_status to read it, and then st_reset." );
		return false;
	}
	return false;
}

//-------------------------------------------------------------------------------------------------
PrintCopyUsage() {
	PrintToServer( "Usage: st_copy [-r] [-m] <source> <dest>" );
	PrintToServer( "-r : directory recursive" );
	PrintToServer( "-m : delete source files (move)" );
	PrintFileHelp();
}

//-------------------------------------------------------------------------------------------------
public Action:Command_id( args ) {
	PrintToServer( "[ST] id = \"%s\"", my_id );
	PrintToServer( "[ST] groups = \"%s\"", mygroups );
	return Plugin_Handled;
}

//-------------------------------------------------------------------------------------------------
bool:CommandMatch( const String:line[], const String:terms[], termcount, bool:partial, bool:matchall ) {
	
	new index1,index2;
	decl String:term[64];
	GetNextArg( terms, index2, term, sizeof term );
	 
	// todo: trie for poopies
	if( termcount == 0 ) {
		if( !GetTrieValue( termcount_trie, term, termcount ) ) {
			termcount = 1;
		}
	}

	decl String:work[1024];
	strcopy( work, sizeof work, line );
	new comment = StrContains( work, "//" );
	if( comment != -1 ) work[comment] = 0;

	if( matchall ) {
		return StrContains( work, term, false ) >= 0;
	} else {
		index2 = 0;
		for( new i = 0; i < termcount; i++ ) {
			decl String:arg[64];
			if( !GetNextArg( terms, index2, term, sizeof term ) ) return true;
			if( !GetNextArg( work, index1, arg, sizeof arg ) ) return false;
			

			if( partial ) {
				if( !StrEqual( arg, term, false ) ) {
					return false;
				}
			} else {
				if( StrContains( arg, term, false) < 0 ) {
					return false;
				}
			}
		}

		return true;
		/*
		decl String:arg[64];
		new nextarg = BreakString( work, arg, sizeof arg );
		if( StrEqual( arg, "sm_cvar", false ) && nextarg != -1 ) {
			// sm_cvar command, use next arg!
			BreakString( work[nextarg], arg, sizeof arg );
		}

		if( cfgfind_partial ) {
			return StrContains( arg, term, false ) >= 0;
		} else {
			return StrEqual( arg, term, false );
		}*/
	}
}

//-------------------------------------------------------------------------------------------------
ConfigFileContainsCommand( const String:filepath[], const String:term[], termcount, bool:partial, bool:matchall ) {
	
	new Handle:file = OpenFile( filepath, "r" );
	if( file == INVALID_HANDLE ) return 0;
	 
	decl String:line2[1024];
	new linecounter = 0;

	new findings = 0;

	while( !IsEndOfFile( file ) ) {
		linecounter++;
		if( !ReadFileLine( file, line2, sizeof line2 ) ) continue;
		TrimString(line2);
		 
		new bool:found;
		found = CommandMatch( line2, term, termcount, partial, matchall );
		 

		if( found ) {
			PrintToServer( "[ST] %s(%d): %s", filepath, linecounter, line2 );
			findings++;
			cfgfind_total++;
			if( cfgfind_total >= CFGFIND_MAX ) break;
		}
		
	}

	CloseHandle( file );
	return findings;
}

//-------------------------------------------------------------------------------------------------
ConfigSearch( const String:path[], const String:term[], termcount, bool:partial, bool:matchall ) {
	new Handle:dir = OpenDirectory( path );

	decl String:entry[128];
	new FileType:ft;
	while( ReadDirEntry( dir, entry, sizeof entry, ft ) ) {
		if( ft == FileType_Directory ) {
			if( StrEqual(entry,".") ) continue;
			if( StrEqual(entry,"..") ) continue;
			Format( entry, sizeof entry, "%s%s/", path,entry );
			ConfigSearch( entry, term, termcount, partial, matchall );

		} else if( ft == FileType_File ) {

			
			
			Format( entry, sizeof entry, "%s%s", path,entry );
			ConfigFileContainsCommand( entry, term, termcount, partial, matchall );
			
			if( cfgfind_total >= CFGFIND_MAX ) break;
		
		}
	}
	CloseHandle( dir );
}

//-------------------------------------------------------------------------------------------------
public Action:Command_cfgfind( args ) {
	
	if( !ReadyForNewOperation() ) return Plugin_Handled;

	// search for command
	if( args < 1 ) {
		PrintToServer( "Usage: st_cfgfind [-pa1..9] <command>" );
		PrintToServer( "-p : match on partial find" );
		PrintToServer( "-a : search all text and not just the primary terms" );
		PrintToServer( "-1..9 : number of terms to match (default depends on command)" );
		return Plugin_Handled;
	}

	decl String:term[128];
	term[0] = 0;

	new bool:opt_partial = false;
	new bool:opt_matchall = false;
	new opt_termcount= 0;
	
	for( new i = 0; i < args; i++ ) {
		decl String:arg[128];
		GetCmdArg( i+1, arg, sizeof(arg) );
		if( arg[0] == '-' ) {
			if( StrEqual( arg, "-p" ) ) {
				opt_partial = true;
			} else if( StrEqual( arg, "-a" ) ) {
				opt_matchall = true;
			} else if( strlen(arg) == 2 && arg[1] >= '1' && arg[1] <= '9' ) {
				opt_termcount = arg[1] - '0';
			} else {
				PrintToServer( "[ST] invalid option: %s", arg );
				return Plugin_Handled;
			}
		} else {
			if( term[0] == 0 ) {
				strcopy(term, sizeof(term), arg);
			} else {
				Format( term, sizeof term, "%s %s", term, arg );
				//PrintToServer( "[ST] too many arguments." );
				//return Plugin_Handled;
			}
		}
		
	}

	if( term[0] == 0 ) {
		PrintToServer( "[ST] invalid arguments" );
		return Plugin_Handled;
	}
	
	cfgfind_total = 0;
	ConfigSearch( "cfg/", term, opt_termcount, opt_partial, opt_matchall );
	PrintToServer( "[ST] %d matches%s.", cfgfind_total, cfgfind_total == CFGFIND_MAX ? " (limit reached)" :"" );

	return Plugin_Handled;
} 

//-------------------------------------------------------------------------------------------------
SetConfig( const String:localfile[], bool:ignoredups, bool:removeonly, termcount, const String:command[] ) {

	new bool:command_written = false;
	/*
	decl String:commandterm[64];
	{
		new index = BreakString( command, commandterm, sizeof commandterm );
		if( StrEqual( commandterm, "sm_cvar", false ) ) {
			BreakString( command[index], commandterm, sizeof commandterm );
		}
	}*/
	
	decl String:oldfile[256];
	if( !FormatLocalPath( oldfile, sizeof oldfile, localfile ) ) {
		PrintToServer( "[ST] invalid file" );
		return;
	}
	decl String:newfile[256];
	GetTempFile( newfile, sizeof newfile );
	
	new Handle:outfile = OpenFile( newfile, "w" );
	if( outfile == INVALID_HANDLE ) {
		PrintToServer( "[ST] internal error" );
		return;
	}
	new Handle:infile = OpenFile( oldfile, "r" );
	if( infile == INVALID_HANDLE ) {
		CloseHandle(outfile);
		DeleteFile( newfile );
		PrintToServer( "[ST] couldn't open %s for reading", oldfile );
		return;
	}

	
	PrintToServer( "[ST] editing config... %s", oldfile );

	while( !IsEndOfFile( infile ) ) {
		decl String:line[1024];
		if( !ReadFileLine( infile, line, sizeof line ) ) continue;
		ReplaceString( line, sizeof line, "\r", "" );
		ReplaceString( line, sizeof line, "\n", "" );

		if( !ignoredups ) {
			if( CommandMatch( line, command, termcount, false, false ) ) {
				// command found
				if( !command_written ) {
					// output command

					if( !removeonly ) { // these two options arent meant to go together but whatever...
						command_written = true;
						WriteFileLine( outfile, command );
					}
				}
			} else {
				WriteFileLine( outfile, line );
			}

		} else {
			WriteFileLine( outfile, line );
		}
	}

	if( !command_written ) {
		if( !removeonly ) {
			command_written = true;
			WriteFileLine( outfile, command );
		}
	}

	CloseHandle( outfile );
	CloseHandle( infile ) ;
	DeleteFile( oldfile );
	if( !RenameFile( oldfile, newfile ) ) {
		PrintToServer( "[ST] a very serious error occurred!" );
	}

}

//-------------------------------------------------------------------------------------------------
public Action:Command_cfgedit( args ) {

	
	if( !ReadyForNewOperation() ) return Plugin_Handled;

	decl String:localfile[256];
	decl String:command[256];
	localfile[0] = 0;
	command[0] = 0;
	new bool:badargs = false;

	new bool:ignoredups = false;
	new bool:removeonly = false;

	new termcount = 0;

	for( new i = 0; i < args; i++ ) {
		decl String:arg[256];
		GetCmdArg( i+1,arg,sizeof(arg) );
		if( arg[0] == '-' ) {
			if( StrEqual(arg, "-a" ) ) {
				ignoredups=true;
			} else if( StrEqual( arg, "-r" ) ) {
				removeonly = true;
			} else if( strlen(arg) == 2 && arg[1] >= '1' && arg[1] <= '9' ) {
				termcount = arg[1] - '0';
			} else {
				badargs = true;
				break;
			}
		} else {
			if( localfile[0] == 0 ) {
				strcopy( localfile, sizeof(localfile), arg );
			} else {
				if( command[0] == 0 ) {
					strcopy( command, sizeof( command ), arg );
				} else {
					Format( command, sizeof command, "%s %s", command, arg );
				}
			}
		}
	}

	if( badargs || localfile[0] == 0 || command[0] == 0 ) {
		PrintToServer( "Usage: st_cfgedit [-ar1-9] <file> <command>" );
		PrintToServer( " -a : append to file without removing duplicates" );
		PrintToServer( " -r : remove matching commands only" );
		PrintToServer( " -1 : match first term only" );
		PrintToServer( " -2 : first two terms must match (use for commands!)" );
		PrintToServer( " -3..9 : first 3..9 terms must match" );
		
		return Plugin_Handled;
	}
	 

	SetConfig( localfile, ignoredups, removeonly, termcount, command );

	PrintToServer( "[ST] cfgedit complete!" );

	return Plugin_Handled;
}

//-------------------------------------------------------------------------------------------------
public Action:Command_view( args ) {

	
	if( !ReadyForNewOperation() ) return Plugin_Handled;

	if( args < 1 ) {
		PrintToServer( "Usage: st_view -xxx <file>" );
		PrintToServer( " -xxx: line to start viewing file" );
		return Plugin_Handled;
	}
	
	decl String:arg[256];
	new startline = 1;
	GetCmdArg( 1, arg, sizeof arg );
	if( arg[0] == '-' ) {
		startline = StringToInt( arg[1] );
		if( args < 2 ) { // god i hate humans
			PrintToServer( "[ST] missing filename..." );
			return Plugin_Handled;
		}
		GetCmdArg( 2, arg, sizeof arg );
	}
	decl String:path[256];
	if( !FormatLocalPath( path, sizeof path, arg ) ) {
		PrintToServer( "[ST] invalid path." );
		return Plugin_Handled;
	}

	

	new Handle:file = OpenFile( path, "r" );
	if( file == INVALID_HANDLE ) {
		PrintToServer( "[ST] Couldn't open file: %s", path );
		return Plugin_Handled;
	}

	PrintToServer( "[ST] Viewing contents of \"%s\"", path );
	PrintToServer( "--- begin ---" );
	decl String:line[1024];
	
	
	new lines =0;
	new maxlines=200;
	while( !IsEndOfFile( file ) && maxlines > 0 ) {
		if( !ReadFileLine( file, line, sizeof line ) ){
			line = "";
		}
		lines++;
		if( lines >= startline ) {
			ReplaceString( line, sizeof line, "\r", "" );
			ReplaceString( line, sizeof line, "\n", "" );
			PrintToServer( "%3d|%s", lines,line );
			maxlines--;
		}
		
	}
	CloseHandle(file);

	if( lines < startline ) {
		PrintToServer( "<file only has %d line%s>", lines, lines==1 ? "":"s" );
	}
	
	if( maxlines <= 0 ) {
		PrintToServer( "--- truncating output after 200 lines. ---" );
	} else {
		PrintToServer( "--- end ---" );
		PrintToServer( "[ST] file dump complete." );
	}

	return Plugin_Handled;
}

//-------------------------------------------------------------------------------------------------
public Action:Command_copy( args ) {

	if( !ReadyForNewOperation() ) return Plugin_Handled;

	if( args < 2 ) {
		PrintCopyUsage();
		return Plugin_Handled;
	}
	
	decl String:source[512];
	decl String:dest[512];

	new bool:directory_recursive = false;
	op_delete_source = false;
	
	new pos = 0;
	for( new i = 0; i < args; i++ ) {
		decl String:arg[512];
		GetCmdArg( i+1, arg, sizeof(arg) );
		if( arg[0] == '-' ) {
			// option arg
			if( StrEqual( arg[1], "r" ) ) {
				directory_recursive = true;
			} else if( StrEqual( arg[1], "m" ) ) {
				op_delete_source = true;
			} else {
				// unknown arg
			}
			// todo
		} else {
			if( pos == 0 ) {
				strcopy( source, sizeof(source), arg );
				pos++;
			} else if( pos == 1 ) {
				strcopy( dest, sizeof(dest), arg );
				pos++;
			}
		}
	}

	if( pos != 2 ) {
		PrintToServer( "Invalid Argument(s)" );
		PrintCopyUsage();
		return Plugin_Handled;
	}

	ReplaceString( source, sizeof(source), "\\", "/" );
	ReplaceString( dest, sizeof(dest), "\\", "/" );

	
	CopyFiles( source, dest, directory_recursive );
		
	return Plugin_Handled;
}

//-------------------------------------------------------------------------------------------------
public Action:Command_delete( args ) {

	if( !ReadyForNewOperation() ) return Plugin_Handled;

	if( args < 1 ) {
		PrintToServer( "Usage: st_delete <file> (local only)" );
		return Plugin_Handled;
	}
	decl String:arg[256];
	GetCmdArg( 1, arg, sizeof(arg) );
	decl String:path1[256];
	if( !FormatLocalPath( path1, sizeof path1, arg )  ) {
		PrintToServer( "[ST] error: invalid file" );
		return Plugin_Handled;
	}
	
	PrintToServer( "[ST] attemping to delete: %s", path1 );
	if( DeleteFile( path1 ) ) {
		PrintToServer( "[ST] file deleted successfully" );
	} else {
		PrintToServer( "[ST] error: couldn't delete file!" );
	}
	
	return Plugin_Handled;	
}

//-------------------------------------------------------------------------------------------------
public Action:Command_new( args ) {
	if( !ReadyForNewOperation() ) return Plugin_Handled;

	if( args < 1 ) {
		PrintToServer( "Usage: st_new <filepath>" );
		return Plugin_Handled;
	}

	decl String:arg[256];
	GetCmdArg( 1, arg, sizeof(arg) );
	decl String:path[256];
	if( !FormatLocalPath( path, sizeof path, arg )  ) {
		PrintToServer( "[ST] error: invalid path" );
		return Plugin_Handled;
	}

	new Handle:file = OpenFile( path, "wb" );
	if( file == INVALID_HANDLE ) {
		PrintToServer( "[ST] Couldn't create file!" );
	} else {
		PrintToServer( "[ST] \"%s\" created!", path );
		CloseHandle(file);
	}
	
	return Plugin_Handled;
}

StripText( String:line[] ) {
	new i;
	for( i = 0; line[i]; i++ ) {
		if( line[i] == ' ' || line[i] == 9 ) continue;
		break;
	}
	line[i] = 0;
}

//-------------------------------------------------------------------------------------------------
EditFile( const String:filename[], replaceline, const String:text[], bool:preserve_indent ) {

	decl String:newfile[256];
	GetTempFile( newfile, sizeof newfile );
	new Handle:outfile = OpenFile( newfile, "w" );
	if( outfile == INVALID_HANDLE ) {
		PrintToServer( "[ST] internal error" );
		return;
	}
	new Handle:infile = OpenFile( filename, "r" );
	if( infile == INVALID_HANDLE ) {
		CloseHandle(outfile);
		DeleteFile( newfile );
		PrintToServer( "[ST] couldn't open %s for reading", filename );
		return;
	}

	PrintToServer( "[ST] editing file... %s", filename );
	new lines = 0;
	new bool:success;
	while( !IsEndOfFile( infile ) ) {
		// move lines++ to here if malfunctions happen
		decl String:line[1024];
		if( !ReadFileLine( infile, line, sizeof line ) ) continue;
		lines++;
		ReplaceString( line, sizeof line, "\r", "" );
		ReplaceString( line, sizeof line, "\n", "" );

		if( lines == replaceline ) {
			if( preserve_indent ) {
				StripText(line);
				WriteFileLine( outfile, "%s%s", line, text );
			} else {
				WriteFileLine( outfile, text );
			}
			success = true;
		} else {
			WriteFileLine( outfile, line );
		}
	}
	if( lines == replaceline-1 ) {
		WriteFileLine( outfile, text );
		success = true;
	}

	CloseHandle(infile);
	CloseHandle(outfile);
	if( !success ) {
		DeleteFile( newfile );
		PrintToServer( "[ST] cannot write to line %d; only %d lines in file.", replaceline, lines );
		return;
	}

	if( !DeleteFile( filename ) ) {
		DeleteFile( newfile );
		PrintToServer( "[ST] cannot write to file: %s", filename );
		return;
	}

	if( !RenameFile( filename, newfile ) ) {
		PrintToServer( "[ST] cannot write to file: %s", filename );
		return;
	}

	PrintToServer( "[ST] edit success!", filename );
}

//-------------------------------------------------------------------------------------------------
public Action:Command_edit( args ) {
	if( !ReadyForNewOperation() ) return Plugin_Handled;

	if( args < 3 ) {
		PrintToServer( "Usage: st_edit -i <filepath> <line> <text>" );
		PrintToServer( "  -i : do not preserve indentation" );
		return Plugin_Handled;
	}

	decl String:line[512];
	GetCmdArgString( line, sizeof line );
	StripQuotes(line);

	new index = 0;
	new bool:indent = true;
	decl String:arg[64];
	GetNextArg( line, index, arg, sizeof arg );
	if( StrEqual( arg, "-i" ) ) {
		indent = false;
	} else {
		index = 0;
	}

	decl String:filename[256];
	new linenumber;

	GetNextArg( line, index, arg, sizeof arg );

	if( !FormatLocalPath( filename, sizeof(filename), arg ) ) {
		PrintToServer( "[ST] invalid path" );
		return Plugin_Handled;
	}

	GetNextArg( line, index, arg, sizeof arg );
	linenumber = StringToInt( arg );

	if(linenumber <= 0 ) {
		PrintToServer( "[ST] invalid line number" );
		return Plugin_Handled;
	}

	if( index == -1 ) {
		PrintToServer( "[ST] missing text string" );
		return Plugin_Handled;
	}
	
	EditFile( filename, linenumber, line[index], indent );
	return Plugin_Handled;
}

//-------------------------------------------------------------------------------------------------
public Action:Command_mkdir( args ) {
	if( !ReadyForNewOperation() ) return Plugin_Handled;

	if( args < 1 ) {
		PrintToServer( "Usage: st_mkdir <path> (local only)" );
		return Plugin_Handled;
	}

	decl String:arg[256];
	GetCmdArg( 1, arg, sizeof(arg) );
	decl String:path[256];
	if( !FormatLocalPath( path, sizeof path, arg )  ) {
		PrintToServer( "[ST] error: invalid path" );
		return Plugin_Handled;
	}

	if( CreateDirectory( path, DPERMS ) ) {
		PrintToServer( "[ST] directory created!" );
	} else {
		PrintToServer( "[ST] error creating directory" );
	}
	return Plugin_Handled;
}

//-------------------------------------------------------------------------------------------------
public Action:Command_rename( args ) {
	if( !ReadyForNewOperation() ) return Plugin_Handled;

	if( args < 2 ) {
		PrintToServer( "Usage: st_rename <file> <newfile>" );
		return Plugin_Handled;
	}

	decl String:arg[256];
	GetCmdArg( 1, arg, sizeof(arg) );
	decl String:path1[256];
	if( !FormatLocalPath( path1, sizeof path1, arg )  ) {
		PrintToServer( "[ST] error: invalid file" );
		return Plugin_Handled;
	}
	 
	GetCmdArg( 2, arg, sizeof(arg) );
	decl String:path2[256];
	if( FindCharInString( arg, '/' ) == -1 ) {
		decl String:work[256];
		StripFileName( work, sizeof work, path1 );
		Format( path2, sizeof path2, "%s%s", work, arg );
		
	} else {
		
		if( !FormatLocalPath( path2, sizeof path2, arg )  ) {
			PrintToServer( "[ST] error: invalid destination" );
			return Plugin_Handled;
		}
	}

	if( !FileDirExists( path2 ) ) {
		PrintToServer( "[ST] error: invalid destination (directory doesnt exist)" );
		return Plugin_Handled;
	}

	PrintToServer( "[ST] attemping to rename: %s -> %s", path1, path2 );
	if( RenameFile( path2, path1 ) ) {
		PrintToServer( "[ST] file renamed successfully" );
	} else {
		PrintToServer( "[ST] error: couldn't rename file!" );
	}

	return Plugin_Handled;
}

//-------------------------------------------------------------------------------------------------
public Action:Command_dir( args ) {
	
	if( !ReadyForNewOperation() ) return Plugin_Handled;

	if( args < 1 ) {
		PrintToServer( "Usage: st_dir <path> (local only)" );
		return Plugin_Handled;
	}
	decl String:arg[256];
	GetCmdArg( 1, arg, sizeof(arg) );
	decl String:path[256];
	if( !FormatLocalPath( path, sizeof path, arg )  ) {
		PrintToServer( "[ST] error: invalid path" );
		return Plugin_Handled;
	}
	
	StripFilePath( op_pattern, sizeof op_pattern, path );
	StripFileName( path, sizeof path, path );

	new Handle:dir = OpenDirectory( path );
	if( !dir ) {
		PrintToServer( "[ST] error: directory doesn't exist" );
		return Plugin_Handled;
	}

	new bool:filter=false;
	filter = op_pattern[0] != 0;
	if( filter ) {
		PrintToServer( "[ST] Directory listing for \"%s\"; filtering by \"%s\"", path, op_pattern );
		LoadPatternRegex();
	} else {
		PrintToServer( "[ST] Directory listing for \"%s\"", path );
	}
	new Handle:files = CreateDataPack();
	new Handle:dirs = CreateDataPack();
	new filecount;
	new dircount;
	decl String:entry[256];
	new FileType:ft;
	while( ReadDirEntry( dir, entry, sizeof entry, ft ) ) {
		if( ft == FileType_Directory ) {

			if( filter && !FilePatternMatch( entry ) ) continue;
			WritePackString( dirs, entry );
			
			dircount++;
		} else if( ft == FileType_File ) {
			if( filter && !FilePatternMatch( entry ) ) continue;
			WritePackString( files, entry );
			filecount++;
		}
		 
	}

	CloseHandle(dir);
	ResetPack(dirs);
	ResetPack(files);
	
	for( new i = 0; i < dircount; i++ ) {
		ReadPackString( dirs, entry, sizeof entry );
		PrintToServer( "[dir] %s", entry );
	}
	CloseHandle( dirs );
	for( new i = 0; i < filecount; i++ ) {
		ReadPackString( files, entry, sizeof entry );
		PrintToServer( "[file] %s", entry );
	}
	CloseHandle( files );

	if( dircount == 0 && filecount == 0 ) {
		PrintToServer( "<no matches>" );
	} else {
		PrintToServer( "Found %d directories, %d files", dircount, filecount );
	}
	return Plugin_Handled;
}


//-------------------------------------------------------------------------------------------------
bool:LoadConfig() {
	sync_url[0] = 0;
	
	new Handle:kv = CreateKeyValues( "servertools" );
	decl String:configpath[256];
	BuildPath( Path_SM, configpath, sizeof(configpath), "configs/servertools.txt" );
	if( !FileExists( configpath ) ) {
		PrintToServer( "[ST] configuration file missing: configs/servertools.txt" );
		return false;
	}

	if( !FileToKeyValues( kv, configpath ) ) {
		PrintToServer( "[ST] error loading config file" );
		return false;
	}

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
	

	KvGetString( kv, "id", my_id, sizeof(my_id), "UNKNOWNID" );
	KvGetString( kv, "Groups", mygroups, sizeof(mygroups), "" );
	cfg_updater = bool:KvGetNum( kv, "updater", 1 );
	
	BuildURLRequestParam();
	
	StrCat(mygroups,sizeof mygroups, " all" );
	TrimString(mygroups);
	CloseHandle(kv);
	return true;
}

//-------------------------------------------------------------------------------------------------
BuildURLRequestParam() {
	decl String:groups[64][64];
	new count = ExplodeString( mygroups, " ", groups, sizeof groups, sizeof groups[] );
	FormatEx( url_request_params, sizeof url_request_params, "id=%s&groups=", my_id );
	
	for( new i = 0; i < count; i++ ) {
		TrimString( groups[i] );
		StrCat( url_request_params, sizeof url_request_params, groups[i] );
		if( i != count-1 )
			StrCat( url_request_params, sizeof url_request_params, "/" );
	}
}

//-------------------------------------------------------------------------------------------------
public Action:Command_reloadconfig( args ) {
	
	if( !ReadyForNewOperation() ) return Plugin_Handled;
	if( !LoadConfig() ) return Plugin_Handled;
	PrintToServer( "[ST] Reloaded Configuration." );
	 
	return Plugin_Handled;
}

//-------------------------------------------------------------------------------------------------
PrintOperationResult() {
	new Handle:file = OpenFile( op_logfile_path, "r" );
	while( !IsEndOfFile(file) ) {
		decl String:errline[256];
		if( !ReadFileLine( file, errline, sizeof(errline) ) ) continue;
		TrimString(errline);
		PrintToServer( "[ST] %s", errline );
	}
	PrintToServer( "%d errors, %d files transferred ", operation_errors, operation_files_transferred  );
}

//-------------------------------------------------------------------------------------------------
public Action:Command_status( args ) {
	if( op_state == STATE_READY ) {
		PrintToServer( "#000 STATUS READY" );
	} else if( op_state == STATE_BUSY ) {
		PrintToServer( "#001 STATUS BUSY" );
	} else if( op_state == STATE_COMPLETED ) {
		PrintToServer( "#002 STATUS COMPLETE" );
		PrintOperationResult();

		if( args > 0 ) {
			decl String:arg[64];
			GetCmdArg( 1, arg, sizeof(arg) );
			if( StrEqual( arg, "RESET" ) ) {
				Command_reset(args);
			}
		}
	}

	
	return Plugin_Handled;
}

//-------------------------------------------------------------------------------------------------
public Action:Command_reset( args ) {
	// todo
	if( op_state == STATE_COMPLETED ) {
		op_state = STATE_READY;
		if( FileExists( op_logfile_path ) ) {
			DeleteFile( op_logfile_path );
		}
		PrintToServer( "#002 RESET OK" );
	} else if( op_state == STATE_BUSY ) {
		PrintToServer( "#001 OPERATION IN PROGRESS" );
	} else if( op_state == STATE_READY ) {
		PrintToServer( "#000 SYSTEM IS READY" );
	}
	return Plugin_Handled;
} 

//-------------------------------------------------------------------------------------------------
StartOperation( const String:name[] ) {
	WakeServer();
	EraseStack();
	op_state = STATE_BUSY;
	//operation_files_failed = 0;
	operation_files_transferred = 0;
	operation_errors = 0;
	GetTempFile( op_logfile_path, sizeof( op_logfile_path ) );
	op_logfile = OpenFile( op_logfile_path, "w" );
	LogToFile( logfile, "-----------------------------------------------------------------------" );
	LogToFile( logfile, "starting operation: %s", name );
	//PrintToServer( "[ST] Starting operation: %s", name );
	strcopy( op_name, sizeof op_name, name );
}

//-------------------------------------------------------------------------------------------------
OperationError( const String:reason_fmt[], any:... ) {
	decl String:reason[256];
	VFormat( reason, sizeof(reason), reason_fmt, 2 );

	if( op_logfile != INVALID_HANDLE ) {
		WriteFileLine( op_logfile, "error: %s", reason );
	}
	
	operation_errors++;

	LogToFile( logfile, "error: %s", reason );
	//PrintToServer( "[ST] Error: %s", reason );
}

//-------------------------------------------------------------------------------------------------
OperationLog( const String:reason_fmt[], any:... ) {
	decl String:reason[256];
	VFormat( reason, sizeof(reason), reason_fmt, 2 );

	if( op_logfile != INVALID_HANDLE ) {
		WriteFileLine( op_logfile, "%s", reason );
	}
	LogToFile( logfile, "%s", reason );
	//PrintToServer( "[ST] %s", reason );
}

//-------------------------------------------------------------------------------------------------
PostUpload() {

	if( !op_delete_source ) return;

	// move operation - delete source files
	ResetPack( op_filepack );
	for( new i = 0; i < operation_files_transferred; i++ ) {
		decl String:file[256];
		ReadPackString( op_filepack, file, sizeof(file) );
		Format( file, sizeof( file ), "%s%s", path_source, file );
		if( !DeleteFile( file ) ) {	
			OperationError( "couldn't delete file: %s", file );
		} else {
			OperationLog( "deleted file: %s", file );
		}
	}

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
	
	while( GetNextArg( mygroups, index, arg, sizeof arg ) ) {
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
PreprocessFile( String:file[], maxlen ) {
	PrintToServer( "[ST] preprocessing file... %s", file );
	// processes a given file (tempfile!) and replaces file (the string passed in) with the new temp filename
	decl String:newfile[256];
	GetTempFile(newfile, sizeof newfile);
	
	new Handle:infile = OpenFile( file, "r" );
	if( !infile ) {
		OperationError( "Couldn't read file: %s", file );
		return;
	}
	new Handle:outfile = OpenFile( newfile, "w" );
	if( !outfile ) {
		CloseHandle(infile);
		OperationError( "Couldn't write file: %s", file );
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
					OperationError( "#endif without #if !!!", arg );
					continue;
				}
				PopStackCell( nest, output_disabled );
				// end if
			} else {
				OperationError( "Unknown Preprocessor Directive: %s", arg );
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
bool:TrieSet( Handle:trie, const String:entry[] ) {
	new dummy;
	return GetTrieValue( trie, entry, dummy );
}

//-------------------------------------------------------------------------------------------------
ProcessDownloadedFiles() {
	
	ResetPack( op_filepack );
	for( new i = 0; i < operation_files_transferred; i++ ) {
		decl String:tempfile[256];
		decl String:file[256];
		decl String:final[256];
		ReadPackString( op_filepack, tempfile, sizeof(tempfile) );
		ReadPackString( op_filepack, file, sizeof(file) );
		decl String:ext[32];
		GetFileExt( ext, sizeof ext, file );
		
		if( TrieSet( pp_trie, ext ) ) {
			
			PreprocessFile( tempfile, sizeof(tempfile) );
		}
		Format( final, sizeof(final), "%s%s", path_dest, file );
		 
		if( !PrimeFileTarget( final ) ) {
			 
			OperationError( "Couldn't write to file: %s", file );
			DeleteFile( tempfile );
		} else {
			
			 
			if( !RenameFile( final, tempfile ) ) {
				OperationError( "Couldn't write to file: %s", file );
			}
		}
	}

	CloseHandle( op_filepack );
	op_filepack = INVALID_HANDLE;
}

//-------------------------------------------------------------------------------------------------
CompleteOperation( ) {
	
	CloseHandle( op_stack );
	op_stack = INVALID_HANDLE;
	 
	
	CloseHandle( op_logfile );
	op_logfile = INVALID_HANDLE;
	LogToFile( logfile, "operation ended: %s", op_name );
	PrintToServer( "[ST] operation completed" );
	op_state = STATE_COMPLETED;
	
	if( StrEqual( op_name, "Server Sync" ) ) {
		if( initial_sync ) {
			initial_sync = false;
			op_state = STATE_READY;
		}
		Sync_Cleanup();
	}
	
	SleepServer();
}

//-------------------------------------------------------------------------------------------------
FileDomain:GetFileDomain( const String:file[] ) {
	new firstslash = FindCharInString( file, '/' );
	if( firstslash <= 0 ) return DOMAIN_ERROR;
	if( (strncmp( file, "ftp/", 4 ) == 0) ) return DOMAIN_FTP;
	if( (strncmp( file, "http/", 5 ) == 0) ) return DOMAIN_HTTP;
	if( (strncmp( file, "sm/", 3 ) == 0) ) return DOMAIN_LOCAL;
	if( (strncmp( file, "game/", 5 ) == 0) ) return DOMAIN_LOCAL;
	if( (strncmp( file, "cfg/", 4 ) == 0) ) return DOMAIN_LOCAL;
	if( (strncmp( file, "pl/", 3 ) == 0) ) return DOMAIN_LOCAL;
	if( (strncmp( file, "tr/", 3 ) == 0) ) return DOMAIN_LOCAL;
	if( (strncmp( file, "sc/", 3 ) == 0) ) return DOMAIN_LOCAL;
	if( (strncmp( file, "web/", 4 ) == 0) ) return DOMAIN_WEB;
	return DOMAIN_ERROR;
}

//-------------------------------------------------------------------------------------------------
bool:FormatFTPUrl( String:output[], maxlen, const String:file[] ) {
	if( strncmp( file, "ftp/", 4 ) != 0 ) return false;
	Format( output, maxlen, "%s%s", ftp_url, file[4] );
	return true;
}

//-------------------------------------------------------------------------------------------------
bool:FormatHTTPUrl( String:output[], maxlen, const String:file[] ) {
	if( strncmp( file, "http/", 5 ) != 0 ) return false;
	Format( output, maxlen, "%s%s", http_url, file[5] );
	return true;
}

//-------------------------------------------------------------------------------------------------
bool:FormatWebUrl( String:output[], maxlen, const String:file[] ) {
	if( strncmp( file, "web/", 4 ) != 0 ) return false;
	Format( output, maxlen, "%s%s", "http://", file[4] );
	return true;
}

//-------------------------------------------------------------------------------------------------
bool:FormatHTTPListingUrl( String:output[], maxlen, const String:file[] ) {
	if( strncmp( file, "http/", 5 ) != 0 ) return false;
	Format( output, maxlen, "%s%s?path=/%s", http_url, http_listing_file, file[5] );
	return true;
}

//-------------------------------------------------------------------------------------------------
bool:PathIsDirectory( const String:path[] ) {
	new sl = strlen(path);
	if( sl == 0 ) return true;
	return path[sl-1] == '/';
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

//-------------------------------------------------------------------------------------------------
bool:FileIsNormalPlugin( const String:path[] ) {
	// normal plugin is a .smx file located in sm/plugins and not
	// sm/plugins/disabled or sm/plugins/optional
	decl String:plugins[128];
	BuildPath( Path_SM, plugins, sizeof plugins, "plugins/" );
	ReplaceString( plugins, sizeof plugins, "\\", "/" );
	
	new plen = strlen(plugins);
	if( strncmp( plugins, path, plen, false ) == 0 ) {
		
		// check folder that it's in
		if( strncmp( path[plen], "disabled/", 9, false ) == 0 ) return false;
		if( strncmp( path[plen], "optional/", 9, false ) == 0 ) return false;
		
		new ext = FindCharInString( path, '.', true );
		if( ext == -1 ) return false; // no extension
		if( StrEqual( path[ext], ".smx", false ) ) return true;
	}
	return false;
}

//-------------------------------------------------------------------------------------------------
bool:TryCopyDisabledPlugin( const String:path[] ) {
	// only pass a valid plugin path
	
	decl String:plugins[128];
	BuildPath( Path_SM, plugins, sizeof plugins, "plugins/" );
	new filestart = strlen(plugins);
	decl String:dpath[128];
	FormatEx( dpath, sizeof dpath, "%sdisabled/%s", plugins, path[filestart] );
	
	if( FileExists( path ) ) return true;
	
	PrimeFileTarget( path );
	if( FileExists( dpath ) ) {
		RenameFile( path, dpath );
		return true;
	}
	return false;
}

//-------------------------------------------------------------------------------------------------
DisablePlugin( const String:path[] ) {
	decl String:plugins[128];
	BuildPath( Path_SM, plugins, sizeof plugins, "plugins/" );
	new filestart = strlen(plugins);
	decl String:dpath[128];
	FormatEx( dpath, sizeof dpath, "%sdisabled/%s", plugins, path[filestart] );
	if( !FileExists( path ) ) return;
	PrimeFileTarget( dpath );
	RenameFile( dpath, path );
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
	
	// nobody likes backslashes
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
bool:IsMultiTransfer( const String:path[] ) {
	decl String:file[256];
	StripFilePath( file, sizeof(file), path );
	return( FindCharInString( file, '*' ) >= 0 );
}

//-------------------------------------------------------------------------------------------------
bool:FileDirExists( const String:dest[] ) {
	decl String:work[512];
	strcopy( work, sizeof(work), dest );
	new index = FindCharInString( work, '/', true );
	if( index == -1 ) return true; // root path
	work[index] = 0; 
	return DirExists( work );
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
		if( StrEqual(dirname, "..") ) continue;
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
public OnGetDirListing( Handle:hndl, CURLcode:code, any:data ) {
	CloseHandle(hndl);
	new Handle:file;
	decl String:tempfile[256];
	decl String:dir[256];
	ResetPack(data);
	file = Handle:ReadPackCell(data);
	ReadPackString( data, tempfile, sizeof(tempfile) );
	ReadPackString( data, dir, sizeof(dir) );
	CloseHandle(data);
	CloseHandle(file);

	if( code == CURLE_OK ) {
		// no error
	} else {
		DeleteFile( tempfile );
		OperationError( "couldnt get directory listing from %s%s", path_source, dir );
		ContinueDownload();
		return;
	}
	file = OpenFile( tempfile, "r" );
	
	// push stack in this order: tempfile -> directory -> file
	PushStackString( op_stack, tempfile );
	PushStackString( op_stack, dir );
	PushStackCell( op_stack, file );
	
	ContinueDownload();
}

//-------------------------------------------------------------------------------------------------
AddFileDownloaded( const String:tempfile[], const String:filepath[] ) {
	operation_files_transferred++;
	WritePackString( op_filepack, tempfile );
	WritePackString( op_filepack, filepath );
	OperationLog( "File retrieved: %s%s", path_source, filepath );
}

//-------------------------------------------------------------------------------------------------
AddFileCopied( const String:file[] ) {
	operation_files_transferred++;
	WritePackString( op_filepack, file );
	OperationLog( "File copied: %s%s", path_source, file );
}

//-------------------------------------------------------------------------------------------------
AddFileUploaded( const String:filepath[] ) {
	operation_files_transferred++;
	WritePackString( op_filepack, filepath );
	OperationLog( "File sent: %s%s", path_source, filepath );
}

//-------------------------------------------------------------------------------------------------
public OnFileDownloadComplete( Handle:hndl, CURLcode:code, any:data ) {
	CloseHandle(hndl);
	ResetPack(data);
	new Handle:file = Handle:ReadPackCell(data);
	decl String:filepath[256];
	ReadPackString( data, filepath, sizeof(filepath) );
	decl String:tempfile[256];
	ReadPackString( data, tempfile, sizeof(tempfile) );
	CloseHandle(file);

	if( code != CURLE_OK ) {
		OperationError( "couldn't download file (code %d): %s%s", code, path_source, filepath );
	 
	} else {
		AddFileDownloaded( tempfile, filepath );
	}
	ContinueDownload();
}

//-------------------------------------------------------------------------------------------------
bool:DownloadFile( const String:file[] ) {
	
	// file = full file path from working directory
	decl String:url[512];
	Format( url, sizeof(url), "%s%s", path_source, file );
	 
	decl String:tempfile[256];
	GetTempFile( tempfile, sizeof(tempfile) );

	// create curl instance
	new Handle:curl = curl_easy_init();
	curl_easy_setopt_int_array( curl, CURLDefaultOpt, sizeof( CURLDefaultOpt ) );

	if( dl_source_domain == DOMAIN_FTP ) {
		curl_easy_setopt_string( curl, CURLOPT_USERPWD, ftp_auth );
	}


	new Handle:outfile = curl_OpenFile( tempfile, "wb" );
	curl_easy_setopt_string( curl, CURLOPT_URL, url );
	curl_easy_setopt_handle( curl, CURLOPT_WRITEDATA, outfile );
	  
	new Handle:pack = CreateDataPack();
	WritePackCell( pack, _:outfile );
	WritePackString( pack, file );
	WritePackString( pack, tempfile );
	
	curl_easy_perform_thread( curl, OnFileDownloadComplete, pack );
	return true;

}

//-------------------------------------------------------------------------------------------------
bool:DownloadMulti( const String:dir[] ) {
	decl String:directory_url[512];
	
	if( dl_source_domain == DOMAIN_FTP ) {
		Format( directory_url, sizeof(directory_url), "%s%s", path_source, dir ); 
	} else if( dl_source_domain == DOMAIN_HTTP ) {
		Format( directory_url, sizeof(directory_url), "%s%s", path_source_httplisting, dir ); 
	} else {
		SetFailState( "fatal error." );
	}


	// create curl instance
	new Handle:curl = curl_easy_init();
	curl_easy_setopt_int_array( curl, CURLDefaultOpt, sizeof( CURLDefaultOpt ) );

	if( dl_source_domain == DOMAIN_FTP ) {
		curl_easy_setopt_string( curl, CURLOPT_USERPWD, ftp_auth );
	}


	// request ftp listing
	decl String:tempfile[256];
	GetTempFile( tempfile, sizeof(tempfile) );
	new Handle:outfile = curl_OpenFile( tempfile, "wb" );
	 
	curl_easy_setopt_string( curl, CURLOPT_URL, directory_url );
	curl_easy_setopt_handle( curl, CURLOPT_WRITEDATA, outfile );
	 
	new Handle:pack = CreateDataPack();
	WritePackCell( pack, _:outfile );
	WritePackString( pack, tempfile );
	WritePackString( pack, dir );

	curl_easy_perform_thread( curl, OnGetDirListing, pack );
	return true;
}

//-------------------------------------------------------------------------------------------------
public OnFileUploadComplete( Handle:hndl, CURLcode:code, any:data ) {
	CloseHandle(hndl);
	ResetPack(data);
	new Handle:file = Handle:ReadPackCell(data);
	CloseHandle(file);
	decl String:path[256];
	ReadPackString( data, path, sizeof(path) );
	CloseHandle(data);

	if( code != CURLE_OK ) {
		OperationError( "couldn't upload file (code %d): %s%s", code, path_source, path );
	} else {
		AddFileUploaded( path );
	}
	ContinueUpload();
}

//-------------------------------------------------------------------------------------------------
bool:TransferFileToFTP( const String:file[] ) {
	decl String:url[512];
	Format( url, sizeof url, "%s%s", path_dest, file );

	decl String:src[512];
	Format( src, sizeof src, "%s%s", path_source, file );

	new Handle:curl = curl_easy_init();
	curl_easy_setopt_int_array( curl, CURLDefaultOpt, sizeof( CURLDefaultOpt ) );
	curl_easy_setopt_string( curl, CURLOPT_USERPWD, ftp_auth );
	curl_easy_setopt_string( curl, CURLOPT_URL, url );
	
	curl_easy_setopt_int( curl, CURLOPT_UPLOAD, 1 );
	curl_easy_setopt_int( curl, CURLOPT_FTP_CREATE_MISSING_DIRS, CURLFTP_CREATE_DIR );
	new Handle:infile = curl_OpenFile( src, "rb" );
	if( infile == INVALID_HANDLE ) {
		OperationError( "couldn't open file." );
		CloseHandle(curl);
		return false;
	}
	curl_easy_setopt_handle( curl, CURLOPT_READDATA, infile );

	new Handle:pack = CreateDataPack();
	WritePackCell( pack, _:infile );
	WritePackString( pack, file );
	
	curl_easy_perform_thread( curl, OnFileUploadComplete, pack );
	return true;
}

//-------------------------------------------------------------------------------------------------
bool:TransferMultiToFTP( const String:dir[] ) {
	decl String:directory_path[512];
	Format( directory_path, sizeof directory_path, "%s%s", path_source, dir );

	new Handle:opendir = OpenDirectory(directory_path);
	
	if( opendir == INVALID_HANDLE ) {
		OperationError( "couldn't browse directory." );
		return false;
	}
	
	PushStackString( op_stack, dir );
	PushStackCell( op_stack, _:opendir );

	ContinueUpload();
	return true;
}

//-------------------------------------------------------------------------------------------------
bool:ParseListingFilename( String:filename[], maxlen, const String:filestring[], &bool:isdirectory ) {
	if( strlen(filestring) == 0 ) {
		return false; // empty line!
	}

	if( dl_source_domain == DOMAIN_FTP ) {
		
		// ftp directory listings are NOT a standard and this will most likely break on a lot of ftp servers :)

		// assuming this format:
		// -rw-r--r--    1 1183     400             3 Jun 06 22:08 test2.txt
		decl String:mod[64];
		decl String:arg[64];
		new index = BreakString( filestring, mod, sizeof(mod) ); // mod
		index += BreakString( filestring[index], arg, sizeof(arg) ); // "1"
		index += BreakString( filestring[index], arg, sizeof(arg) ); // "1183"
		index += BreakString( filestring[index], arg, sizeof(arg) ); // "400"
		index += BreakString( filestring[index], arg, sizeof(arg) ); // size
		index += BreakString( filestring[index], arg, sizeof(arg) ); // month
		index += BreakString( filestring[index], arg, sizeof(arg) ); // day
		index += BreakString( filestring[index], arg, sizeof(arg) ); // time

		strcopy( filename, maxlen, filestring[index] ); // filename
	
		if( mod[0] == 'd' ) {
			isdirectory = true;
		} else {
			isdirectory = false;
		}
		return true;
	} else {

		// assuming this format:
		// <filetype> <filename>
		decl String:arg[64];
		new index = BreakString( filestring, arg, sizeof(arg) );
		TrimString(arg);
		if( StrEqual(arg, "dir") ) {
			isdirectory = true;
		} else if( StrEqual( arg,"file" ) ) {
			isdirectory=false;
		} else {
			return false; // invalid file type
		}
		strcopy( filename, maxlen, filestring[index] );
		
		if( StrEqual( filename, "." ) ) return false; // catch these special directories
		if( StrEqual( filename, ".." ) ) return false;

		return true;
	}
}

bool:FilePatternMatch( const String:filename[] ) {
	
	return MatchRegex( op_pattern_regex, filename ) > 0;
}

ContinueUpload() {
	new bool:ending = false;
	while( !ending ) {
		if( IsStackEmpty( op_stack ) ) {
			ending = true;
			break;
		}

		new Handle:dir;
		decl String:dirpath[256];
		PopStackCell( op_stack, dir );
		PopStackString( op_stack, dirpath, sizeof dirpath );
		
		decl String:nextfile[256];
		new FileType:ftype;
		if( !ReadDirEntry( dir, nextfile, sizeof nextfile, ftype ) ) {
			// end of directory
			CloseHandle(dir);
			continue;
		}
		
		PushStackString( op_stack, dirpath );
		PushStackCell( op_stack, _:dir );
		
		if( StrEqual( nextfile, "." ) ) continue; // skip these dirs...
		if( StrEqual( nextfile, ".." ) ) continue;

		new bool:patternmatch = FilePatternMatch( nextfile );
		Format( nextfile, sizeof nextfile, "%s%s", dirpath, nextfile );

		if( ftype == FileType_Directory ) {
			if( op_directory_recursive ) {
				StrCat( nextfile, sizeof nextfile, "/" );
				if( TransferMultiToFTP( nextfile ) ) return;
				continue;
			}
			continue;
		} else if( ftype == FileType_Unknown  ) {
			continue;
		}

		if( patternmatch ) {
			if( TransferFileToFTP( nextfile ) ) return;
			continue;
		} else {
			continue;
		}
	}

	PostUpload();
	CompleteOperation();
}

//-------------------------------------------------------------------------------------------------
ContinueDownload() {

	new bool:ending = false;

	while( !ending ) {
		if( IsStackEmpty(op_stack) ) {
			ending = true;
			
			break;
		}

		new Handle:listing;
		decl String:dir[256];
		PopStackCell( op_stack, listing );
		PopStackString( op_stack, dir, sizeof dir );

		if( IsEndOfFile( listing )  ) {
			CloseHandle(listing);
			decl String:listing_file[256];
			PopStackString( op_stack, listing_file, sizeof(listing_file) );
			DeleteFile( listing_file );
			continue;
		}

		PushStackString( op_stack, dir );
		PushStackCell( op_stack, listing );

		decl String:filestring[256];
		new bool:readresult = ReadFileLine( listing, filestring, sizeof filestring );

		if( readresult == false ) {
			continue;
		}
		
		TrimString( filestring );
		if( strlen(filestring) == 0 ) {
			continue;
		}
		decl String:filename[128];
		new bool:isdirectory; 
		if( !ParseListingFilename( filename, sizeof(filename), filestring, isdirectory ) ) {
			continue;
		}
		new bool:patternmatch = FilePatternMatch( filename );
		Format( filename, sizeof(filename), "%s%s", dir, filename );

		if( isdirectory ) {
			if( op_directory_recursive ) {
			 
				StrCat( filename, sizeof(filename), "/" );
				DownloadMulti( filename );
				return;
			}
			continue;
		}
		if( patternmatch ) {
			DownloadFile( filename );
			return;
		} else {
			continue;
		}
	}
	
	ProcessDownloadedFiles();
	CompleteOperation();
}

//-------------------------------------------------------------------------------------------------
EraseStack() {
	if( op_stack != INVALID_HANDLE ) {
		CloseHandle(op_stack);
	}
	op_stack = CreateStack( 128/4 ); /// 128 chars
}

//-------------------------------------------------------------------------------------------------
EraseFilePack() {
	if( op_filepack != INVALID_HANDLE ) {
		CloseHandle( op_filepack );
	}
	op_filepack = CreateDataPack();
	ResetPack( op_filepack );
}

//-------------------------------------------------------------------------------------------------
LoadPatternRegex() {
	decl String:work[256];
	strcopy( work, sizeof work, op_pattern );
	ReplaceString( work, sizeof work, ".", "\\." );
	ReplaceString( work, sizeof work, "[", "\\[" );
	ReplaceString( work, sizeof work, "*", ".*" );
	ReplaceString( work, sizeof work, "?", ".+" );
	Format( work, sizeof(work), "^%s$", work );
	if( op_pattern_regex != INVALID_HANDLE ) CloseHandle( op_pattern_regex );
	op_pattern_regex = CompileRegex( work, 0 );
}

//-------------------------------------------------------------------------------------------------
StartFTPDownload( const String:source[], const String:dest[] ) {
	decl String:url[512];
	decl String:path[512];
	if( !FormatFTPUrl( url, sizeof(url), source ) ) {
		PrintToServer( "error: invalid source" );
		return;
	}
	if( !FormatLocalPath( path, sizeof(path), dest ) ) {
		PrintToServer( "error: invalid destination (bad path)" );
		return;
	}
	AddPathSlash(path,sizeof path);
	if( !FileDirExists( path ) ) {
		PrintToServer( "error: invalid destination (directory doesnt exist)" );
		return;
	}
	
	// setup working directories
	StripFileName( path_source, sizeof(path_source), url );
	StripFileName( path_dest, sizeof(path_dest), path );
	StripFilePath( op_pattern, sizeof(op_pattern), url );
	LoadPatternRegex();
	 
	if( url[strlen(url)-1] == '/' ) {
		// invalid source
		PrintToServer( "[ST] error: Invalid source; for directory transfers use -r path/*" );
		return;
	}
	new bool:multi = IsMultiTransfer(source);

	StartOperation( multi ? "FTP Multiple File Download" : "FTP Single File Download" );
	dl_source_domain = DOMAIN_FTP;
	EraseFilePack(); 

	if( multi ) {
		// get directory
		DownloadMulti( "" );
	} else {
		// get single file
		DownloadFile( op_pattern );
	}
}

//-------------------------------------------------------------------------------------------------
StartFTPUpload( const String:source[], const String:dest[] ) {
	decl String:path[512];
	decl String:url[512];
	if( !FormatLocalPath( path, sizeof path, source ) ) {
		PrintToServer( "[ST] error: invalid source (bad path)" );
		return;
	}
	if( !FormatFTPUrl( url, sizeof url, dest ) ) {
		PrintToServer( "[ST] error: invalid destination" );
		return;
	}
	AddPathSlash( url, sizeof url );

	StripFileName( path_source, sizeof path_source, path );
	StripFileName( path_dest, sizeof path_dest, url );
	StripFilePath( op_pattern, sizeof(op_pattern), path );
	LoadPatternRegex();
	 
	if( path[strlen(path)-1] == '/' ) {
		PrintToServer( "[ST] error: Invalid source; for directory transfers use -r path/*" );
		return;
	}
	new bool:multi = IsMultiTransfer(source);
	StartOperation( multi ? "FTP Multiple File Upload" : "FTP Single File Upload" );
	EraseFilePack(); 

	if( multi ) {
		// get directory
		if( !TransferMultiToFTP( "" ) ) ContinueUpload();
	} else {
		// get single file
		if( !TransferFileToFTP( op_pattern ) ) ContinueUpload();
	}
}
/*
public OnGetHttpListing( Handle:hndl, CURLcode:code, any:data ) {
	CloseHandle(hndl);
	new Handle:file;
	decl String:tempfile[256];
	decl String:dir[256];
	ResetPack(data);
	file = Handle:ReadPackCell(data);
	ReadPackString( data, tempfile, sizeof(tempfile) );
	ReadPackString( data, dir, sizeof(dir) );
	CloseHandle(data);
	CloseHandle(file);

	if( code == CURLE_OK ) {
		// no error
	} else {
		DeleteFile( tempfile );
		OperationError( "couldnt get directory listing from %s%s", path_source, dir );
		ContinueDownload();
		return;
	}

	file = OpenFile( tempfile, "rb" );
	// push stack in this order: tempfile -> directory -> file
	PushStackString( op_stack, tempfile );
	PushStackString( op_stack, dir );
	PushStackCell( op_stack, file );

	ContinueDownload();

//-------------------------------------------------------------------------------------------------
bool:TransferFileFromHTTP( const String:file[] ) {
	decl String:url[512];
	Format( url, sizeof(url), "%s%s", path_source, file );

	decl String:tempfile[256];
	GetTempFile( tempfile, sizeof(tempfile) );

	new Handle:curl = curl_easy_init();
	curl_easy_setopt_int_array( curl, CURLDefaultOpt, sizeof( CURLDefaultOpt ) );
	new Handle:outfile = curl_OpenFile( tempfile, "wb" );
	curl_easy_setopt_string( curl, CURLOPT_URL, url );
	curl_easy_setopt_handle( curl, CURLOPT_WRITEDATA, outfile );
	  
	new Handle:pack = CreateDataPack();
	WritePackCell( pack, _:outfile );
	WritePackString( pack, file );
	WritePackString( pack, tempfile );
	
	curl_easy_perform_thread( curl, OnHttpDownloadComplete, pack );
	return true;
}

//-------------------------------------------------------------------------------------------------
bool:TransferMultiFromHTTP( const String:dir[] ) {
	decl String:directory_url[512];
	Format( directory_url, sizeof( directory_url ), "%s%s", path_source_httplisting, dir );

	new Handle:curl = curl_easy_init();
	curl_easy_setopt_int_array( curl, CURLDefaultOpt, sizeof( CURLDefaultOpt ) );
	 
	// request HTTP listing
	decl String:tempfile[256];
	GetTempFile( tempfile, sizeof(tempfile) );
	new Handle:outfile = curl_OpenFile( tempfile, "wb" );
	curl_easy_setopt_string( curl, CURLOPT_URL, directory_url );
	curl_easy_setopt_handle( curl, CURLOPT_WRITEDATA, outfile );
	new Handle:pack = CreateDataPack();
	WritePackCell( pack, _:outfile );
	WritePackString( pack, tempfile );
	WritePackString( pack, dir );

	curl_easy_perform_thread( curl, OnGetHttpListing, pack );
	return true;
}
*/

//-------------------------------------------------------------------------------------------------
StartHTTPDownload( const String:source[],const String:dest[] ) {
	decl String:url[512];
	decl String:listingurl[512];
	decl String:path[512];
	if( !FormatHTTPUrl( url, sizeof(url), source ) ) {
		PrintToServer( "error: invalid source" );
		return;
	}
	if( !FormatHTTPListingUrl( listingurl, sizeof(listingurl), source ) ) {
		PrintToServer( "error: invalid source" );
		return;
	}
	if( !FormatLocalPath( path, sizeof(path), dest ) ) {
		PrintToServer( "error: invalid destination (bad path)" );
		return;
	}
	AddPathSlash(path,sizeof path);
	if( !FileDirExists( path ) ) {
		PrintToServer( "error: invalid destination (directory doesnt exist)" );
		return;
	}
	
	// setup working directories
	StripFileName( path_source, sizeof(path_source), url );
	StripFileName( path_source_httplisting, sizeof(path_source_httplisting), listingurl );
	StripFileName( path_dest, sizeof(path_dest), path );
	StripFilePath( op_pattern, sizeof(op_pattern), url );
	LoadPatternRegex();
	 
	if( url[strlen(url)-1] == '/' ) {
		// invalid source
		PrintToServer( "[ST] error: Invalid source; for directory transfers use -r path/*" );
		return;
	}
	new bool:multi = IsMultiTransfer(source);

	StartOperation( multi ? "HTTP Multiple File Download" : "HTTP Single File Download" );
	dl_source_domain = DOMAIN_HTTP;
	EraseFilePack(); 
 
	if( multi ) 
		DownloadMulti( "" );
	else
		DownloadFile( op_pattern );
}

//-------------------------------------------------------------------------------------------------
StartWebDownload( const String:source[], const String:dest[] ) {
	decl String:url[512]; 
	decl String:path[512];
	if( !FormatWebUrl( url, sizeof(url), source  ) ) {
		PrintToServer( "error: invalid source" );
		return;
	}
	if( !FormatLocalPath( path, sizeof(path), dest ) ) {
		PrintToServer( "error: invalid destination (bad path)" );
		return;
	}
	AddPathSlash(path,sizeof path);
	if( !FileDirExists( path ) ) {
		PrintToServer( "error: invalid destination (directory doesnt exist)" );
		return;
	}
	
	// setup working directories
	StripFileName( path_source, sizeof(path_source), url );
	StripFileName( path_dest, sizeof(path_dest), path );
	StripFilePath( op_pattern, sizeof(op_pattern), url );
	LoadPatternRegex();
	 
	
	if( url[strlen(url)-1] == '/' ) {
		// invalid source
		PrintToServer( "[ST] error: Invalid source" );
		return;
	}
	new bool:multi = IsMultiTransfer(source);

	if( multi ) {
		PrintToServer( "[ST] error: Cannot do multi transfers from web/" );
		return;
	}

	StartOperation( "Web File Download" );
	dl_source_domain = DOMAIN_WEB;
	EraseFilePack(); 
 
	DownloadFile( op_pattern );
}

//-------------------------------------------------------------------------------------------------
CopyFileSingle( const String:source[], const String:rename[] = "" ) {

	decl String:fullsource[256], String:fulldest[256];
	Format( fullsource, sizeof fullsource, "%s%s", path_source, source );
	if( rename[0] == 0 ) {
		Format(fulldest, sizeof fulldest, "%s%s", path_dest, source );
	} else {
		Format( fulldest, sizeof fulldest, "%s%s", path_dest, rename );
	}

	new Handle:infile = OpenFile( fullsource, "rb" );
	if( infile == INVALID_HANDLE ) {
		PrintToServer( "[ST] couldn't open %s for reading", fullsource );
		return;
	}
	if( !PrimeFileTarget( fulldest ) ) {
		CloseHandle(infile);
		PrintToServer( "[ST] couldn't open %s for writing", fulldest );
		return;
	}
	new Handle:outfile = OpenFile( fulldest, "wb" );
	if( outfile == INVALID_HANDLE ) {
		CloseHandle(infile);
		PrintToServer( "[ST] couldn't open %s for writing", fulldest );
		return;
	}

	new pos = 0;
	new byte;
	while( !IsEndOfFile( infile ) ) {
		if( ReadFileCell( infile, byte, 1 ) == -1 ) {
			if( pos != 0 ) {
				PrintToServer( "[ST] a read error occurred" );
			}
			break;
		}
		if( !WriteFileCell( outfile, byte, 1 ) ) {
			PrintToServer( "[ST] a write error occurred" );
			break;
		}
		pos++;
	}

	AddFileCopied( source );

	CloseHandle( infile );
	CloseHandle( outfile );
}

//-------------------------------------------------------------------------------------------------
CopyFileLoop( const String:dirpath[] ) {
	decl String:dirpath2[256];
	Format(dirpath2, sizeof dirpath2, "%s%s", path_source, dirpath );
	
	new Handle:dir = OpenDirectory( dirpath2 );
	decl String:file[256];
	new FileType:ft;
	while( ReadDirEntry( dir, file, sizeof file, ft ) ) {
		if( StrEqual( file, "." ) ) continue; // skip these dirs...
		if( StrEqual( file, ".." ) ) continue;
		decl String:filepath[256];
		
		Format( filepath, sizeof filepath, "%s%s", dirpath, file );

		if( ft == FileType_Directory ) {
			if( op_directory_recursive ) {
				AddPathSlash( filepath, sizeof filepath );
				CopyFileLoop( filepath );
			}
		} else if( ft == FileType_File ) {
			
			CopyFileSingle( filepath );
		}
	}
	CloseHandle(dir);
}

//-------------------------------------------------------------------------------------------------
DoLocalCopy( const String:source[], const String:dest[] ) {
	decl String:srcpath[512];
	decl String:destpath[512];
	if( !FormatLocalPath( srcpath, sizeof srcpath, source ) ) {
		PrintToServer( "[ST] error: invalid source (bad path)" );
		return;
	}
	if( !FormatLocalPath( destpath, sizeof destpath, dest ) ) {
		PrintToServer( "[ST] error: invalid dest (bad path)" );
		return;
	}
	
	if( !FileDirExists( srcpath ) ) {
		PrintToServer( "[ST] error: invalid source (directory doesnt exist)" );
		return;
	}
	if( !FileDirExists( destpath ) ) {
		PrintToServer( "[ST] error: invalid dest (directory doesnt exist)" );
		return;
	}

	new bool:multi = IsMultiTransfer(source);
	if( multi ){
		AddPathSlash( destpath, sizeof destpath );
	}
	

	StripFileName( path_source, sizeof path_source, srcpath );
	StripFileName( path_dest, sizeof path_dest, destpath );
	StripFilePath( op_pattern, sizeof(op_pattern), srcpath );
	LoadPatternRegex();
	 
	operation_files_transferred = 0;
	EraseFilePack(); 

	if( srcpath[strlen(srcpath)-1] == '/' ) {
		PrintToServer( "[ST] error: Invalid source; for directory transfers use -r path/*" );
		return;
	}

	if( multi ) {
		PrintToServer( "[ST] copying files..." );
		CopyFileLoop( "" );
		PostUpload();
	} else {
		
		if( PathIsDirectory(destpath) ) {
			CopyFileSingle( op_pattern );
			PostUpload();
		} else {
			decl String:filedest[256];
			StripFilePath( filedest, sizeof filedest, destpath );
			 
			CopyFileSingle( op_pattern, filedest );
			PostUpload();
		
		}
	}
	PrintToServer( "[ST] %d files copied", operation_files_transferred );
}

//-------------------------------------------------------------------------------------------------
CopyFiles( const String:source[], const String:dest[], bool:directory_recursive ) {
	new FileDomain:sourcedomain, FileDomain:destdomain;
	
	op_directory_recursive = directory_recursive; // set op option
	sourcedomain = GetFileDomain( source );
	destdomain = GetFileDomain( dest );

	
	if( destdomain == DOMAIN_ERROR ) {
		PrintToServer( "[ST] invalid destination path" );
		return;
	}

	if( sourcedomain == DOMAIN_FTP ) {
		if( destdomain == DOMAIN_FTP ) {
			
			PrintToServer( "[ST] FTP->FTP transfers are not supported." );
			return;
		} else if( destdomain == DOMAIN_LOCAL ) {
			
			StartFTPDownload( source, dest );
			return;
		} else if( destdomain == DOMAIN_HTTP ) {
			PrintToServer( "[ST] http mode is read only." );
			return;
		}
	} else if( sourcedomain == DOMAIN_ERROR ) {
		PrintToServer( "[ST] bad source path" );
		return;
	} else if( sourcedomain == DOMAIN_LOCAL ) {
		if( destdomain == DOMAIN_FTP ) {
			StartFTPUpload( source, dest );
		} else if( destdomain == DOMAIN_HTTP ) {
			PrintToServer( "[ST] http mode is read only" );
			return;
		} else if( destdomain == DOMAIN_LOCAL ) {
			DoLocalCopy( source, dest );
		}
	} else if( sourcedomain == DOMAIN_HTTP ) {
		if( destdomain == DOMAIN_HTTP ) {
			PrintToServer( "[ST] HTTP->HTTP is not supported." );
			return;
		} else if( destdomain == DOMAIN_FTP ) {
			PrintToServer( "[ST] HTTP->FTP is not supported. ");
			return;
		} else if( destdomain == DOMAIN_LOCAL ) {
			StartHTTPDownload( source, dest );
			return;
		}
		
	} else if( sourcedomain == DOMAIN_WEB ) {
		if( destdomain != DOMAIN_LOCAL ) {
			PrintToServer( "[ST] invalid destination" );
			return;
		}

		StartWebDownload( source, dest );
	}
}

//-------------------------------------------------------------------------------------------------
public Action:Command_test( args ) {

	PrintToServer( "[ST] testing testing 1...2...3" );
	/*
	new Handle:kv = CreateKeyValues("Filehashes" );
	FileToKeyValues( kv, "addons/sourcemod/data/hashes.txt" );
	new result = KvJumpToKey( kv, "Addons" );

	PrintToServer( "%d - " ,result );
	CloseHandle(kv);*/
	
	
	return Plugin_Handled;
}
 

//-------------------------------------------------------------------------------------------------
public Action:Command_sync( args ) {
	if( !ReadyForNewOperation() ) return Plugin_Handled;	
	initial_sync = false;
	PerformSync();
	return Plugin_Handled;
}

//-------------------------------------------------------------------------------------------------

// SYNC OPERATION:
//
//  request manifest from remote server (RS)
//  parse manifest and create listing of synchronized files, also track plugins
//  ask RS for hashes of each file that is targetted, and create a list of out-of-date files
//  get updated files from RS and overwrite old files
//  move any plugins that were not on the manifest to /disabled/
//

GetLastSync() {
	decl String:path[128];
	BuildPath( Path_SM, path ,sizeof path, "data/servertools_sync" );
	if( !FileExists( path ) ) return 0;
	return GetFileTime( path, FileTime_LastChange );
}

//-------------------------------------------------------------------------------------------------
SetLastSync() {
	decl String:path[128];
	BuildPath( Path_SM, path ,sizeof path, "data/servertools_sync" );
	new Handle:h = OpenFile( path, "wb" );
	CloseHandle(h);
}

//-------------------------------------------------------------------------------------------------
PerformSync() {
	if( op_state != STATE_READY ) return; // ???
	StartOperation( "Server Sync" );
	
	// retrieve manifest
	decl String:manifest_url[512];
	FormatEx( manifest_url, sizeof manifest_url, "%s%s?%s", sync_url, sync_manifest, url_request_params );
	new Handle:curl = curl_easy_init();
	curl_easy_setopt_int_array( curl, CURLDefaultOpt, sizeof( CURLDefaultOpt ) );
	 
	// request manifest
	decl String:tempfile[256];
	GetTempFile( tempfile, sizeof(tempfile) );
	new Handle:outfile = curl_OpenFile( tempfile, "wb" );
	curl_easy_setopt_string( curl, CURLOPT_URL, manifest_url );
	curl_easy_setopt_handle( curl, CURLOPT_WRITEDATA, outfile );
	new Handle:pack = CreateDataPack();
	WritePackCell( pack, _:outfile );
	WritePackString( pack, tempfile );
	curl_easy_perform_thread( curl, OnGetSyncManifest, pack );
}

//-------------------------------------------------------------------------------------------------
Handle:LoadFileHashes() {
	decl String:path[128];
	BuildPath( Path_SM, path, sizeof path, "data/servertools-hashes.txt" );
	new Handle:kv = CreateKeyValues( "servertools-filehashes" );
	if( FileExists( path ) ) {
		if( !FileToKeyValues( kv, path ) ) {
			// corrupted?
			CloseHandle(kv);
			DeleteFile( path );
			kv = CreateKeyValues( "servertools-filehashes" );
		}
	}
	return kv;
}

//-------------------------------------------------------------------------------------------------
SaveFileHashes( Handle:kv ) {
	KvRewind( kv );
	decl String:path[128];
	BuildPath( Path_SM, path, sizeof path, "data/servertools-hashes.txt" );
	KeyValuesToFile( kv, path );
}

//-------------------------------------------------------------------------------------------------
Sync_WhitelistPlugins() {

	// servertools
	decl String:filename[128];
	GetPluginFilename( INVALID_HANDLE, filename, sizeof filename );
	BuildPath( Path_SM, filename, sizeof filename, "plugins/%s", filename );
	ReplaceString( filename, sizeof(filename), "\\", "/" );
	SetTrieValue( sync_plugins, filename, 1 );
}

//-------------------------------------------------------------------------------------------------
public OnGetSyncManifest( Handle:hndl, CURLcode:code, any:data ) {
	// phase1
	CloseHandle(hndl);
	new Handle:file;
	decl String:tempfile[256]; 
	ResetPack(data);
	file = Handle:ReadPackCell(data);
	ReadPackString( data, tempfile, sizeof tempfile );
	CloseHandle(data);
	CloseHandle(file);
	
	if( code != CURLE_OK ) {
		OperationError( "couldn't retrieve manifest." );
		CompleteOperation();
		return;
	}
	
	// parse manifest
	new Handle:kv = CreateKeyValues( "servertools_manifest" );
	if( !FileToKeyValues( kv, tempfile ) ) {
		CloseHandle(kv);
		OperationError( "couldn't parse manifest." );
		CompleteOperation();
		return;
	}
	
	if( !KvJumpToKey( kv, "packages" ) || !KvGotoFirstSubKey( kv ) ) {
		CloseHandle(kv);
		OperationError( "no packages in manifest." );
		CompleteOperation();
		return;
	}
	
	OperationLog( "parsing manifest..." );
	
	sync_plugins = CreateTrie();
	Sync_WhitelistPlugins();
	
	
	sync_list = CreateDataPack();
	new Handle:file_filter = CreateTrie(); // file_filter is used to cancel duplicate files (ie multiple packages sharing files)
	
	do {
		decl String:packagename[64];
		KvGetSectionName( kv, packagename, sizeof packagename );
		decl String:target[64];
		KvGetString( kv, "target", target, sizeof target, "" );
		if( target[0] == 0 ) {
			
			OperationError( "package \"%s\" is missing target", packagename );
			continue;
		}
		
		if( !IsTarget( target ) ) continue;
		
		OperationLog( "reading package \"%s\"...", packagename );
		if( KvGetNum( kv, "disabled", 0 ) != 0 ) {
			OperationLog( "skipping -- package is disabled.", packagename ); 
			continue;
		}
		
		if( KvJumpToKey( kv, "files" ) ) {
			if( KvGotoFirstSubKey( kv, false ) ) {
			
				do {
					decl String:filename[128];
					decl String:remote[128];
					KvGetSectionName( kv, filename, sizeof filename );
					TrimString(filename);
					if( filename[0] == 0 ) continue;
					if( !FormatLocalPath( filename, sizeof filename, filename ) ) {
						OperationError( "package \"%s\" :: bad path: \"%s\"", packagename, filename );
						continue;
					}
					
					KvGetString( kv, NULL_STRING, remote, sizeof remote, "" );
					TrimString( remote );
					
					new plugin_mode = 0;
					if( StrContains( remote, "?install" ) != -1 ) {
						ReplaceString( remote, sizeof remote, "?install", "" );
						plugin_mode = 1;
					}
					if( StrContains( remote, "?ignore" ) != -1 ) {
						ReplaceString( remote, sizeof remote, "?ignore", "" );
						plugin_mode = 2;
					}
					TrimString( remote );
					if( remote[0] != 0 ) {
						
						if( !FormatLocalPath( remote, sizeof remote, remote ) ) {
							OperationError( "package \"%s\" :: bad path: \"%s\"", packagename, remote );
							continue;
						}
					}
					
					if( FileIsNormalPlugin( filename ) ) {
						if( SetTrieValue( sync_plugins, filename, 1, false ) ) {
							
						}
						
						if( !sync_reinstall &&  plugin_mode == 1 ) {
							if( FileExists( filename ) ) {
								OperationLog( "--plugin \"%s\" exists, skipping (install mode).", filename );
								continue; // plugin exists, don't update in "install" mode
							}
							if( TryCopyDisabledPlugin( filename ) ) {
								OperationLog( "--plugin \"%s\" moving from disabled folder (install mode).", filename );
								continue;
							}
						} else if( plugin_mode == 2 ) {
							continue; // ignore the state of this plugin
						}
						
					} else if( plugin_mode == 2 ) {
					
						OperationError( "packages \"%s\" :: plugin option used for normal file. skipping", packagename );
						continue;
					} else if( plugin_mode == 1 ) {
						if( FileExists( filename ) ) {
							OperationLog( "--file \"%s\" :: skipping (install mode)", filename );
							continue;
						}
					}
					
					
					
					new dummy;
					// add to downloads if file is unique
					if( !GetTrieValue( file_filter, filename, dummy ) ) {
						SetTrieValue( file_filter, filename, 1 );
						WritePackString( sync_list, filename );
						
						if( remote[0] != 0 ) {
							
							WritePackString( sync_list, remote );
						} else {
							WritePackString( sync_list, filename );
						}
						
					}
				
				} while( KvGotoNextKey( kv, false ) );
				
				KvGoBack( kv );
				
			}
			KvGoBack( kv );
		}
		
		
	} while( KvGotoNextKey( kv ) );
	CloseHandle( kv );
	CloseHandle( file_filter );
	 
	ResetPack( sync_list );
	sync_updates = CreateDataPack();
	
	sync_hashes = LoadFileHashes();
	
	ResetPack( sync_list );
	UpdateBinaryHashes();
}

//-------------------------------------------------------------------------------------------------
UpdateBinaryHashes() {
	
	while( IsPackReadable( sync_list, 1 ) ) {
		
		decl String:file[128];
		decl String:remote[128];
		ReadPackString( sync_list, file, sizeof file ); // local path
		ReadPackString( sync_list, remote, sizeof remote ); // remote path
		
		if( !FileExists(file) ) continue;
		
		decl String:ext[32];
		GetFileExt( ext, sizeof ext, file );
		if( TrieSet( sync_binaries, ext ) ) {
			// this is a binary file, hash it client-side
			
			OperationLog( "Hashing binary file: \"%s\"...", file );
			new Handle:data = CreateDataPack();
			WritePackString( data, file );
			curl_hash_file( file, Openssl_Hash_MD4, OnFileHashed, data );
			return;
		}
	}
	
	ResetPack( sync_list );
	ProcessSyncFiles();
}

//-------------------------------------------------------------------------------------------------
public OnFileHashed( const bool:success, const String:buffer[], any:data ) {
	decl String:file[128];
	ResetPack(data);
	ReadPackString( data, file, sizeof file );
	CloseHandle(data);
	OperationLog( "--%s", buffer );
	
	KvJumpToKey( sync_hashes, file, true );
	KvSetString( sync_hashes, NULL_STRING, buffer );
	KvGoBack( sync_hashes );
	
	UpdateBinaryHashes();
}

//-------------------------------------------------------------------------------------------------
ProcessSyncFiles() {
	// phase2
	
	new start = GetPackPosition( sync_list );
	if( !IsPackReadable( sync_list, 1 ) ) {
		ResetPack( sync_updates );
		Sync_GetUpdate(); 
		return;
	}
	
	// request file hashes
	new Handle:curl = curl_easy_init();
	curl_easy_setopt_int_array( curl, CURLDefaultOpt, sizeof( CURLDefaultOpt ) );
	decl String:url[512];
	FormatEx( url, sizeof url, "%s%s?%s", sync_url, sync_listing, url_request_params );
	 
	decl String:tempfile[256];
	GetTempFile( tempfile, sizeof(tempfile) );
	new Handle:outfile = curl_OpenFile( tempfile, "wb" );
	curl_easy_setopt_string( curl, CURLOPT_URL, url );
	curl_easy_setopt_handle( curl, CURLOPT_WRITEDATA, outfile );
	new Handle:post = curl_httppost();
	
	// create request
	for( new i = 0; i < 25; i ++ ) { 
		if( !IsPackReadable( sync_list, 1 ) ) break;
		decl String:postname[8];
		decl String:file[128];
		ReadPackString( sync_list, file, sizeof file ); // local path
		ReadPackString( sync_list, file, sizeof file ); // remote path (desired)
		FormatEx( postname, sizeof postname, "%d", i+1 );
		curl_formadd( post, CURLFORM_COPYNAME, postname, CURLFORM_COPYCONTENTS, file, CURLFORM_END ); 
	}
	sync_list_next = GetPackPosition( sync_list );
	SetPackPosition( sync_list,start );
	
	curl_easy_setopt_handle( curl, CURLOPT_HTTPPOST, post );
	
	new Handle:pack = CreateDataPack();
	WritePackCell( pack, _:outfile );
	WritePackString( pack, tempfile );
	curl_easy_perform_thread( curl, Sync_OnGetHashes, pack );
	 
}

//-------------------------------------------------------------------------------------------------
public Sync_OnGetHashes( Handle:hndl, CURLcode:code, any:data ) {
	CloseHandle(hndl);
	new Handle:file;
	decl String:tempfile[256]; 
	ResetPack(data);
	file = Handle:ReadPackCell(data);
	ReadPackString( data, tempfile, sizeof tempfile );
	CloseHandle(data);
	CloseHandle(file);
	
	if( code != CURLE_OK ) {
		OperationError( "couldn't retrieve file hashes." );
		CompleteOperation();
		return;
	}
	
	file = OpenFile( tempfile, "rb" );
	
	new file_index = 0;
	
	decl String:buffer[64];
	ReadFileLine( file, buffer, sizeof buffer );
	TrimString(buffer);
	if( !StrEqual( buffer, "HASH/LISTING" ) ) {
		OperationError( "couldn't retrieve file hashes." );
		CompleteOperation();
		return;
	}
	
	while( ReadFileLine( file, buffer, sizeof buffer ) ) { 
		file_index++;
		
		TrimString(buffer);
		if( buffer[0] == 0 ) continue;
		if( !StrEqual( buffer,"HASH" ) ) {
			CloseHandle(file);
			OperationError( "fatal - remote hashlist error (1) data:%s", buffer );
			CompleteOperation();
			return;
		}
		
		ReadFileLine( file, buffer, sizeof buffer  ); // index
		TrimString(buffer);
		if( StringToInt(buffer) != file_index ) {
			CloseHandle(file);
			OperationError( "fatal - remote hashlist error (2)" );
			CompleteOperation();
			return;
		}
 
		ReadFileLine( file, buffer, sizeof buffer  ); // hash
		TrimString(buffer);
		
		decl String:localfile[128];
		decl String:remotefile[128];
		ReadPackString( sync_list, localfile, sizeof localfile );
		ReadPackString( sync_list, remotefile, sizeof remotefile );
		if( StrEqual( buffer, "MISSING" ) ) {
			OperationError( "remote file MISSING: %s", remotefile );
			continue;
		}
		
		// check hash table for file
		if( FileExists( localfile ) && KvJumpToKey( sync_hashes, localfile ) ) {
			decl String:hash[128];
			KvGetString( sync_hashes, NULL_STRING, hash, sizeof hash );
			KvGoBack( sync_hashes );
			if( StrEqual( hash, buffer ) ) {
				// file is up to date
				OperationLog( "\"%s\" is up-to-date.", localfile );
				continue;
			}
		}
		
		OperationLog( "\"%s\" marked; hash=%s", localfile, buffer );
		WritePackString( sync_updates, remotefile );
		WritePackString( sync_updates, localfile );
		WritePackString( sync_updates, buffer ); //hash
	//	WritePackCell( sync_updates, filesize ); 
		
	}
	CloseHandle(file);
	
	if( GetPackPosition( sync_list ) != sync_list_next ) {
		OperationError( "fatal - checkpoint failure" );
		CompleteOperation();
		return;
	}
	//DeleteFile( tempfile ); debug
	
	ProcessSyncFiles();
}

//-------------------------------------------------------------------------------------------------
Sync_GetUpdate() {
	// phase3

	if( !IsPackReadable( sync_updates, 1 ) ) {	
		SaveFileHashes( sync_hashes );
		Sync_AdjustPlugins();
		return;
	}
	
	
	decl String:file[128];
	ReadPackString( sync_updates, file, sizeof file );
	
	OperationLog( "getting \"%s\"...", file );
	
	new Handle:curl = curl_easy_init();
	curl_easy_setopt_int_array( curl, CURLDefaultOpt, sizeof( CURLDefaultOpt ) );
	decl String:url[512];
	FormatEx( url, sizeof url, "%s%s?%s", sync_url, file, url_request_params );
	
	decl String:tempfile[256];
	GetTempFile( tempfile, sizeof(tempfile) );
	new Handle:outfile = curl_OpenFile( tempfile, "wb" );
	curl_easy_setopt_string( curl, CURLOPT_URL, url );
	curl_easy_setopt_handle( curl, CURLOPT_WRITEDATA, outfile );
	
	new Handle:pack = CreateDataPack();
	WritePackCell( pack, _:outfile );
	WritePackString( pack, tempfile );
	curl_easy_perform_thread( curl, Sync_OnFileDownloaded, pack );
}

#define HTTP_RESPONSE_OK 200

//-------------------------------------------------------------------------------------------------
public Sync_OnFileDownloaded( Handle:hndl, CURLcode:code, any:data ) {
	
	new Handle:file;
	decl String:tempfile[256]; 
	ResetPack(data);
	file = Handle:ReadPackCell(data);
	ReadPackString( data, tempfile, sizeof tempfile );
	CloseHandle(data);
	CloseHandle(file);
	
	new response;
	curl_easy_getinfo_int(hndl,CURLINFO_RESPONSE_CODE,response);
	if( code != CURLE_OK || response != HTTP_RESPONSE_OK ) {
		CloseHandle(hndl);
		OperationError( "fatal: error retrieving file." );
		CompleteOperation();
		return;
	}
	CloseHandle(hndl);
	
	decl String:localfile[128];
	decl String:hash[128];
	ReadPackString( sync_updates, localfile, sizeof localfile );
	ReadPackString( sync_updates, hash, sizeof hash );
 
	if( !PrimeFileTarget( localfile ) ) {
		OperationError( "fatal: disk error (prime path)" );
		CompleteOperation();
		return;
	}
	
	decl String:ext[32];
	GetFileExt( ext, sizeof ext, localfile );
	if( TrieSet( pp_trie, ext ) ) {
		PreprocessFile( tempfile, sizeof tempfile );
	}
	
	if( !RenameFile( localfile, tempfile ) ) {
		OperationError( "fatal: disk error (move file)" );
		CompleteOperation();
		return;
	}
	
	if( KvJumpToKey( sync_hashes, localfile, true ) ) {
		KvSetString( sync_hashes, NULL_STRING, hash );
		KvGoBack( sync_hashes );
	}
	
	Sync_GetUpdate();
}

//-------------------------------------------------------------------------------------------------
AdjustPluginsFunction( const String:path[], bool:toplevel=false ) {
	new Handle:dir = OpenDirectory( path );
	new plstart = StrContains( path, "plugins" ) + 8;
	decl String:entry[256];
	new FileType:ft;
	while( ReadDirEntry( dir, entry, sizeof entry, ft ) ) {
		if( ft == FileType_Directory ) {
			if( StrEqual( entry, "." ) ||
				StrEqual( entry, ".." ) ||
				toplevel && StrEqual( entry, "disabled" ) ||
				toplevel && StrEqual( entry, "optional" ) ) 
				continue;
				
			decl String:subdir[128];
			FormatEx( subdir, sizeof subdir, "%s/%s", path, entry );
			AdjustPluginsFunction( subdir );
		} else if( ft == FileType_File ) {
			new dummy;
			
			decl String:fullpath[128];
			FormatEx( fullpath, sizeof fullpath, "%s/%s", path, entry );
			if( !GetTrieValue( sync_plugins, fullpath, dummy ) ) {
				// disable plugin
				OperationLog( "disabling plugin: \"%s\".", fullpath[plstart] );
				DisablePlugin( fullpath );
			}
		}
	}
	CloseHandle( dir );
}

//-------------------------------------------------------------------------------------------------
Sync_AdjustPlugins() {
	// phase4
	
	
	if( sync_checkplugins ) {
		// move unmarked plugins to /disabled/
		decl String:plugins_dir[128];
		BuildPath( Path_SM, plugins_dir, sizeof plugins_dir, "plugins" );
		ReplaceString( plugins_dir, sizeof(plugins_dir), "\\", "/" );
		
		OperationLog( "scanning plugins..." );
		
		AdjustPluginsFunction( plugins_dir, true );
	} else {
		OperationLog( "skipping plugin scan (checkplugins=0)" );
	}
	
	SetLastSync();
	if( initial_sync ) {
		// reload map if no players are playing
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
	
	
	CompleteOperation();
}

//-------------------------------------------------------------------------------------------------
SAFE_CLOSE_HANDLE( &Handle:h ) {
	if( h == INVALID_HANDLE ) return;
	CloseHandle(h);
	h = INVALID_HANDLE;
}

//-------------------------------------------------------------------------------------------------
Sync_Cleanup() {
	SAFE_CLOSE_HANDLE( sync_list );
	SAFE_CLOSE_HANDLE( sync_updates );
	SAFE_CLOSE_HANDLE( sync_hashes );
	SAFE_CLOSE_HANDLE( sync_plugins );
}

//-------------------------------------------------------------------------------------------------
WakeServer() {
	if( sv_hibernate_when_empty != INVALID_HANDLE ) {
		c_hibernate_when_empty = GetConVarInt( sv_hibernate_when_empty );
//		if( c_hibernate_when_empty != 0 ) {
//			ignore_hibernate_change = true;
		SetConVarInt( sv_hibernate_when_empty, 0 );
//		}
	}
}

//-------------------------------------------------------------------------------------------------
SleepServer() {
	if( sv_hibernate_when_empty != INVALID_HANDLE ) {
		if( c_hibernate_when_empty != 0 ) {
			SetConVarInt( sv_hibernate_when_empty, 1 );
		}
	}
}
