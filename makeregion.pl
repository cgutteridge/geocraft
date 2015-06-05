#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Minecraft;

use Data::Dumper;

my $mc = new Minecraft( "$FindBin::Bin/saves" );
my $world = $mc->world( "Test23" );
$world->init_region(0,0);

$world->save;
exit;

