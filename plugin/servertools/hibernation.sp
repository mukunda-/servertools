
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
