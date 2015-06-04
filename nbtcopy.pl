#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Minecraft;

use Data::Dumper;
my $data = Minecraft::NBT->from_file( $ARGV[0] );
print Dumper( $data );
$data->to_file( $ARGV[1] );
exit;

