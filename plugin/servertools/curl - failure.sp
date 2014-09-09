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

//-------------------------------------------------------------------------------------------------
new g_curl_default_options[][2] = {
	{_:CURLOPT_NOSIGNAL,		1}, ///use for threaded only
	{_:CURLOPT_NOPROGRESS,		1},
	{_:CURLOPT_TIMEOUT,			60}, // allow user to specify?
	{_:CURLOPT_CONNECTTIMEOUT,	5},
	{_:CURLOPT_VERBOSE,			0}
};

//-------------------------------------------------------------------------------------------------
#define TRANSFER_ATTEMPTS 4

new Handle:g_curl;
new Handle:g_curl_close_timer = INVALID_HANDLE;
new Handle:g_pending_transfers;
new g_remote_transfer_in_progress;
  
//-------------------------------------------------------------------------------------------------
RemoteTransfer( const String:url[], TransferCompleteCallback:on_complete, any:data=0, Handle:post=INVALID_HANDLE ) {
	
	new Handle:xfer = CreateDataPack();
	WritePackString( xfer, url );
	WritePackCell( xfer, _:on_complete );
	WritePackCell( xfer, data );
	WritePackCell( xfer, _:post );
	PushArrayCell( g_pending_transfers, xfer );
	
	DoNextRemoteTransfer();
}

//-------------------------------------------------------------------------------------------------
KillCURLCloseTimer() {
	if( g_curl_close_timer == INVALID_HANDLE ) return;
	KillTimer( g_curl_close_timer );
	g_curl_close_timer = INVALID_HANDLE;
}

//-------------------------------------------------------------------------------------------------
public Action:CURLCloseTimer( Handle:timer ) {
	if( g_curl == INVALID_HANDLE ) return Plugin_Handled;
	CloseHandle( g_curl );
	g_curl = INVALID_HANDLE;
	return Plugin_Handled;
}

//-------------------------------------------------------------------------------------------------
DoNextRemoteTransfer() {
	
	if( g_remote_transfer_in_progress ) return;
	if( GetArraySize( g_pending_transfers ) == 0 ) return;
	KillCURLCloseTimer();
	g_remote_transfer_in_progress = true;
	new Handle:source = GetArrayCell( g_pending_transfers, 0 );
	RemoveFromArray( g_pending_transfers, 0 );
	ResetPack( source );
	
	decl String:url[512];
	ReadPackString( source, url, sizeof url );
	new TransferCompleteCallback:on_complete = TransferCompleteCallback:ReadPackCell( source );
	new any:data = ReadPackCell( source );
	new Handle:post = Handle:ReadPackCell( source );
	CloseHandle( source );
	
	new Handle:kv = CreateKeyValues( "STDownload" );
	KvSetString( kv, "url", url );
	
	decl String:tempfile[256];
	GetTempFile( tempfile, sizeof(tempfile) );
	
	KvSetString( kv, "file", tempfile );
	
	if( g_curl == INVALID_HANDLE ) {
		g_curl = curl_easy_init();
		curl_easy_setopt_int_array( g_curl, g_curl_default_options, sizeof( g_curl_default_options ) );
	}
	
	new Handle:outfile = curl_OpenFile( tempfile, "wb" );
	curl_easy_setopt_string( g_curl, CURLOPT_URL, url );
	curl_easy_setopt_handle( g_curl, CURLOPT_WRITEDATA, outfile );
	
	if( post != INVALID_HANDLE ) {
		curl_easy_setopt_handle( g_curl, CURLOPT_HTTPPOST, CURLBuildPost( post ) ); 
	}
	
	KvSetHandle( kv, "outfile", outfile );
	KvSetNum( kv, "attempt", 0 );
	KvSetHandle( kv, "post", post );
	KvSetNum( kv, "userdata", data );
	KvSetNum( kv, "on_complete", _:on_complete );
	
	curl_easy_perform_thread( g_curl, OnCURLTransferComplete, kv );
}

