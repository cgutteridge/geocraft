#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Minecraft;

use Data::Dumper;

my $mc = new Minecraft( "$FindBin::Bin/saves" );
my $world = $mc->world( "Test23" );

for( my $x=-50;$x<50;++$x ) {
	for( my $z=-50;$z<50;++$z ) {
		for( my$y=50;$y<70;++$y ) {
			$world->set_block($x,$y,$z, 1 );
		}
	}
}

$world->save;
exit;

