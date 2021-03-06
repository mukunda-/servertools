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

Handle:SetupCurl( Handle:kv, const String:url[], Handle:post=INVALID_HANDLE ) {
	decl String:tempfile[256];
	GetTempFile( tempfile, sizeof(tempfile) );
	KvSetString( kv, "file", tempfile );
	
	new Handle:curl = curl_easy_init();
	curl_easy_setopt_int_array( curl, g_curl_default_options, sizeof( g_curl_default_options ) );
	new Handle:outfile = curl_OpenFile( tempfile, "wb" );
	curl_easy_setopt_string( curl, CURLOPT_URL, url );
	curl_easy_setopt_handle( curl, CURLOPT_WRITEDATA, outfile );
	
	if( post != INVALID_HANDLE ) {
		curl_easy_setopt_handle( curl, CURLOPT_HTTPPOST, CURLBuildPost( post ) ); 
	}
	KvSetHandle( kv, "outfile", outfile );
	return curl;
}
  
//-------------------------------------------------------------------------------------------------
RemoteTransfer( const String:url[], TransferCompleteCallback:on_complete, any:data=0, Handle:post=INVALID_HANDLE ) {
	
	new Handle:kv = CreateKeyValues( "STDownload" );
	KvSetString( kv, "url", url );
	 
	new Handle:curl = SetupCurl( kv, url, post );
	
	KvSetNum( kv, "attempt", 0 );
	KvSetHandle( kv, "post", post );
	KvSetNum( kv, "userdata", data );
	KvSetNum( kv, "on_complete", _:on_complete );
	
	curl_easy_perform_thread( curl, OnCURLTransferComplete, kv );
}

//-------------------------------------------------------------------------------------------------
CURLRetryTransfer( Handle:kv ) {
	decl String:url[512];
	KvGetString( kv, "url", url, sizeof url );
	new Handle:curl = SetupCurl( kv, url, KvGetHandle( kv, "post" ) );
	curl_easy_perform_thread( curl, OnCURLTransferComplete, kv );
}
 
//-------------------------------------------------------------------------------------------------
Handle:CURLBuildPost( Handle:data ) {
	ResetPack(data);
	decl String:postname[128];
	decl String:postdata[512];
	
	new Handle:post = curl_httppost();
	
	new index = 0;
	while( IsPackReadable(data,1) ) { 
		ReadPackString( data, postname, sizeof postname );
		ReadPackString( data, postdata, sizeof postdata ); 
		curl_formadd( post, CURLFORM_COPYNAME, postname, CURLFORM_COPYCONTENTS, postdata, CURLFORM_END ); 
		index++;
	}
	
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
	CloseHandle(hndl);
	if( code != CURLE_OK || response != HTTP_RESPONSE_OK  ) {
	
		decl String:file[128];
		KvGetString( kv, "file", file, sizeof file );
		TryDeleteFile( file );
		
		// retry if not 404 and not too many attempts
		new attempt = KvGetNum( kv, "attempt" );
		attempt++;
		if( attempt >= TRANSFER_ATTEMPTS || response == 404 ) {
			if( response == 404 ) {
				KvSetNum( kv, "notfound", 1 );
			}
			
			
			Call_StartFunction( INVALID_HANDLE, Function:KvGetNum( kv, "on_complete" ) );
			Call_PushCell( kv );
			Call_PushCell( false );
			Call_PushCell( KvGetNum( kv, "userdata" ) );
			Call_Finish();
			CURLDeletePostPack(kv);
			CloseHandle(kv);
			
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
		TryDeleteFile( file );
			
		CURLDeletePostPack(kv);
		CloseHandle(kv);
		
	}
}
