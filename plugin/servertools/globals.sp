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
