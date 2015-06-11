#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Minecraft;

use Data::Dumper;

if( @ARGV != 3 )
{
	print "$0 <world> <region_x> <region_z>\n";
	exit 1;
}

my $mc = new Minecraft( "$FindBin::Bin/saves" );
my $world = $mc->world( $ARGV[0] );
$world->init_region( $ARGV[1], $ARGV[2] );
$world->save;
exit;

