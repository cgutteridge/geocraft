#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Minecraft;

use Data::Dumper;
my $data = Minecraft::Region->from_file( $ARGV[0] );
print Dumper( $data );
exit;

