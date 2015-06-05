#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Minecraft;

use Data::Dumper;

my $mc = new Minecraft( "$FindBin::Bin/saves" );
my $world = $mc->world( "Test23" );

$world->set_block(-5,100,5,  1 );

$world->save;
exit;

