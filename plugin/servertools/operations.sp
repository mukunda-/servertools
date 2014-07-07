
// threaded operation management

new Handle:g_operation_queue;
new Handle:g_completed_operations;
new g_operation_id=1;
new bool:g_operation_in_progress = false;

//-----------------------------------------------------------------------------
Operations_Init() {
	g_operation_queue = CreateArray();
	g_completed_operations = CreateArray();
}

//-----------------------------------------------------------------------------
Handle:CreateOperation( const String:name[], OperationEntry:entry ) {
	
	new Handle:op = CreateKeyValues("Operation");
	KvSetString( op, "name", name );
	KvSetNum( op, "id", g_operation_id++ );
	KvSetNum( op, "finished", 0 );
	KvSetNum( op, "errors", 0 );
	KvSetHandle( op, "errorlist", CreateDataPack() );
	KvSetHandle( op, "log", CreateDataPack() );
	KvSetNum( op, "entry", _:entry );
	PrintToServer( "[ST] OPCREATE:%d", g_operation_id-1 );
	return op;
}

//-----------------------------------------------------------------------------
OperationError( Handle:op, const String:reason_fmt[], any:... ) {
	decl String:reason[256];
	VFormat( reason, sizeof(reason), reason_fmt, 3 );
	
	WritePackString( KvGetHandle( op, "errorlist" ), reason );
	KvSetNum( op, "errors", KvGetNum( op, "errors" ) + 1 );
	
	LogToFile( g_logfile, "error: %s", reason );
}

//-----------------------------------------------------------------------------
OperationLog( Handle:op, const String:reason_fmt[], any:... ) {
	decl String:reason[256];
	VFormat( reason, sizeof(reason), reason_fmt, 3 );
	WritePackString( KvGetHandle( op, "log" ), reason ); 
	LogToFile( g_logfile, "%s", reason );
}


//-------------------------------------------------------------------------------------------------
PrintOperationResult( Handle:op ) {
	new Handle:log = KvGetHandle( op, "log" );
	new Handle:errlist = KvGetHandle( op, "errorlist" );
	new errors = KvGetNum( op, "errors" );
	ResetPack( log );
	ResetPack( errlist );
	while( IsPackReadable( errlist, 1 ) ) {
		decl String:errline[256];
		ReadPackString( errlist, errline, sizeof(errline) );
		TrimString(errline);
		PrintToServer( "[ST] Error: %s", errline );
	}
	while( IsPackReadable( log, 1 ) ) {
		decl String:line[256];
		ReadPackString( log, line, sizeof(line) );
		TrimString(line);
		PrintToServer( "[ST] %s", line );
	}
	 
	if( errors > 0 ) {
		PrintToServer( "[ST] %d errors", errors );
	}
}

//-----------------------------------------------------------------------------
PrintOperationStatus( id ) {
	for( new i = 0; i < GetArraySize( g_operation_queue ); i++ ) {
		new Handle:op = GetArrayCell( g_operation_queue, i );
		if( KvGetNum( op, "id" ) == id ) {
			PrintToServer( "[ST] STATUS: BUSY" );
			return;
		}
	}
	
	for( new i = 0; i < GetArraySize( g_completed_operations ); i++ ) {
		new Handle:op = GetArrayCell( g_completed_operations, i );
		if( KvGetNum( op, "id" ) == id ) {
			PrintToServer( "[ST] STATUS: COMPLETE" );
			PrintOperationResult( op );
			return;
		}
	}
	
	PrintToServer( "[ST] STATUS: NOTFOUND" );
}

//-----------------------------------------------------------------------------
CloseOperation( Handle:op ) {
	CloseHandle( KvGetHandle( op, "errorlist" ) );
	CloseHandle( KvGetHandle( op, "log" ) );
	CloseHandle( op );
}

//-----------------------------------------------------------------------------
StartOperation( Handle:op ) {
	
	PushArrayCell( g_operation_queue, op );
	StartNextOperation();
}

//-----------------------------------------------------------------------------
StartNextOperation() {
	if( g_operation_in_progress ) return;
	if( GetArraySize( g_operation_queue ) == 0 ) {
		SleepServer();
		return;
	}
	WakeServer();
	g_operation_in_progress = true;
	new Handle:kv = GetArrayCell( g_operation_queue, 0 );
	
	new Function:entry = Function:KvGetNum( kv, "entry" );
	Call_StartFunction( INVALID_HANDLE, entry );
	Call_PushCell( kv );
	Call_Finish();
}

//-----------------------------------------------------------------------------
EndOperation( Handle:op ) {
	g_operation_in_progress = false;
	KvSetNum( op, "finished", 1 ); 
	RemoveFromArray( g_operation_queue, 0 );
	PushArrayCell( g_completed_operations, op );
	
	decl String:name[128];
	KvGetString( op, "name", name, sizeof name );
	PrintToServer( "[ST] Operation Ended: (%d) %s", KvGetNum( op, "id" ), name );
	// delete result after 10 minutes
	CreateTimer( 600.0, DeleteOperationStatus, op );
	
	StartNextOperation();
}

//-----------------------------------------------------------------------------
public Action:DeleteOperationStatus( Handle:timer, Handle:hndl ) {
	new size = GetArraySize( g_completed_operations );
	for( new i = 0; i < size; i++ ) {
		if( GetArrayCell( g_completed_operations, i ) == hndl ) {
			RemoveFromArray( g_completed_operations, i );
			break;
		}
	}
	CloseOperation( hndl );
	return Plugin_Handled;
}
