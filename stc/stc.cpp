// stc.cpp : Defines the entry point for the console application.
//

#include "stdafx.h"

#define VERSION "3.0.0"

const char *startup_message = 
	"\n"
	" -----------------------------------------------\n"
	" ServerTools Console [Version " VERSION "]\n"
	" (c) 2014 mukunda\n"
	" -----------------------------------------------\n"
	"\n";

#define CONSOLE_NOTICE "///"
#define CONSOLE_ERROR "###"
#define CONSOLE_RESPONSE "<<<"
#define CONSOLE_PROMPT ">>>"

//-------------------------------------------------------------------------------------------------
boost::mutex console_lock;
int next_id=1;

using boost::asio::ip::tcp;

//-------------------------------------------------------------------------------------------------
struct PacketHeader {
	boost::int32_t size;
	boost::int32_t id;
	boost::int32_t type;
};

//-------------------------------------------------------------------------------------------------
class Packet {
	 
	PacketHeader header;
	std::string body;
public:
	
	enum PacketType {
		SERVERDATA_AUTH = 3,
		SERVERDATA_AUTH_RESPONSE = 2,
		SERVERDATA_EXECCOMMAND = 2,
		SERVERDATA_RESPONSE_VALUE = 0
	} ;

	Packet() {
	}
	 
	Packet( PacketType type, std::string data ) {
		header.id = next_id++;
		header.type = type;
		body = data;
	}

	boost::system::error_code Send( tcp::socket &socket ) {
		int len = body.length();
		header.size = len + 10;
		boost::uint8_t *data = new boost::uint8_t[ len + 14 ];
		int write = 0;
		memcpy( data, &header, sizeof PacketHeader );
		if( len != 0 ) memcpy( data+12, body.c_str(), len );
		data[12+len] = 0;
		data[13+len] = 0; 
		
		boost::system::error_code err;
		boost::asio::write( socket, boost::asio::buffer( data, len+14 ), 
			boost::asio::transfer_all(), err );
		delete[] data;
		if( err ) return err;
		  
		return boost::system::error_code();
	}

	boost::system::error_code Recv( tcp::socket &socket ) {
		boost::system::error_code err;
		
		int size;
		boost::asio::read( socket, boost::asio::buffer( &size, 4 ), boost::asio::transfer_all(), err );
		if( err ) return err;

		boost::uint8_t *data = new boost::uint8_t[size];
		boost::asio::read( socket, boost::asio::buffer( data, size ), boost::asio::transfer_all(), err );
		if( err ) {
			delete[] data;
			return err;
		}
		
		header.id = (data[0]) | (data[1]<<8) | (data[2]<<16) | (data[3]<<24);
		header.type = (data[4]) | (data[5]<<8) | (data[6]<<16) | (data[7]<<24);
		body = (char*)(data+8);
		delete[] data;

		return boost::system::error_code();
	}

	int GetID() const {
		return header.id;
	}

	PacketType GetType() const {
		return (PacketType)header.type;
	}

	std::string &GetData() {
		return body;
	}

	int Set( PacketType type, const char *data ) {
		header.id = next_id++;
		header.type = type;
		body = data;
		return header.id;
	}
};

FILE *OpenLog() {
	return fopen( "console.log", "a" );
}

//-------------------------------------------------------------------------------------------------
void EchoEx( const char *format, ... ) {
	boost::lock_guard<boost::mutex> lock(console_lock);
	va_list arguments; 
	va_start( arguments, format );
	vprintf( format, arguments );

	FILE *f = OpenLog();
	vfprintf( f, format, arguments );
	fclose(f);
}

//-------------------------------------------------------------------------------------------------
void Echo( const char *format, ... ) {
	boost::lock_guard<boost::mutex> lock(console_lock);
	va_list arguments; 
	va_start( arguments, format );
	printf( CONSOLE_RESPONSE " " );
	vprintf( format, arguments );
	fputc( '\n', stdout );

	FILE *f = OpenLog();
	fprintf( f, CONSOLE_RESPONSE " " );
	vfprintf( f, format, arguments );
	fputc( '\n', f );
	fclose(f);
}

//-------------------------------------------------------------------------------------------------
void EchoError(  const char *format, ... ) {
	boost::lock_guard<boost::mutex> lock(console_lock);
	va_list arguments; 
	va_start( arguments, format );
	printf( CONSOLE_ERROR " " );
	vprintf( format, arguments );
	fputc( '\n', stdout );

	FILE *f = OpenLog();
	fprintf( f,CONSOLE_ERROR " " );
	vfprintf( f,format, arguments );
	fputc( '\n', f );
	fclose(f);
}

