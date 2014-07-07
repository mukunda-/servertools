<?php

header("Content-Type: text/plain");

echo "LISTING";
//-----------------------------------------------------------------------------
for( $i = 1; $i <= 50; $i++ ) {
	if( !isset( $_POST[$i] ) ) continue;
	$file = $_POST[$i];
	if( file_exists($file) ) {
		echo "\n" . filesize( $file ) . "\n" . filemtime( $file );
	} else {
		echo "\n[SKIP]";
	} 
}

?>