//-------------------------------------------------------------------------------------------------
CURLRetryTransfer( Handle:kv ) {
	decl String:url[512];
	KvGetString( kv, "url", url, sizeof url );
	decl String:tempfile[256];
	KvGetString( kv, "file", tempfile, sizeof tempfile );
//	new Handle:post = Handle:KvGetNum( kv, "post" );
	
	curl_easy_setopt_int_array( g_curl, g_curl_default_options, sizeof( g_curl_default_options ) );
	new Handle:outfile = curl_OpenFile( tempfile, "wb" );
	curl_easy_setopt_string( g_curl, CURLOPT_URL, url );
	curl_easy_setopt_handle( g_curl, CURLOPT_WRITEDATA, outfile );
//	if( post != INVALID_HANDLE ) {
//		curl_easy_setopt_handle( g_curl, CURLOPT_HTTPPOST, CURLBuildPost( post ) );
//	}
	KvSetHandle( kv, "outfile", outfile );
	curl_easy_perform_thread( g_curl, OnCURLTransferComplete, kv );
}
 
//-------------------------------------------------------------------------------------------------
Handle:CURLBuildPost( Handle:data ) {
	ResetPack(data);
	decl String:postname[128];
	decl String:postdata[512];
	
	new Handle:post = curl_httppost();
	
	PrintToServer( "DEBUG BUILDING POST " );
	new index = 0;
	while( IsPackReadable(data,1) ) { 
		ReadPackString( data, postname, sizeof postname );
		ReadPackString( data, postdata, sizeof postdata ); 
		curl_formadd( post, CURLFORM_COPYNAME, postname, CURLFORM_COPYCONTENTS, postdata, CURLFORM_END ); 
		index++;
	}
	PrintToServer( "DEBUG BUILDING POST COMPLETE %d ", index );
	return post;
}

//-------------------------------------------------------------------------------------------------
bool:CURLDeletePostPack( Handle:kv ) {
	new Handle:post = KvGetHandle( kv, "post" );
	if( post != INVALID_HANDLE ) {
		CloseHandle(post);
		KvSetHandle( kv, "post", INVALID_HANDLE );
		return true;
	}
	return false;
}

//-------------------------------------------------------------------------------------------------
public OnCURLTransferComplete( Handle:hndl, CURLcode:code, any:kv ) {
	
	CloseHandle( KvGetHandle( kv, "outfile" ) );
		
	const HTTP_RESPONSE_OK = 200;
	
	new response;
	curl_easy_getinfo_int( hndl, CURLINFO_RESPONSE_CODE, response );
	 
	if( code != CURLE_OK || response != HTTP_RESPONSE_OK  ) {
		
		// retry if not 404 and not too many attempts
		new attempt = KvGetNum( kv, "attempt" );
		attempt++;
		if( attempt >= TRANSFER_ATTEMPTS || response == 404 ) {
			if( response == 404 ) {
				KvSetNum( kv, "notfound", 1 );
			}
			decl String:file[128];
			KvGetString( kv, "file", file, sizeof file );
			TryDeleteFile( file );
			
			Call_StartFunction( INVALID_HANDLE, Function:KvGetNum( kv, "on_complete" ) );
			Call_PushCell( kv );
			Call_PushCell( false );
			Call_PushCell( KvGetNum( kv, "userdata" ) );
			Call_Finish();
			new bool:haspost = CURLDeletePostPack(kv);
			CloseHandle(kv);
			
			RemoteTransferFinished( haspost );
			return;
		}
		
		// retry
		KvSetNum( kv, "attempt", attempt );
		CURLRetryTransfer( kv );
		return;
		
	} else {
		Call_StartFunction( INVALID_HANDLE, Function:KvGetNum( kv, "on_complete" ) );
		Call_PushCell( kv );
		Call_PushCell( true );
		Call_PushCell( KvGetNum( kv, "userdata" ) );
		Call_Finish();
		
		decl String:file[128];
		KvGetString( kv, "file", file, sizeof file );
		//TryDeleteFile( file ); DEBUG BYPASS
			
		new bool:haspost = CURLDeletePostPack(kv);
		CloseHandle(kv);
		
		RemoteTransferFinished( haspost );
	}
}

//-------------------------------------------------------------------------------------------------
RemoteTransferFinished( bool:close ) {
	
	g_remote_transfer_in_progress = false;
	
	if( close ) {
		CloseHandle( g_curl );
		g_curl = INVALID_HANDLE;
	}
	if( GetArraySize( g_pending_transfers ) == 0 ) {

		if( !close ) CreateTimer( 1.0, CURLCloseTimer );
		return;
	} else {
		DoNextRemoteTransfer();
	}
}
