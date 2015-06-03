#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Minecraft;

use Data::Dumper;
my $parser = new Minecraft::NBT::Parser();
my $data = $parser->parse_file( $ARGV[0] );
print Dumper( $data );
exit;

