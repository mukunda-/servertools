<?php

header("Content-Type: text/plain");

//-----------------------------------------------------------------------------
class FileHash {
	public $hash = "";
	public $date = 0;
	public $size = 0;
	
	function __construct( $file ) {
		$this->hash = hash_file( 'md4', $file );
		$this->date = filemtime( $file );
		$this->size = filesize( $file );
	}
};

//-----------------------------------------------------------------------------
function TryReadHash( $hash, $file ) {
	
	$hash_expiry = 60*60*24*3; // 3 days

	if( !file_exists( $hash ) ) return FALSE;
	if( time() >= (filemtime( $hash ) + $hash_expiry) ) return FALSE;
	$data = file_get_contents( $hash );
	if( $data === FALSE ) return FALSE;
	$data = unserialize($data);
	if( $data === FALSE ||
		$data->date != filemtime( $file ) ||
		$data->size != filesize( $file ) ) {
		
		return FALSE;
	}	
	return $data;
}

//-----------------------------------------------------------------------------
function GetFileHash( $path ) {
 
	$hash = "__hashes/" . $path . ".hash";
	$data = TryReadHash( $hash, $path );
	if( $data !== FALSE ) return $data;
	$dir = pathinfo($hash,PATHINFO_DIRNAME);
	if( !is_dir( $dir ) ) {
		if( file_exists($dir) ) unlink( $dir );
		mkdir( $dir, 0777, true );
	}
	$data = new FileHash( $path );
	file_put_contents( $hash, serialize($data) );
	return $data;
}

echo "HASH/LISTING\n";
//-----------------------------------------------------------------------------
for( $i = 1; $i <= 25; $i++ ) {
	if( !isset( $_POST[$i] ) ) continue;
	$file = $_POST[$i];
	$hash = 'MISSING'; 
	if( file_exists($file) ) {
		$hash = GetFileHash( $file )->hash;
	}
	
	echo "HASH\n" .
		$i . "\n" . 
		$hash . "\n";
}

?>