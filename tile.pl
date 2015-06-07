#!/usr/bin/env perl

use Data::Dumper;
use Image::Magick;
use Math::Trig;
use FindBin;
use lib "$FindBin::Bin/lib";
use Geo::Coordinates::OSGB qw(ll_to_grid grid_to_ll);
use Minecraft;
use strict;
use warnings;

my $map;
my $skip;
require "map.pl";

my $tiles_dir= "$FindBin::Bin/tiles";

my $mc = new Minecraft( "$FindBin::Bin/saves" );
my $world = $mc->world( "Test24" );
$world->init_region(0,0);

my( $lat,$long)=  ( 50.933, -1.38928 );

my( $width, $height ) = (256,256);
#( $width, $height ) = (32,32);

my( $easting_offset, $northing_offset ) = ll_to_grid( $lat,$long);
$easting_offset -= $width/2;
$northing_offset -= $height/2;

my $mc_x_offset = 0;
my $mc_y = 2;
my $mc_z_offset = 0;
my $zoom  =19;
my $tile_width = 256;
my $tile_height = 256;
my $SPREAD = 4;

my $tiles = {};

for( my $y=0; $y<$height; ++$y ) {
	print STDERR "$y\n";
	for( my $x=0; $x<$width; ++$x ) {

		my $e = $easting_offset+$x;
		my $n = $northing_offset+$y;
		my $mc_x = $mc_x_offset+$width - $x-1;
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
			$tiles->{$tile} = new Image::Magick;
			$tiles->{$tile}->Read( "$tiles_dir/$tile" );
		}

		my $pixel_x = int($tile_width*$xr);
		my $pixel_y = int($tile_height*$yr);

		my $scores = {};
		my $best = "";
		my $max = 0;
		for( my $yy=-$SPREAD; $yy<=$SPREAD; ++$yy ) {
			X: for( my $xx=-$SPREAD; $xx<=$SPREAD; ++$xx ) {
				my $p_x = $pixel_x+$xx;
				my $p_y = $pixel_y+$yy;
				next if( $p_x<0 || $p_x>=$tile_width );
				next if( $p_y<0 || $p_y>=$tile_height );
				my @pixel = $tiles->{$tile}->GetPixel(x=>$pixel_x,y=>$pixel_y);
				my $col = int( $pixel[0]*100 ).":".int( $pixel[1]*100 ).":".int($pixel[2]*100);
				next X if( $skip->{$col} );
				$scores->{$col}++;
				if( $scores->{$col} > $max )
				{
					$max = $scores->{$col};
					$best = $col;
				}
			}
		}
		my $underblock = 3;
		my $block = 57;
		if( $map->{$best} ) { $block = $map->{$best}; }

		print "$best\n" if( $block == 57 );
		$underblock = 3 if $block==9;
		$world->set_block( $mc_x, $mc_y-1, $mc_z, $underblock );
		$world->set_block( $mc_x, $mc_y, $mc_z, $block );
		if( $block == 45 )
		{
			for( my $i=0;$i<10;++$i ) 
			{
				$world->set_block( $mc_x, $mc_y+$i, $mc_z, $block );
			}
		}
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

