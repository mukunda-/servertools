/*
 * Copyright 2014 Mukunda Johnson (www.mukunda.com)
 *
 * This file is part of ServerTools.
 *
 * ServerTools is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * ServerTools is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with ServerTools. If not, see <http://www.gnu.org/licenses/>.
 */

 // legacy primitive operations
// TODO... put all this shit back in..?


// working directories
//new String:path_source[512]; // source path ie "ftp://poop.com/root/" ends with slash
//new String:path_source_httplisting[512]; // source path for directory listing ie "http://poop.com/root/listing.php?path=/" ends with slash
//new String:path_dest[512]; // dest path ie "addons/sourcemod/configs/" ends with slash or is empty
//new FileDomain:dl_source_domain;
//new String:op_pattern[128];
//new Handle:op_pattern_regex = INVALID_HANDLE;


new cfgfind_total;
#define CFGFIND_MAX 20

Legacy_Init() {
	RegServerCmd( "st_copy", Command_copy, "Copy File" );
	
	RegServerCmd( "st_rename", Command_rename, "Rename File" );
	RegServerCmd( "st_dir", Command_dir, "Directory Listing" );
	RegServerCmd( "st_delete", Command_delete, "Delete File" );
	RegServerCmd( "st_mkdir", Command_mkdir, "Create Directory" );
	
	RegServerCmd( "st_cfgfind", Command_cfgfind, "Search all cfg files for a cvar/command" );
	RegServerCmd( "st_cfgedit", Command_cfgedit, "Edit config file" );
	RegServerCmd( "st_view", Command_view, "View a file" );
	RegServerCmd( "st_new", Command_new, "Create New File" );
	RegServerCmd( "st_edit", Command_edit, "Edit File" );
}

//-------------------------------------------------------------------------------------------------
FileDomain:GetFileDomain( const String:file[] ) {
	new firstslash = FindCharInString( file, '/' );
	if( firstslash <= 0 ) return DOMAIN_ERROR;
//	if( (strncmp( file, "ftp/", 4 ) == 0) ) return DOMAIN_FTP;
//	if( (strncmp( file, "http/", 5 ) == 0) ) return DOMAIN_HTTP;
	if( (strncmp( file, "sm/", 3 ) == 0) ) return DOMAIN_LOCAL;
	if( (strncmp( file, "game/", 5 ) == 0) ) return DOMAIN_LOCAL;
	if( (strncmp( file, "cfg/", 4 ) == 0) ) return DOMAIN_LOCAL;
	if( (strncmp( file, "pl/", 3 ) == 0) ) return DOMAIN_LOCAL;
	if( (strncmp( file, "tr/", 3 ) == 0) ) return DOMAIN_LOCAL;
	if( (strncmp( file, "sc/", 3 ) == 0) ) return DOMAIN_LOCAL;
//	if( (strncmp( file, "web/", 4 ) == 0) ) return DOMAIN_WEB;
	return DOMAIN_ERROR;
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
PrintFileHelp() {
	PrintToServer( "source,dest can be in these formats:" );
	 
	PrintToServer( "sm/... - path relative to sourcemod folder" );
	PrintToServer( "game/... - path relative to game root" );
	PrintToServer( "cfg/... - path relative to cfg folder" ); 
	PrintToServer( "pl/... - path relative to plugins folder, \".smx\" is appended" );
	PrintToServer( "tr/... - path relative to translations folder, \".txt\" is appended" );
	PrintToServer( "sc/... - path relative to sourcemod configs folder" );
//	PrintToServer( "ftp/... - remote path relative to ftp directory" );
//	PrintToServer( "http/... - remote path relative to http directory (read only)" );
//	PrintToServer( "web/... - remote path to arbitrary http url" );
	
}


//-------------------------------------------------------------------------------------------------
bool:PathIsDirectory( const String:path[] ) {
	new sl = strlen(path);
	if( sl == 0 ) return true;
	return path[sl-1] == '/';
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
PrintCopyUsage() {
	PrintToServer( "Usage: st_copy [-r] [-m] <source> <dest>" );
	PrintToServer( "-r : directory recursive" );
	PrintToServer( "-m : delete source files (move)" );
	PrintFileHelp();
}

//-------------------------------------------------------------------------------------------------
public Action:Command_copy( args ) {

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

TryDeleteFile( const String:path[] ) {
	if(!FileExists(path) ) return;
	DeleteFile(path);
}
