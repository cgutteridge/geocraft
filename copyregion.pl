#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Minecraft;

use Data::Dumper;
my $region = Minecraft::Region->from_file( $ARGV[0] );
for( my$z=-50;$z<50;++$z ) {
for( my$y=150;$y<200;++$y ) {
	$region->set_block(35,$y,$z,  int rand(100) );
}
}
$region->set_block( 35,170,12,  1 );
$region->to_file( $ARGV[1] );
exit;

