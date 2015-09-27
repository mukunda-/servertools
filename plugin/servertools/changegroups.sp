/*
 * Copyright 2015 Mukunda Johnson (www.mukunda.com)
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

//------------------------------------------------------------------------------
public Action:Command_addgroups( args ) {
	
	new Handle:kv = LoadKVConfig( "servertools_id", "servertools_id.cfg" );
	if( kv == INVALID_HANDLE ) {
		PrintToServer( "Error, couldn't load config!" );
		return Plugin_Handled;
	}
	
	new String:groupstring[256];
	KvGetString( kv, "Groups", groupstring, sizeof(groupstring), "" );
	
	new String:list[64][32];
	new count = ExplodeString( groupstring, " ", list, sizeof list, sizeof list[] );
	
	new String:arg[32];
	
	for( new i = 1; i <= args; i++ ) {
		GetCmdArg( i, arg, sizeof arg );
		new bool:duplicate = false;
		
		for( new j = 0; j < count; j++ ) {
			if( StrEqual( list[j], arg, false )) {
				duplicate = true;
				break;
			}
		}
		if( duplicate ) continue;
		
		list[count] = arg;
		count++;
	}
	
	ImplodeStrings( list, count, " ", groupstring, sizeof groupstring );
	
	KvSetString( kv, "Groups", groupstring );
	
	SaveKVConfig( kv, "servertools_id.cfg" );
	CloseHandle( kv );
	
	LoadIDConfig();
	PrintToServer( "[ST] groups = \"%s\"", my_groups ); 
	
	return Plugin_Handled;
}

//------------------------------------------------------------------------------
public Action:Command_removegroups( args ) {
	
	new Handle:kv = LoadKVConfig( "servertools_id", "servertools_id.cfg" );
	if( kv == INVALID_HANDLE ) {
		PrintToServer( "Error, couldn't load config!" );
		return Plugin_Handled;
	}
	
	new String:groupstring[256];
	KvGetString( kv, "Groups", groupstring, sizeof groupstring, "" );
	
	new String:list[64][32];
	new count = ExplodeString( groupstring, " ", list, sizeof list, sizeof list[] );
	
	new String:arg[32];
	for( new i = 1; i <= args; i++ ) {
		GetCmdArg( i, arg, sizeof arg );
		
		for( new j = 0; j < count; j++ ) {
			if( StrEqual( list[j], arg, false )) {
				list[j] = "";
			}
		}
	}
	
	new copyto = 0;
	
	for( new i = 0; i < count; i++ ) {
		
		if( list[i][0] == 0 ) {
			// empty string, skip
			
		} else {
			strcopy( list[copyto], sizeof list[], list[i] );
			copyto++;
		}
	}
	
	count = copyto;
	
	ImplodeStrings( list, count, " ", groupstring, sizeof groupstring );
	KvSetString( kv, "Groups", groupstring );
	SaveKVConfig( kv, "servertools_id.cfg" );
	CloseHandle( kv );
	LoadIDConfig();
	PrintToServer( "[ST] groups = \"%s\"", my_groups ); 
	
	return Plugin_Handled;
}
