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
( $lat,$long)=  ( 50.93452, -1.397 ); #uni
( $lat,$long)=  ( 50.90871, -1.40457); #arthouse

( $lat,$long)=  ( 50.88999, -1.38677); # offset used for SotonLidar
#($lat,$long) = (  43.65909, -79.31193  ); $grid="MERC"; #toronto
#($lat,$long) = (  43.66031, -79.30658  ); $grid="MERC"; #torontobeach
#($lat,$long) = ( 43.6529,-79.3045 ); $grid= "MERC"; # toronto se

($lat,$long) = ( 50.59332, -1.20502 );#ventnor haven

my $OPTS = {};

#ventnorfull
# <--------coast--------->: 
# W:-1500 E:200 S:500 N:0

$OPTS->{MC_BL} = [-512*3,-1024]; 
$OPTS->{MC_TR} = [512*3,-256]; 


$OPTS->{MAPTILES} = new Minecraft::MapTiles(
	zoom=>19,
	spread=>3,
	width=>256,
	height=>256,
	dir=>"$FindBin::Bin/tiles", 
	url=>"http://b.tile.openstreetmap.org/",
	default_block=>1,
);
#$OPTS->{ELEVATION} = new Elevation( "$FindBin::Bin/HeightData", [101,-62] );
#$OPTS->{EXTRUDE}->{45} = [ 45,95.15,45,45,95.15,45,45,95.15,45, 44.0 ];
#$OPTS->{EXTRUDE}->{98} = [ 98,95.15,98,98,95.15,98,98,95.15,98, 44.0 ];
#$OPTS->{EXTEND_DOWNWARDS} = 12;

#$OPTS->{ELEVATION} = new Elevation( "$FindBin::Bin/HeightData", [90,-80] );
#$OPTS->{EXTRUDE}->{45} = [ 45,95.15,45,45,95.15,45,45,95.15,45, 44.0 ];
#$OPTS->{EXTRUDE}->{98} = [ 98,95.15,98,98,95.15,98,98,95.15,98, 44.0 ];

#$OPTS->{ELEVATION} = new Elevation( "$FindBin::Bin/ventnor-lidar",[101,-68] );


#$OPTS->{ELEVATION} = new Elevation( "$FindBin::Bin/soton-lidar",[101,-62] );
#$OPTS->{EXTRUDE}->{45} = [44.0];
#$OPTS->{EXTEND_DOWNWARDS} = 12;



$OPTS->{ELEVATION} = new Elevation( "$FindBin::Bin/ventnor-lidar",[101,-68] );
$OPTS->{EXTRUDE}->{45} = [44.0];
$OPTS->{EXTEND_DOWNWARDS} = 9;



my $mc = new Minecraft( "$FindBin::Bin/saves" );
my $world = $mc->world( $ARGV[0] );
my $p = Minecraft::Projection->new_from_ll( $world, 0,0, $lat,$long, $grid );
$p->render( %$OPTS );

exit;
