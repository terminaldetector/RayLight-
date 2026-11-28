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
	const char *const classes[] = {"abaddon_flight_bolt", "abaddon_flight_mine", "abaddon_mine_supply",
		"abaddon_energy_cloud", "abaddon_charge_station"};
	for ( int i = 0; i < ARRAYSIZE( classes ); ++i )
	{
		if ( !dictionary || !dictionary->FindFactory( classes[i] ) )
		{
			fprintf( stderr, "missing factory: %s\n", classes[i] );
			return 4;
		}
		printf( "PASS | %s registers %s\n", VSERVERTOOLS_INTERFACE_VERSION, classes[i] );
	}
	return 0;
}
