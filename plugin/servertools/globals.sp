
new String:my_id[64];
new String:my_groups[256];

new Handle:g_text_extensions; // file extensions that should be treated as text files
new Handle:termcount_trie; // trie for looking up terms to get default termcount values (for command matching)

new String:g_logfile[128];

new String:g_remote_url[256];
new String:g_remote_key[64];
new String:g_remote_dir[64];
new String:g_remote_dirns[64];
new String:g_url_request_params[256]; // the id and groups for placing in a URL

new Handle:g_sync_paths = INVALID_HANDLE;
 

enum {
	SYNCPATHFLAG_RECURSIVE=1,
	SYNCPATHFLAG_PLUGINS=2,
	SYNCPATHFLAG_ALL=4,
	SYNCPATHFLAG_FORCE=8,
	SYNCFLAG_NORELOAD=16
};

functag TransferCompleteCallback public( Handle:hndl, bool:success, any:data );
functag OperationEntry public( Handle:hndl );
