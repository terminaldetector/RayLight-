// Linux loader smoke. Use the same headers and 32-bit toolchain as server.so.
#include "cbase.h"
#include "toolframework/itoolentity.h"

#include <dlfcn.h>
#include <stdio.h>

int main( int argc, char **argv )
{
	if ( argc != 2 )
		return 64;
	void *module = dlopen( argv[1], RTLD_NOW | RTLD_LOCAL );
	if ( !module )
	{
		fprintf( stderr, "dlopen: %s\n", dlerror() );
		return 1;
	}
	CreateInterfaceFn get = reinterpret_cast<CreateInterfaceFn>( dlsym( module, "CreateInterface" ) );
	if ( !get )
		return 2;
	int status = -1;
	IServerTools *tools = static_cast<IServerTools *>( get( VSERVERTOOLS_INTERFACE_VERSION, &status ) );
	if ( !tools || status != 0 )
		return 3;
	IEntityFactoryDictionary *dictionary = tools->GetEntityFactoryDictionary();
	if ( !dictionary || !dictionary->FindFactory( "abaddon_flight_bolt" ) )
	{
		fprintf( stderr, "missing factory: abaddon_flight_bolt\n" );
		return 4;
	}
	printf( "PASS | %s registers abaddon_flight_bolt\n", VSERVERTOOLS_INTERFACE_VERSION );
	return 0;
}
