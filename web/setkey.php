<?php
	if( !isset($_REQUEST['newkey']) ) {
		die( "please specify \"newkey\"" );
	}
	
	$key = $_REQUEST['newkey'];
	$key = trim($key);

	if( file_exists( ".htaccess" ) ) {
		unlink( ".htaccess" );
	}
	
	if( $key == "" ) {
		echo "KEY REMOVED.";
	} else {
		
		echo "KEY SET TO \"$key\".";
		$key = preg_quote($key);
		
		file_put_contents( ".htaccess", '
RewriteEngine On
RewriteCond %{QUERY_STRING} !(^|&)key='.$key.'($|&)
RewriteRule ^.*$ - [R=403,L]
'
		);
	}
?>