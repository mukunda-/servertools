/*
 * ServerTools Console
 *
 * Copyright 2014 Mukunda Johnson
 *
 * Licensed under The MIT License, see COPYING.MIT
 */
 
#pragma once

#ifndef UTIL_STRINGLES_H
#define UTIL_STRINGLES_H

#include <assert.h>

namespace Util {

int StringToInt( const char *str );
bool StringToBool( const char *str );
double StringToFloat( const char *str );

//-------------------------------------------------------------------------------------------------
// str = str[start..end]
// parameters are inclusive
//
void CropString( char *str, int start, int end );

//-------------------------------------------------------------------------------------------------
// str = str[start...]
//
void CropStringLeft( char *str, int start );

//-------------------------------------------------------------------------------------------------
// remove all quote characters in a string
// yes...all of them
void StripQuotes( char *str );

//-------------------------------------------------------------------------------------------------
// remove whitespace from beginning and end of string
//
void TrimString( char *str );

//-------------------------------------------------------------------------------------------------
// extracts an argument from a string, cutting it out and copying it to the dest
// source now points to the next argument, or is empty
void ScanArgString( char *source, char *dest, int maxlen );

//-------------------------------------------------------------------------------------------------
// returns false if result was truncated
bool CopyString( char *dest, size_t maxlen, const char *source );
template <size_t maxlen>
bool CopyString( char (&dest)[maxlen], const char *source ) {
	return CopyString( dest, maxlen, source );
}

char *BreakString( char *source, char *dest, int maxlen );

//-------------------------------------------------------------------------------------------------
static inline bool StrEmpty( const char *string ) {
	return string[0] == 0;
}

//-------------------------------------------------------------------------------------------------
bool StrEqual( const char *a, const char *b, bool case_sensitive = true );

void StringToUpper( char *str );
void StringASCIIFilter( char *str );

};

#endif
