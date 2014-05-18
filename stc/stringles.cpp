
#include "stdafx.h"

namespace Util {
	
//-------------------------------------------------------------------------------------------------
int StringToInt( const char *str ) {
	return atoi( str );
}

//-------------------------------------------------------------------------------------------------
double StringToFloat( const char *str ) {
	return atof( str );
}

//-------------------------------------------------------------------------------------------------
bool StringToBool( const char *str ) {
	if( StrEqual(str,"yes",false) ) return true;
	if( StrEqual(str,"no",false) ) return false;

	if( StrEqual(str,"true",false) ) return true;
	if( StrEqual(str,"false",false) ) return false;

	if( StrEqual(str,"on",false) ) return true;
	if( StrEqual(str,"off",false) ) return false;

	return false;
}

//-------------------------------------------------------------------------------------------------
void CropString( char *str, int start, int end ) {
	// copy string
	int i;
	for( i = start; i <= end; i++ ) {
		str[i-start] = str[i];
	}
	str[i-start] = 0;
}

//-------------------------------------------------------------------------------------------------
void CropStringLeft( char *str, int start ) {
	int i;
	for( i = start; str[i]; i++ ) {
		str[i-start] = str[i];
	}
	str[i-start] = 0;
}

//-------------------------------------------------------------------------------------------------
void StripQuotes( char *str ) {
	int write = 0;
	for( int i = 0; str[i]; i++ ) {
		if( str[i] != '"' ) {
			str[write++] = str[i];
		}
	}
	str[write] = 0;
}

//-------------------------------------------------------------------------------------------------
void TrimString( char *str ) {
	int start, end, len;
	int i;

	// find start
	for( i = 0; str[i]; i++ ) {
		if( str[i] < 1 || str[i] > 32 ) break;
	}

	start = i;
	if( str[start] == 0 ) {
		// string is empty
		str[0] = 0; 
		return;
	}

	// find total length
	for( i = start; str[i]; i++ ) {
	}
	len = i;

	// find end
	for( i = len-1; ( str[i] >= 1 && str[i] <= 32 ); i-- ) {
	}
	end = i;

	CropString( str, start, end );
	
	
}

//-------------------------------------------------------------------------------------------------
bool DelimScan( char source, const char *delimiters ) {
	for( int i = 0; delimiters[i]; i++ ) {
		if( source == delimiters[i] ) return true;
	}
	return false;
}

//-------------------------------------------------------------------------------------------------
bool IsWhitespace( char a ) {
	return a == ' ' || a == '\t';
}

//-------------------------------------------------------------------------------------------------
void ScanArgString( char *source, char *dest, int maxlen ) {
	TrimString(source);

	int len = 0;

	bool quotemode = false;

	int write = 0;
	int i;
	for( i = 0; source[i]; ) {
		
		if( quotemode ) {
			if( source[i] == '"' ) {
				i++;
				quotemode = false;
			} else {
				dest[write++] = source[i++];
				if( write == maxlen-1 ) break;
			}
		} else {
			if( source[i] == '"' ) {
				i++;
				quotemode = true;
			} else {
				if( IsWhitespace(source[i]) ) {
					i++;
					break;
				} else {

					dest[write++] = source[i++];
					if( write == maxlen-1 ) break;
				}
			}
		}
	}
	dest[write] = 0;

	if( source[i] ) {
		CropStringLeft( source, i );
	} else {
		source[0] = 0;
	}

	TrimString( source );
	TrimString( dest );
	StripQuotes( dest );
}

//-------------------------------------------------------------------------------------------------
char *BreakString( char *source, char *dest, int maxlen ) {
	char *read = source;
	bool quotes=false;
	int space = maxlen-1;
	assert( space != 0 );

	if( (*read) == '"' ) {
		*read++;

		// copy until end quote is found
		while( (*read) != 0 && (*read) != '"' ) {
			*dest++ = *read++;
			space--;
			if( space == 0 ) { *dest=0; return read; }
			
		}
		*dest = 0; //null termination
 		if( *read == 0 ) return read;
		read++; // skip quote
		
	} else {
		while( (*read) != 0 && (*read) > ' ' ) {
			*dest++ = *read++;
			space--;
			if( space == 0 ) { *dest=0; return read; }
			
		}
		*dest = 0;
	}

	// search for next arg
	while( (*read) <= ' ' && (*read) != 0 ) { 
		read++;
	}
	return read;
}

//-------------------------------------------------------------------------------------------------
bool CopyString( char *dest, size_t maxlen, const char *source ) {
	if( strlen(source) > maxlen-1 ) {
		strncpy( dest, source, maxlen-1 );
		dest[maxlen-1] = 0;
		return false;
	} else {
		strcpy( dest, source );
		return true;
	}
}

//-------------------------------------------------------------------------------------------------
bool StrEqual( const char *a, const char *b, bool case_sensitive ) {
	if( case_sensitive == false ) {
		return strcmp( a,b ) == 0;
	} else {
		//todo: optimize (use a table at least)
		for( int i = 0;; i++ ) {
			char c1, c2;
			c1 = a[i];
			c2 = b[i];
			if( c1 >= 'A' && c1 <= 'Z' ) c1 += 'a' - 'A';
			if( c2 >= 'A' && c2 <= 'Z' ) c2 += 'a' - 'A';
			if( c1 != c2 ) return false;
			if( c1 == 0 ) return true;
		}
	}
}

//-------------------------------------------------------------------------------------------------
void StringToUpper( char *str ) {
	for( ; *str; str++ ) {
		if( *str >= 'a' && *str <= 'z' ) {
			*str += 'A' - 'a';
		}
	}
}

//-------------------------------------------------------------------------------------------------
void StringASCIIFilter( char *str ) {
	for( ; *str; str++ ) {
		if( *str >= 128 ) *str = '_' ;
	}
}

}