//-------------------------------------------------------------------------------------------------
void EchoNotice(  const char *format, ... ) {
	boost::lock_guard<boost::mutex> lock(console_lock);
	va_list arguments; 
	va_start( arguments, format );
	printf( CONSOLE_NOTICE " " );
	vprintf( format, arguments );
	fputc( '\n', stdout );

	FILE *f = OpenLog();
	fprintf( f,CONSOLE_NOTICE " " );
	vfprintf( f,format, arguments );
	fputc( '\n', f );
	fclose(f);
}

//-------------------------------------------------------------------------------------------------

boost::asio::io_service io_service;

void configureSocketTimeouts(boost::asio::ip::tcp::socket& socket)
{
#if defined _WIN32
    int32_t timeout = 10000;
    setsockopt(socket.native(), SOL_SOCKET, SO_RCVTIMEO, (const char*)&timeout, sizeof(timeout));
    setsockopt(socket.native(), SOL_SOCKET, SO_SNDTIMEO, (const char*)&timeout, sizeof(timeout));
#else
    struct timeval tv;
    tv.tv_sec  = 10; 
    tv.tv_usec = 0;         
    setsockopt(socket.native(), SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(socket.native(), SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
#endif
}

//-------------------------------------------------------------------------------------------------
class CommandParams {
	std::vector<std::string> params;
	std::string arg_string;

public:
	CommandParams() {}

	void Parse( std::string &command ) {
		Parse( command.c_str() );
	}

	void Parse( const char *command ) {
		char command2[512];
		Util::CopyString( command2, sizeof command2, command );
		char arg[512];
		Util::ScanArgString( command2, arg, sizeof arg );
		arg_string = command2;
		Util::CopyString( command2, sizeof command2, command );
		
		do {
			Util::ScanArgString( command2, arg, sizeof arg );
			if( Util::StrEmpty( arg ) ) break;
			if( arg[0] == '/' && arg[1] == '/' ) break;
			params.push_back(arg);
		} while(true);
	}
	CommandParams( const char *command ) {
		Parse(command);
	}

	size_t Count() const {
		return params.size();
	}

	bool IsEmpty() const {
		return params.size() == 0;
	}

	std::string GetString( size_t index ) const {
		if( index >= Count() ) return "";
		return params[index];
	}

	std::string GetAllArgs() const {
		std::string result;
		for( size_t i = 1; i < params.size(); i++ ) {
			result += params[i] + " ";
		}
		boost::algorithm::trim( result );
		return result;
	}
	
	std::string GetArgString() const {
		return arg_string;
	}
	  
	int GetInt( size_t index, int def=0 ) const {
		if( index >= Count() ) return def;
		return Util::StringToInt( params[index].c_str() );
	}

	std::string operator[] (size_t n) const {
		return GetString( n );
	}
	 
};

//-------------------------------------------------------------------------------------------------
class Server {

private:
	 
	std::string address;
	std::string password;

	std::string id;
	std::string groups;
	CommandParams parsed_groups;
	bool refresh_info;
	
	bool hibernates;
	bool connected;
	
	volatile bool is_busy;
	bool fault;
	  
	std::string rcon_command;
	std::string rcon_result;
	bool rcon_has_operation;
	int last_operation_id;

	tcp::socket socket;

	boost::mutex busy;
	boost::condition_variable waiter;

	//-----------------------------------------------------------------------------------------------
	boost::system::error_code ExecCommand() {
		boost::system::error_code err;
		int end_id;

		// send packet to execute command
		Packet packet( Packet::SERVERDATA_EXECCOMMAND, rcon_command );
		err = packet.Send( socket );
		if( err ) {
			connected = false;
			return err;
		}
		
		// this packet is used as a terminator signal
		// we break the loop when we find an end_id match
		//
		// we do this to detect split packet responses
		//
		end_id = packet.Set( Packet::SERVERDATA_RESPONSE_VALUE, "" );
		err = packet.Send(socket);
		if( err ) {
			connected = false;
			return err;
		}

		rcon_result = "";
		do {
			err = packet.Recv( socket );
			if( err ) {
				connected = false;
				return err;
			}
			if( packet.GetID() != end_id ) {
				rcon_result += packet.GetData();
			} else {
				break;
			}
		} while( true );

		// the host responds with two packets with the SERVERDATA_RESPONSE_VALUE trick
		// read this extra one and discard it
		err = packet.Recv( socket );
		if( err ) {
			connected = false;
			return err;
		}
		
		int operation_id = 0;
		if( rcon_has_operation ) {
			// scan for operation ID
			
			// get input ...
			std::istringstream stream( rcon_result );
			std::string line;
			while( std::getline(stream, line) ) {
				if( strncmp( line.c_str(), "[ST] OPCREATE:", 14 ) == 0 ) {
					// found operation ID
					line = line.substr( 14 );
					operation_id = std::stoi( line );
					break;	
				}
			}
			if( operation_id != 0 ) {

				// poll operation status.
				last_operation_id = operation_id;
			}

		}
		
		// print to client
		Echo( "[%s] %s", id.c_str(), rcon_result.c_str() );

		if(operation_id) {
			WaitForOp( operation_id );
		}
		return boost::system::error_code();
	}
	
	
	//-----------------------------------------------------------------------------------------------
	void Connect() {
		connected=false;
		 
		std::string real_address;
		std::string port = "27015";
		{
			int portstart = address.find_first_of( ':' );
			if( portstart != std::string::npos ) {
				port = address.substr( portstart+1 );
				address = address.substr( 0, portstart );
			}
		}
		tcp::resolver::query query( address, port );
		tcp::resolver resolver(io_service);
		tcp::resolver::iterator endpoint_iterator = resolver.resolve( query );
		tcp::resolver::iterator end;
		boost::system::error_code error = boost::asio::error::host_not_found;
		while( error && endpoint_iterator != end ) {
			socket.close();
			socket.connect( *endpoint_iterator++, error ); 
		}
		if( error ) {
			EchoError( "ERROR@%s: %s", address.c_str(), error.message().c_str() );  
			return;
		} 
		configureSocketTimeouts( socket );

		Packet packet( Packet::SERVERDATA_AUTH, password );
		boost::system::error_code err = packet.Send( socket );
		if( err ) { 
			EchoError( "ERROR@%s: %s/%s", address.c_str(), "FAILED TO AUTHENTICATE", err.message().c_str() );  
			return;
		}
		err = packet.Recv( socket );
		if( err ) {
			EchoError( "ERROR@%s: %s/%s", address.c_str(), "FAILED TO AUTHENTICATE", err.message().c_str() );  
			return;
		}
		err = packet.Recv( socket );
		if( err ) {
			EchoError( "ERROR@%s: %s/%s", address.c_str(), "FAILED TO AUTHENTICATE", err.message().c_str() );  
			return;
		}
		if( packet.GetID() == -1 ) {
			EchoError( "ERROR@%s: %s", address.c_str(), "INVALID RCON PASSWORD (CAUTION!)" );
			password = "";
			return;
		}


		if( refresh_info ) {

			// retrieve ID info from the server
			//
			packet.Set( Packet::SERVERDATA_EXECCOMMAND, "st_id" );
			err = packet.Send( socket );
			if( err ) {
				EchoError( "ERROR@%s: %s", address.c_str(), "Network Failure (send)" );
				return;
			}
			err = packet.Recv( socket );
			if( err ) {
				EchoError( "ERROR@%s: %s", address.c_str(), "Network Failure (recv)" );
				return;
			}
			
			// parse data
			std::string &data = packet.GetData();
			if( data.find( "Unknown command") != std::string::npos ) {
				EchoError( "ERROR@%s: %s", address.c_str(), "ServerTools is not installed." );
				return;
			}
			
			int start = data.find( "[ST] id = \"" );
			if( start != std::string::npos) {
				start += 11;
				int end = data.find( '"', start+1 );
				id = data.substr( start, end-start );
			} else {
				
				EchoError( "ERROR@%s: %s", address.c_str(), "ServerTools is not installed." );
				return;
			}
			
			start = data.find( "[ST] groups = \"" );
			if( start != std::string::npos ) {
				
				start += 15;
				int end = data.find( '"', start+1 );
				groups = data.substr( start, end-start );
				parsed_groups.Parse( groups );
			}

			EchoNotice( "Added Server: %s, ID=\"%s\", GROUPS=\"%s\"", address.c_str(), id.c_str(), groups.c_str() );

			refresh_info = false;
			// register server
		} 
		connected = true; 
	}

	bool SendPacket( Packet &p ) {
		boost::system::error_code err;
		err = p.Send( socket );
		if( err ) {
			if( err = boost::asio::error::eof ) {
				Connect();
				if( connected ) {
					err = ExecCommand();
					if( err ) {
						EchoError( "ERROR@%s: Couldn't execute command ::: err=%s", id.c_str(), err.message()  );
						return false;
					}
				} else {
					EchoError( "ERROR@%s: Couldn't connect to server.", id.c_str()  );
					return false;
				}

			} else {
				
				EchoError( "ERROR@%s: %s", id.c_str(), err.message().c_str() );
				return false;
			}
		}
		return true;
	}

	bool GetPacket( Packet &p ) {
		boost::system::error_code err;
		err = p.Recv( socket );
		if( err ) {
			EchoError( "ERROR@%s: Network Error / %s", id.c_str(), err.message().c_str() );
			connected = false;
			return false;
		}
		return true;
	}
	 
public:	
	bool selected;
	//-----------------------------------------------------------------------------------------------
	Server( std::string &p_addr, std::string &p_password ): socket(io_service) {
		configureSocketTimeouts( socket );
		address = p_addr;
		password = p_password;
		boost::algorithm::trim( address );
		boost::algorithm::trim( password ); 

		selected = false;
		connected = false;
		hibernates = false;
		is_busy = true;  

		refresh_info = true;
		boost::thread t( boost::bind( &Server::ConnectThread, this ) );
	}
	
	//-----------------------------------------------------------------------------------------------
	void ConnectThread() {
		boost::lock_guard<boost::mutex> lock(busy);
		Connect();
		is_busy = false;
		waiter.notify_all();
	}

	//-----------------------------------------------------------------------------------------------
	void CommandThread() {
		boost::lock_guard<boost::mutex> lock(busy);

		is_busy = true;
		if( !connected ) {
			Connect();
		}

		if( connected ) {
			boost::system::error_code err = ExecCommand();
			if( err ) {
				Connect();
				if( connected ) {
					boost::system::error_code err = ExecCommand();
				} else {
					EchoError( "ERROR@%s: %d/%s", id.c_str(), err.value(), err.message().c_str() );
				}
				/*
				if( err == boost::asio::error::eof ) {
					Connect();
					if( connected ) {
						boost::system::error_code err = ExecCommand();
					}
				} else {
					EchoError( "ERROR@%s: %d/%s", id.c_str(), err.value(), err.message().c_str() );
				}*/
			}
		}

		is_busy = false;
		waiter.notify_all();

	}
	//-----------------------------------------------------------------------------------------------
	void WaitForOp( int operation_id ) {
		//boost::lock_guard<boost::mutex> lock(busy);
		//is_busy = true;

		int retries=30;
		
		std::string poll_packet = "st_status " + std::to_string(operation_id);

		for( ;; ) {
			
			if( !SendPacket( Packet( Packet::SERVERDATA_EXECCOMMAND, poll_packet.c_str() ) ) ) break;
			Packet p;
			if( !GetPacket(p) ) break;
			
			std::string response_code = p.GetData().substr(0,14);
			if( response_code == "[ST] STATUS: N" ) {
				// NOTFOUND status, server is not busy.
				break;
			} else if( response_code == "[ST] STATUS: B" ) {
				// BUSY status, sleep and retry
				retries--;
				if( !retries ) {
					EchoError( "ERROR@%s: %s", id.c_str(), "Server is stuck in operation for more than 30 seconds!" );
					break;
				}
				boost::this_thread::sleep_for( boost::chrono::seconds(1) );
				continue;
			} else if( response_code == "[ST] STATUS: C" ) {
				// COMPLETE status, print server response

				// skip first line
				std::string response = p.GetData();
				int start = response.find_first_of( '\n' );
				start++;
				response = response.substr(start);
				Echo( "[%s] %s", id.c_str(), response.c_str() );
				break;
			} else {
				// unknown response
				EchoError( "ERROR@%s: %s", id.c_str(), "Server responded with unknown or empty status" );
				break;
			}
			
		}
		//is_busy = false;
		//waiter.notify_all();
		  
	}

	/*
	//-----------------------------------------------------------------------------------------------
	void OnConnect( const boost::system::error_code &err, tcp::resolver::iterator endpoint_iterator ) {
		if( !err ) {
			connected = true;
			// authenticate



			is_busy = false;
		} else if( endpoint_iterator != tcp::resolver::iterator() ) {
			socket.close();
			tcp::endpoint endpoint = *endpoint_iterator;
			socket.async_connect( endpoint, 
				boost::bind( &Server::OnConnect, this, boost::asio::placeholders::error, ++endpoint_iterator ) );

			
		} else {
			EchoError( "ERROR@%s: %s", address, err.message().c_str() );
			is_busy = false;
		}
		
	}*/
	
	//-----------------------------------------------------------------------------------------------
	void RunCommand( const char *command, bool has_operation ) {
		boost::lock_guard<boost::mutex> lock(busy);
		if( refresh_info ) {
			EchoError( "ERROR@%s: %s", address, "NETWORK FAILURE" );
			return;
		}
		if( is_busy ) {
			EchoError( "ERROR@%s: %s", address, "COMMAND IN PROGRESS" );
			return;
		}
		is_busy = true;
		rcon_command = command;
		rcon_has_operation = has_operation;
		
		boost::thread t( boost::bind( &Server::CommandThread, this ) );
	}
	/*
	//-----------------------------------------------------------------------------------------------
	void WaitOperationComplete() {
		if( last_operation_id == 0 ) return;

		boost::lock_guard<boost::mutex> lock(busy);
		if( refresh_info ) {
			EchoError( "ERROR@%s: %s", address, "NETWORK FAILURE" );
			return;
		}
		if( is_busy ) {
			EchoError( "ERROR@%s: %s", address, "COMMAND IN PROGRESS" );
			return;
		}
		is_busy = true;
		boost::thread t( boost::bind( &Server::WaitOpThread, this ) );
	}*/
	
	//-----------------------------------------------------------------------------------------------
	void WaitComplete() {
		boost::unique_lock<boost::mutex> lock(busy);
		while( is_busy ) {
			waiter.wait( lock );
		}
	}


	std::string GetID() const {
		return id;
	}

	std::string GetGroups() const {
		return groups;
	}

	bool InGroup( std::string group ) const {
		if( id == "" ) return false;
		if( group == id ) return true;
		if( group == "all" ) return true;
		for( size_t i = 0; i < parsed_groups.Count(); i++ ){
			if( group == (parsed_groups[i]) ) return true;
		}
		return false;
	}

	bool IsTarget( CommandParams parsed_target ) const {
		if( id == "" ) return false;
		bool is_target = false;
		for( size_t i = 0; i < parsed_target.Count(); i++ ) {
			std::string arg = parsed_target[i];
			bool negate = false;
			if( arg[0] == '-' ) {
				negate = true;
				arg = arg.substr(1);
				
			} else if( arg[0] == '+' ) {
				if( !is_target ) continue;
				arg = arg.substr(1);
				if( !InGroup( arg ) ) is_target = false;
				continue;
			}
		
			if( negate ) {
		
				if( InGroup( arg ) ) is_target = false;
			} else {
				if( InGroup( arg ) ) is_target = true;
			}
		}
		return is_target;
	}
};

std::vector<Server*> servers;
bool update_server_listing = false;

typedef void (*ConCmdCallback)( CommandParams &params );

class ConsoleCommand;
std::vector<ConsoleCommand*> command_list;

bool running;

//-------------------------------------------------------------------------------------------------
class ConsoleCommand {
	
	char cmd_name[64];
	ConCmdCallback cmd_func;
	std::string usage;

public:
	ConsoleCommand( const char *name, ConCmdCallback function, const std::string &p_usage ) {
		Util::CopyString( cmd_name, name );
		cmd_func = function;
		usage = p_usage;
		command_list.push_back(this);
		
	}

	~ConsoleCommand() {
		for( std::vector<ConsoleCommand*>::iterator it = command_list.begin(); it != command_list.end(); ++it ) {
			if( (*it) == this ) {
				command_list.erase(it);
				return;
			}
		}
	}

	void Execute( CommandParams &p ) {
		(*cmd_func)( p );
	}

	bool Match( const char *name ) {
		return Util::StrEqual( name, cmd_name );
	}

	bool Match( std::string &name ) {
		return( name == cmd_name );
	}

	const std::string &GetUsage() const {
		return usage;
	}
	
	std::string GetName() const {
		return cmd_name;
	}
};

//-------------------------------------------------------------------------------------------------
void WaitCompleteAll() {
	for( std::vector<Server*>::iterator it = servers.begin(); it != servers.end(); ++it ) {
		(*it)->WaitComplete();
	}
}


//-------------------------------------------------------------------------------------------------
int RunCommandOnServers( std::string command, bool has_operation ) {
	int count = 0;
	for( size_t i = 0; i < servers.size(); i++ ) {
		if( servers[i]->selected ) {
			count++;
			servers[i]->RunCommand( command.c_str(), has_operation ); 
		}
	}
	
	if( count == 0 ) { Echo( "No servers selected!" ); }
	return count;
}
/*
int WaitForOperation() {
	int count = 0;
	for( size_t i = 0; i < servers.size(); i++ ) {
		if( servers[i]->selected ) {
			count++;
			servers[i]->WaitOperationComplete();
		}
	}
	return count;
}*/

//-------------------------------------------------------------------------------------------------
void ExecuteCommand( const char *command ) {
	CommandParams params( command );
	if( params.IsEmpty() ) return;

	std::string name;
	name = params.GetString( 0 ); 

	bool found=false;

	for( size_t i = 0; i < command_list.size(); i++ ) {
		if( command_list[i]->Match( name ) ) {
			command_list[i]->Execute( params );
			found=true;
		}
	}

	if( !found ) {
		EchoError( "Unknown command: %s", name.c_str() );
	}
}

//-------------------------------------------------------------------------------------------------
void Command_ExecuteScript( CommandParams &params ) {
	if( params.Count() < 2 ) {
		/// error
		return;
	}

	std::string file;
	file = params.GetString( 1 );
	
	int pos = file.find_last_of( '.' );
	if( pos == std::string::npos ) {
		file += ".cfg";
	}
	FileReader f( file.c_str() );

	EchoNotice( "Executing script: %s", file.c_str() );

	char line[1024];
	while( f.ReadLine( line ) ) {
		Util::TrimString( line );
		ExecuteCommand(line);
	}
}

//-------------------------------------------------------------------------------------------------
void Command_Test( CommandParams &params ) {
	Echo( "Hi." );
}

//-------------------------------------------------------------------------------------------------
void Command_Quit( CommandParams &params ) {
	running=false;
}

//-------------------------------------------------------------------------------------------------
void Command_AddServer( CommandParams &params ) {
	if( params.Count() < 3 ) {
		Echo( "Usage: addserver <address> <password>" );
		return;
	}

	std::string addr,password;

	addr = params.GetString( 1 );
	password = params.GetString( 2 );

	Server *serv = new Server( addr, password );
	servers.push_back( serv ); 
	update_server_listing = true;
}

void PrintSelection() {
	EchoEx( CONSOLE_RESPONSE " Selection: " );
	int count=0;
	int mod=0;
	for( size_t i = 0; i < servers.size(); i++ ) {
		if( servers[i]->selected ) {
			if( mod == 5 ) {
				mod = 0;
				EchoEx( "\n<<<            " );
			}
			EchoEx( " %10s", servers[i]->GetID().c_str() );
			count++;
			mod++;
		}
	}
	if( count == 0 ) {
		EchoEx( " <none>" );
	}
	EchoEx( "\n" );
}

//-------------------------------------------------------------------------------------------------
void Command_Select( CommandParams &params ) {
	// todo; copy istarget from plugin.
	if( params.Count() >= 2 ) {
		std::string target;
		target = params.GetAllArgs();
		boost::algorithm::replace_all( target, "-", " -" );
		boost::algorithm::replace_all( target, "+", " +" );
		CommandParams targets( target.c_str() );

		for( size_t i = 0; i < servers.size(); i++ ) {
			servers[i]->selected = servers[i]->IsTarget( targets ) ;
		}
	}

	PrintSelection();
}

//-------------------------------------------------------------------------------------------------
void Command_SelectMore( CommandParams &params ) {
	if( params.Count() < 2 ) {
		Echo( "asel <target> - Add to selection" );
		return;
	}

	std::string target;
	target = params.GetAllArgs();
	boost::algorithm::replace_all( target, "-", " -" );
	boost::algorithm::replace_all( target, "+", " +" );
	CommandParams targets( target.c_str() );

	for( size_t i = 0; i < servers.size(); i++ ) {
		if( servers[i]->IsTarget( targets ) ) {
			servers[i]->selected = true;
		}	
	}

	PrintSelection();
}

//-------------------------------------------------------------------------------------------------
void Command_Deselect( CommandParams &params ) {
	if( params.Count() < 2 ) {
		Echo( "dsel <target> - Deselect target" );
		return;
	}

	std::string target;
	target = params.GetAllArgs();
	boost::algorithm::replace_all( target, "-", " -" );
	boost::algorithm::replace_all( target, "+", " +" );
	CommandParams targets( target.c_str() );

	for( size_t i = 0; i < servers.size(); i++ ) {
		if( servers[i]->IsTarget( targets ) ) {
			servers[i]->selected = false;
		}
	}
	PrintSelection();
}


//-------------------------------------------------------------------------------------------------
void Command_Run( CommandParams &params ) {
	if( params.Count() < 2 ) {
		Echo( "r <command> - Execute an rcon command on selected servers." );
		return;
	}
	
	RunCommandOnServers(  params.GetArgString(), false );
}

//-------------------------------------------------------------------------------------------------
void Command_List( CommandParams &params ) {
	
	Echo( "Server List: " );
	for( size_t i = 0; i < servers.size(); i++ ) {
		Echo( "  ID: \"%s\" | Groups: \"%s\"", servers[i]->GetID().c_str(), servers[i]->GetGroups().c_str() );
	}
}

void Command_Echo( CommandParams &params ) {
	EchoNotice( "%s", params.GetArgString().c_str() );
}

void Command_Fuck( CommandParams &params ) {
	Echo( "%s", "My, what a filthy mind you have!" );
}

void Command_Help( CommandParams &params ) {
	Echo( "Command Listing:" );
	for( size_t i = 0; i < command_list.size(); i++ ) {
		if( command_list[i]->GetUsage()  != "" ) {
			Echo( "  %-8s %s", command_list[i]->GetName().c_str(), command_list[i]->GetUsage().c_str() );
		}
	}
}
/*
//-------------------------------------------------------------------------------------------------
void Command_New( CommandParams &params ) {
	if( params.Count() < 2 ) {
		Echo( "new <filename> - Creates an empty file." );
		return;
	}
	RunCommandOnServers( "st_new "  + params.GetArgString() );
}

//-------------------------------------------------------------------------------------------------
void Command_Delete( CommandParams &params ) {
	if( params.Count() < 2 ) {
		Echo( "delete <filename> - Deletes a file." );
		return;
	}
	RunCommandOnServers( "st_delete "  + params.GetArgString() );
}

//-------------------------------------------------------------------------------------------------
void Command_Copy( CommandParams &params ) {
	if( params.Count() < 3 ) {
		Echo( "copy [-rm] <source> <dest> - Copy file(s)" );
		return;
	}
	RunCommandOnServers( "st_copy " + params.GetArgString() );

	WaitCompleteAll();
	WaitForOperation();
}

//-------------------------------------------------------------------------------------------------
void Command_Rename( CommandParams &params ) {
	if( params.Count() < 3 ) {
		Echo( "rename <file> <newfile> - Rename a file" );
		return;
	}
	RunCommandOnServers( "st_rename "  + params.GetArgString() );
}

void Command_MakeDirectory( CommandParams &params ) {
	if( params.Count() < 2 ) {
		Echo( "mkdir <path> - Create a directory" );
		return;
	}
	RunCommandOnServers( "st_mkdir "  + params.GetArgString() );
}

void Command_Edit( CommandParams &params ) {
	if( params.Count() < 4 ) {
		Echo ("edit [-i] <file> <line> <text> - Edit a text file" );
		return;
	}
	RunCommandOnServers( "st_edit " + params.GetArgString() );
}

void Command_CfgFind( CommandParams &params ) {
	if( params.Count() < 2 ) {
		Echo( "cfgfind [-pa] <term> - Search config file" );
		return;
	}
	RunCommandOnServers( "st_cfgfind " + params.GetArgString() );
}

void Command_CfgEdit( CommandParams &params ) {
	if( params.Count() < 3 ) {
		Echo( "cfgedit [-ar] <file> <command> - Edit config file" );
		return;
	}
	RunCommandOnServers( "st_cfgedit " + params.GetArgString() );
}

void Command_View( CommandParams &params ) {
	if( params.Count() < 2 ) {
		Echo( "view -xxx <filename> - View a file" );
		return;
	}
	RunCommandOnServers( "st_view " + params.GetArgString() );

}

void Command_Dir( CommandParams &params ) {
	if( params.Count() < 2 ) {
		Echo( "dir <path>" );
		return;
	}
	RunCommandOnServers( "st_dir " + params.GetArgString() );

}


void Command_Sync( CommandParams &params ) {
	RunCommandOnServers( "st_sync" );
	WaitCompleteAll();
	WaitForOperation();
	
}*/
void Command_Get( CommandParams &params ) {
	RunCommandOnServers( "st_get " + params.GetArgString(), true );
}

void Command_Remove( CommandParams &params ) {
	RunCommandOnServers( "st_remove " + params.GetArgString(), true );
	
}

void Command_Sync( CommandParams &params ) {
	RunCommandOnServers( "st_sync " + params.GetArgString(), true );
		
}



//-------------------------------------------------------------------------------------------------
template <size_t maxlen> void GetInputEx( char (&dest)[maxlen], const char *prompt ) {
	EchoEx( "%s", prompt );
	//printf( "%s", prompt );
	fgets( dest, maxlen, stdin );

	FILE *f = OpenLog();
	fprintf( f, "%s", dest );
	fclose(f);

}

//-------------------------------------------------------------------------------------------------
template <size_t maxlen> void GetInput( char (&dest)[maxlen] ) {
	GetInputEx( dest, CONSOLE_PROMPT " " );
}

void UpdateServerListing() {
	if( !update_server_listing ) return;
	update_server_listing = false;

	for( size_t i = 0; i < servers.size(); i++ ) {
		Server *s = servers[i]; 
		if( s->GetID() == "" ) {
			servers.erase( servers.begin() +i );
			delete s;
			i--;
		}
	}
}

//-------------------------------------------------------------------------------------------------
int _tmain( int argc, _TCHAR* argv[] ) {
	
	{
		time_t timer;
		time(&timer);
		struct tm * timeinfo = localtime (&timer);
		FILE *f = OpenLog();
		char thetime[128];
		strftime( thetime, sizeof thetime, "%x %X", timeinfo );
		fprintf( f,
			"\n" 
			"*****************************************************************\n"
			"Session start: %s\n"
			"*****************************************************************\n"
			, thetime );
		fclose(f);
	}

	EchoEx( startup_message );
	new ConsoleCommand( "addserv", Command_AddServer, "Adds a server address for servicing" );
	new ConsoleCommand( "sel", Command_Select, "Set server selection" );
	new ConsoleCommand( "asel", Command_SelectMore, "Adds target to selection" );
	new ConsoleCommand( "dsel", Command_Deselect, "Removes target from selection" );
	new ConsoleCommand( "list", Command_List, "Lists servers" );
	new ConsoleCommand( "r", Command_Run, "Run command on selected servers" );
	new ConsoleCommand( "rcon", Command_Run, "Run command on selected servers" );

	//new ConsoleCommand( "new", Command_New, "Create new file" );
	//new ConsoleCommand( "delete", Command_Delete, "Delete a file" );
	
	//new ConsoleCommand( "dir", Command_Dir, "View directory contents" );
	//new ConsoleCommand( "copy", Command_Copy, "Copy file(s)" );
	//new ConsoleCommand( "rename", Command_Rename, "Rename file" );
	//new ConsoleCommand( "mkdir", Command_MakeDirectory, "Create directory" );
	//new ConsoleCommand( "edit", Command_Edit, "Edit file" );
	//new ConsoleCommand( "cfgfind", Command_CfgFind, "Search config files" );
	//new ConsoleCommand( "cfgedit", Command_CfgEdit, "Edit configuration file" );
	//new ConsoleCommand( "view", Command_View, "View file contents" );
	//new ConsoleCommand( "sync", Command_Sync, "Force sync" );

	new ConsoleCommand( "sync", Command_Sync, "Perform ServerTools Sync" );
	new ConsoleCommand( "get", Command_Get, "Perform ServerTools Get" );
	new ConsoleCommand( "remove", Command_Remove, "Perform ServerTools Remove" );

	new ConsoleCommand( "exec", Command_ExecuteScript, "Executes a script (for this console, not remotely)" );
	new ConsoleCommand( "quit", Command_Quit, "" );
	new ConsoleCommand( "exit", Command_Quit, "Ends session" );
	
	
	new ConsoleCommand( "echo", Command_Echo, "Echo to console" );
	
	new ConsoleCommand( "help", Command_Help, ""); 

	
	new ConsoleCommand( "fuck", Command_Fuck, "" );
	new ConsoleCommand( "test", Command_Test, "" );
	new ConsoleCommand( "hi", Command_Test, "" );

	running = true;
	ExecuteCommand( "exec autoexec" );
	WaitCompleteAll();
	UpdateServerListing();
	 
	while( running ) {
		char command[1024];
		GetInput( command );
		ExecuteCommand( command );
		WaitCompleteAll();

		UpdateServerListing();
	}
	 
	return 0;
}

