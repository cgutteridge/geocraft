#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Minecraft;
use Math::Trig;
use Geo::Coordinates::OSGB qw(ll_to_grid grid_to_ll);
use Image::Magick;

my $tiles_dir= "$FindBin::Bin/tiles";

my $mc = new Minecraft( "$FindBin::Bin/saves" );
my $world = $mc->world( "Test23" );
$world->init_region(0,0);

my $mc_x_offset = 0;
my $mc_y = 10;
my $mc_z_offset = 0;
my $width = 50;
my $height = 50;
my $easting_offset = 442544;
my $northing_offset = 115392;
my $zoom  =17;

my $tiles = {};

for( my $x=0; $x<$width; ++$x ) {
	for( my $y=0; $y<$height; ++$y ) {
		my $e = $easting_offset+$x;
		my $n = $northing_offset+$y;
		my $mc_x = $mc_x_offset + $x;
		my $mc_z = $mc_z_offset + $y;
		my( $lat, $long ) = grid_to_ll($e,$n);
		my( $xtile,$ytile, $xr,$yr ) = getTileNumber( $lat,$long, $zoom );
		my $tile = "${zoom}_${xtile}_${ytile}.png";
		if( !defined $tiles->{$tile} )
		{
			if( !-e "$tiles_dir/$tile" )
			{
				`curl 'http://b.tile.openstreetmap.org/$zoom/$xtile/$ytile.png' > $tiles_dir/$tile`;
			}
			my $p = new Image::Magick;
			$p->Read( "$tiles_dir/$tile" );
		}
			
		$world->set_block( $mc_x, $mc_y, $mc_z, 35.7 );
	}
}

$world->save;
exit;

sub getTileNumber {
  my ($lat,$lon,$zoom) = @_;
  my $xtile = ($lon+180)/360 * 2**$zoom ;
  my $ytile = (1 - log(tan(deg2rad($lat)) + sec(deg2rad($lat)))/pi)/2 * 2**$zoom ;
  return (int($xtile), int($ytile), $xtile-int($xtile), $ytile-int($ytile));
}

