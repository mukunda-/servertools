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

// todo: add timer to ensure server is awake during operations.

new c_hibernate_when_empty; 

//-------------------------------------------------------------------------------------------------
WakeServer() {
	new Handle:sv_hibernate_when_empty = FindConVar( "sv_hibernate_when_empty" );
	if( sv_hibernate_when_empty != INVALID_HANDLE ) {
		c_hibernate_when_empty = GetConVarInt( sv_hibernate_when_empty ); 
		SetConVarInt( sv_hibernate_when_empty, 0 ); 
	}
}

//-------------------------------------------------------------------------------------------------
SleepServer() {
	new Handle:sv_hibernate_when_empty = FindConVar( "sv_hibernate_when_empty" );
	if( sv_hibernate_when_empty != INVALID_HANDLE ) {
		if( c_hibernate_when_empty != 0 ) {
			SetConVarInt( sv_hibernate_when_empty, 1 );
		}
	}
}
