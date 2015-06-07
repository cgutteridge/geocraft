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

my $tiles_dir= "$FindBin::Bin/tiles";

my $mc = new Minecraft( "$FindBin::Bin/saves" );
my $world = $mc->world( "Test23" );
$world->init_region(0,0);

my( $lat,$long)=  ( 50.89461, -1.39271 );

my( $width, $height ) = (256,256);

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

for( my $x=0; $x<$width; ++$x ) {
	for( my $y=0; $y<$height; ++$y ) {

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
		$block = 45 if $best eq "85:81:78"; #building
		$block = 45 if $best eq "84:81:78"; #building
		$block = 2 if $best eq "81:92:65"; #grass
		$block = 2 if $best eq "68:81:62"; #woods?
		$block = 2 if $best eq "80:92:65"; # grass?
		$block = 13 if $best eq "96:93:71"; # carpark?
		$block = 159.3 if $best eq "94:93:90"; #tarmac? 
		$block = 159.3 if $best eq "94:93:91";#tarmac
		$block = 60 if $best eq "89:78:67"; #allotment
		$underblock = 9 if $best eq "89:78:67"; #allotment
		$block = 9 if $best eq "70:81:81";  # water
		$block = 1 if $best eq "57:66:83";#stone

		# edges - redsand
		$block = 181 if $best eq "63:72:82"; 

		$block = 159.9 if $best eq "88:88:88";# private -cyan clay
		$block = 159.9 if $best eq "87:87:87"; # private -cyan clay

		$block = 159.4 if $best eq "80:80:77";#campus? yellow clay

		$block = 159.8 if $best eq "92:85:90";# light grey clay( docks)

		$block = 159.15 if $best eq "99:99:99"; #road


#unknown35.13
		$block = 5.5 if $best eq "75:75:74";# dark oak
		$block = 35.13 if $best eq "67:67:66";#green wool
		$block = 35.1  if $best eq "95:95:90"; #orange woold
		$block = 5.2 if $best eq "77:72:69";#birch
		$block = 35.6 if $best eq "57:65:83"; # pink wool
		$block = 35.11 if $best eq "80:80:80"; #blue wool
		$block = 95.15 if $best eq "86:86:86"; #black glass
		$block = 35.8 if $best eq "76:70:66"; #light grey wool

		$block = 35.3 if $best eq "89:78:66";#light blue wool
		$block = 35.5 if $best eq "94:94:84";#lime wool
		$block = 35.10 if $best eq "92:92:92";#purple wool
		$block = 1.1 if $best eq "91:91:91";#granite
		$block = 1.2 if $best eq "56:79:46";#polished granite
		$block = 1.3 if $best eq "65:80:59";#diorite
		$block = 1.4 if $best eq "92:92:83";#polished #diorite
		$block = 1.5 if $best eq "96:82:82";#andesite
		$block = 1.6 if $best eq "67:81:62";#polished andesite
		$block = 159.0 if $best eq "89:89:89";#white clay
		$block = 159.1 if $best eq "83:79:76";#orange clay
		$block = 159.2 if $best eq "83:92:69";#magenta clay
		$block = 5 if $best eq "91:91:83"; #wood
		$block = 159.5 if $best eq "56:80:46";#lime clay
		$block = 159.6 if $best eq "77:77:75";#pink clay
		$block = 159.7 if $best eq "0:57:85";#grey clay
		$block = 152 if $best eq "75:75:75"; #redstone
		$block = 159.10 if $best eq "45:29:3";#purple clay
		$block = 159.11 if $best eq "89:89:81";#blue clay
		$block = 159.12 if $best eq "97:97:97";#brown clay
		$block = 159.13 if $best eq "78:74:69";#green clay
		$block = 159.14 if $best eq "83:80:77";#red clay
		$block = 166 if $best eq "77:72:67"; #slime
		$block = 35.7 if $best eq "85:85:85";#grey wool

		$block = 35.4 if $best eq "81:81:81"; #yellow wool
		$block = 35.12 if $best eq "78:78:78"; #brown wool
		$block = 35.9 if $best eq "96:96:96"; #cyan wool
		$block = 35.14 if $best eq "95:95:95"; #red wool
		$block = 35.2 if $best eq "85:85:80"; #magenta wool
		$block = 95.0 if $best eq "77:77:77"; # white glass
		$block = 95.1 if $best eq "81:92:67"; #ora glass
		$block = 95.2 if $best eq "91:90:82"; #mag glass
		$block = 95.3 if $best eq "70:70:70"; #lblue glass
		$block = 95.4 if $best eq "94:94:94"; #yello glass
		$block = 95.5 if $best eq "95:95:89"; #lime glass
		$block = 95.6 if $best eq "69:69:67"; #pink glass
		$block = 95.7 if $best eq "69:69:69"; #grey glass
		$block = 95.8 if $best eq "74:74:74"; #light grey glass
		$block = 95.9 if $best eq "81:77:74"; #cyan glass
		$block = 95.10 if $best eq "83:83:83"; #purple glass
		$block = 95.11 if $best eq "69:69:66"; # blue glass
		$block = 95.12 if $best eq "76:70:65"; #brown glass
		$block = 95.13 if $best eq "84:80:78"; #green glass 
		$block = 95.14 if $best eq "80:76:72"; #red glass
		$block = 5.1 if $best eq "60:60:60"; #spruce
		$block = 5.3 if $best eq "29:64:98";#	jungle
		$block = 5.4 if $best eq "71:70:57";#acacia
		print "$best\n" if( $block == 57 );
		$underblock = 3 if $block==9;

		$world->set_block( $mc_x, $mc_y-1, 1, $underblock );
		$world->set_block( $mc_x, $mc_y, $mc_z, $block );
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

