#!/usr/bin/env perl

use Data::Dumper;
use FindBin;
use lib "$FindBin::Bin/lib";
use Geo::Coordinates::OSGB qw(ll_to_grid grid_to_ll);
use Minecraft;
use Elevation;
use Minecraft::Projection;
use Minecraft::MapTiles;

use strict;
use warnings;

my $worldname = $ARGV[0];
if( -e "$FindBin::Bin/saves/$worldname" )
{
	die "World Already exists.";
}
`cp -a "$FindBin::Bin/saves/BedRock" "$FindBin::Bin/saves/$worldname"`;

my $mc = new Minecraft( "$FindBin::Bin/saves" );
my $world = $mc->world( $worldname );




####################################################
# actual options


my( $lat,$long,$grid);
my( $mc_x_offset,$mc_z_offset );
#( $lat,$long)=  ( 50.89578, -1.40625 ); #town quay
#( $lat,$long)=  ( 50.89945, -1.40555 );
($lat,$long) = ( 50.9249, -1.39629 ); #middle of soton
( $lat,$long)=  ( 50.93452, -1.397 ); #uni
( $lat,$long)=  ( 50.93974, -1.37171); #gark
($lat,$long)=  (50.91948, -1.39561 ); # middle of city 
( $lat,$long)=  ( 50.93531, -1.39871  ); #unidip
($lat,$long) = ( 50.59614, -1.2001  ); #ventnor library
($lat,$long) = ( 50.59635, -1.2008); #front of ventnor church
($lat,$long) = ( 50.59305, -1.2079 );#ventnor seafront
( $lat,$long)=  ( 50.89266, -1.40567  ); #town quay end
( $lat,$long)=  ( 50.90871, -1.40457); #arthouse

($lat,$long) = ( 50.59332, -1.20502 );#ventnor haven

( $lat,$long)=  ( 50.88999, -1.38677); # offset used for SotonLidar

( $lat,$long)=  ( 50.93452, -1.397 ); #uni

# corner of SUSU
( $lat,$long)=  ( 50.93502, -1.39806 );

# east corner of staff club
($lat,$long) = ( 50.93543, -1.39698 );

my $OPTS = {};

#ventnorfull
# <--------coast--------->: 
# W:-1500 E:200 S:500 N:0

$OPTS->{MC_BL} = [-200,-200];
$OPTS->{MC_TR} = [200,200];

$OPTS->{MAPTILES} = new Minecraft::MapTiles(
	zoom=>19,
	spread=>3,
	width=>256,
	height=>256,
	dir=>"$FindBin::Bin/tiles", 
	url=>"http://b.tile.openstreetmap.org/",
	default_block=>1,
);

$OPTS->{EXTEND_DOWNWARDS} = 9;

$OPTS->{DTM} = new Elevation( "/Users/cjg/Projects/LIDAR-DSM-1M-SU41/DTM" );
$OPTS->{DSM} = new Elevation( "/Users/cjg/Projects/LIDAR-DSM-1M-SU41/DSM" );

my $p = Minecraft::Projection->new_from_ll( $world, 0,0, $lat,$long, "OSGB36" );

$p->render( %$OPTS );



exit;
