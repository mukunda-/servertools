/*
 * ServerTools Console
 *
 * Copyright 2014 Mukunda Johnson
 *
 * Licensed under The MIT License, see COPYING.MIT
 */
 
#pragma once
#include <stdio.h>

//-------------------------------------------------------------------------------------------------
class FileReader {

	FILE *file;

public:
	FileReader( const char *path ) {
		file = fopen( path, "r" );
	}

	~FileReader() {
		if( file ) fclose(file);
	}

	bool ReadLine( char *dest, int maxlen ) {
		if( !file ) return false;
		char *a = fgets( dest, maxlen, file );
		if( a == dest ) return true;
		return false;
	}

	template <size_t maxlen> bool ReadLine( char (&dest)[maxlen] ) {
		return ReadLine( dest, maxlen );
	}

	bool EndOfFile() {
		if( !file ) return true;
		return !!feof(file);
	}
};

