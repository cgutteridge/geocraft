#!/usr/bin/env perl

use Data::Dumper;
use Image::Magick;
use Math::Trig;
use FindBin;
use lib "$FindBin::Bin/lib";
use Geo::Coordinates::OSGB qw(ll_to_grid grid_to_ll);
use Minecraft;
use POSIX;

$X::skip={};
$X::map={};
require "map.pl";
use strict;
use warnings;
my $ele_tweak_h = 90;
my $ele_tweak_v = -80;

my $tiles_dir= "$FindBin::Bin/tiles";

my $mc = new Minecraft( "$FindBin::Bin/saves" );
my $world = $mc->world( "Test23" );
$world->init_region(0,0);
$world->init_region(0,1);
$world->init_region(1,0);
$world->init_region(1,1);

my( $lat,$long);
( $lat,$long)=  ( 50.93452, -1.397 ); #uni
#( $lat,$long)=  ( 50.89266, -1.40567  ); #town quay end
#( $lat,$long)=  ( 50.89578, -1.40625 ); #town quay
#( $lat,$long)=  ( 50.89945, -1.40555 );

my( $width, $height ) = (256,256);
( $width, $height ) = (100,100);
( $width, $height ) = (1024,1024);


my( $easting_offset, $northing_offset ) = ll_to_grid( $lat,$long);
$easting_offset = POSIX::floor($easting_offset-$width/2);
$northing_offset = POSIX::floor($northing_offset-$height/2);

my $mc_x_offset = 0;
my $mc_y = 2;
my $mc_z_offset = 0;
my $zoom  =19;
my $SPREAD = 4;
my $tile_width = 256;
my $tile_height = 256;
my $MAP_FILE = "$FindBin::Bin/map.txt";
my $TREE_FILE = "$FindBin::Bin/trees.tsv";
my $elevation_scale_h = 20;
my $elevation_scale_v = 20;
my $elevation = elevation();

my $tiles = {};

my $trees = {};
open( my $tfh, "<", $TREE_FILE ) || die "can't treeread: $!";
while( my $line = <$tfh> )
{
	chomp $line;
	my( $lat, $long ) = split( /\t/,$line );
	my( $e,$n ) = ll_to_grid( $lat,$long );
	$trees->{POSIX::floor($n)}->{POSIX::floor($e)} = 1;
}

my $failcols = {};
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

		my $pixel_x = POSIX::floor($tile_width*$xr);
		my $pixel_y = POSIX::floor($tile_height*$yr);

		my $scores = {};
		my $best = "FAIL";
		my $max = 0;
		my $midcol="eh";
		for( my $yy=-$SPREAD; $yy<=$SPREAD; ++$yy ) {
			X: for( my $xx=-$SPREAD; $xx<=$SPREAD; ++$xx ) {
				my $p_x = $pixel_x+$xx;
				my $p_y = $pixel_y+$yy;
				next if( $p_x<0 || $p_x>=$tile_width );
				next if( $p_y<0 || $p_y>=$tile_height );
				my @pixel = $tiles->{$tile}->GetPixel(x=>$p_x,y=>$p_y);
				my $col = int( $pixel[0]*100 ).":".int( $pixel[1]*100 ).":".int($pixel[2]*100);
				if( $xx==0 && $yy==0 ) { $midcol=$col;}
				#if( $x==30 && $y==23 ) { print "$xx,$yy : $col\n"; }
				#next X if( $X::skip->{$col} );
#				next X if( !$X::map->{$col} );

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
		if( $X::map->{$best} ) { $block = $X::map->{$best}; }

		my($lat1,$long1) = grid_to_ll( $e, $n );
        	my($e1,$n1) = ll_to_grid($lat1,$long1,"WGS84");
		$mc_y = $elevation->{POSIX::floor($n1)+$ele_tweak_v}->{POSIX::floor($e1)+$ele_tweak_h}+10;

		$failcols->{$midcol}++ if( $block == 57 );
		$underblock = 3 if $block==9;
		$world->set_block( $mc_x, $mc_y-1, $mc_z, $underblock );
		$world->set_block( $mc_x, $mc_y, $mc_z, $block );
		if( $block == 45 || $block == 98)
		{
			for( my $i=0;$i<10;++$i ) 
			{
				$world->set_block( $mc_x, $mc_y+$i, $mc_z, $block );
			}
		}
		elsif( $trees->{$n}->{$e} )
		{
print "TREE!\n";
			my $TREESIZE=4;
			my $TRUNKSIZE=4;
			for( my $xx=-$TREESIZE;$xx<=$TREESIZE;++$xx ){
				for( my $yy=-$TREESIZE;$yy<=$TREESIZE;++$yy ){
					ZZ: for( my $zz=-$TREESIZE;$zz<=$TREESIZE;++$zz ){
						next ZZ if( abs($xx)+abs($yy)+abs($zz)>$TREESIZE );
						$world->set_block( $mc_x+$xx,$mc_y+$TRUNKSIZE+$TREESIZE+$yy,$mc_z+$zz, 18);
					}
				}
			}
			for( my $i=0;$i<$TRUNKSIZE+$TREESIZE;++$i )
			{
				$world->set_block( $mc_x,$mc_y+1+$i,$mc_z, 17);
			}
		}
	}
	
}

my $c={};
foreach my $failcol ( keys %$failcols )
{
	my $v = $failcols->{$failcol};
	$c->{sprintf("%10d %s", $v, $failcol )} = "$failcol : $v";
}
foreach my $key ( sort keys %$c )
{
	print $c->{$key}."\n";
}
$world->save;
exit;

sub getTileNumber {
  my ($lat,$lon,$zoom) = @_;
  my $xtile = ($lon+180)/360 * 2**$zoom ;
  my $ytile = (1 - log(tan(deg2rad($lat)) + sec(deg2rad($lat)))/pi)/2 * 2**$zoom ;
  return (int($xtile), int($ytile), $xtile-int($xtile), $ytile-int($ytile));
}

sub elevation
{
	my $elefiles = {};
	open( my $mfh, "<", $MAP_FILE );
	while( my $line = <$mfh> )
	{
		$line =~ s/\n//g;
		$line =~ s/\r//g;
		chomp $line;
		my($line_north, $line_east ,$filename) = split( / /, $line );
		$elefiles->{$line_north}->{$line_east} = $filename;
	}

	
	my($lat1,$long1) = grid_to_ll( $easting_offset, $northing_offset );
	my($lat2,$long2) = grid_to_ll( $easting_offset+$width, $northing_offset+$height );
        my($x1,$y1) = ll_to_grid($lat1,$long1,"WGS84");
        my($x2,$y2) = ll_to_grid($lat2,$long2,"WGS84");
	$x1=POSIX::floor($x1)+$ele_tweak_h;
	$y1=POSIX::floor($y1)+$ele_tweak_v;
	$x2=POSIX::floor($x2)+$ele_tweak_h;
	$y2=POSIX::floor($y2)+$ele_tweak_v;
	
	$x2+=$elevation_scale_h;
	$y2+=$elevation_scale_v;

	$x1 = $x1 - $x1 % $elevation_scale_h;
	$y1 = $y1 - $y1 % $elevation_scale_v;
	my $points = {};
	for( my $x=$x1;$x<=$x2;$x+=$elevation_scale_h )
	{
		Y: for( my $y=$y1;$y<=$y2;$y+=$elevation_scale_v )
		{
			next Y if( defined $points->{$y}->{$x} );
			my $n_offset = $y-$y%10000;
			my $e_offset = $x-$x%10000;
			my $fn = $elefiles->{ $n_offset }->{ $e_offset };
	
			if( !defined $fn ) { die "no elevation for $e_offset,$n_offset"; }
	
			my $file = "$FindBin::Bin/HeightData/$fn";
			open( my $hfh, "<", $file ) || die "can't read $file";
			my @lines = <$hfh>;
			close $hfh;
		
			for( my $i=6; $i<scalar(@lines); ++$i )
			{
				my $line = $lines[$i];
				$line =~ s/\n//g;
				$line =~ s/\r//g;
				my @row = split( / /, $line );
				for( my $j=0; $j<scalar(@row); $j++ )
				{
					$points->{ $n_offset + (499-($i-6))*$elevation_scale_v }->{ $e_offset + $j*$elevation_scale_h } = $row[$j];
				}
			}
		}
	}
	
	my $ele = {};
	for(my $x=$x1;$x<$x2;$x+=$elevation_scale_h )
	{
		for(my $y=$y1;$y<$y2;$y+=$elevation_scale_v )
		{
			my $SW = $points->{ $y }->{ $x };
			my $SE = $points->{ $y }->{ $x+$elevation_scale_h };
			my $NW = $points->{ $y+$elevation_scale_v }->{ $x };
			my $NE = $points->{ $y+$elevation_scale_v }->{ $x+$elevation_scale_h };
			#print "($SW)($SE)($NW)($NE)\n";
	
			for( my $xx=0;$xx<=$elevation_scale_h;++$xx) {
				for( my $yy=0;$yy<=$elevation_scale_v;++$yy) {
					my $h_ratio = $xx/$elevation_scale_h;
					my $v_ratio = $yy/$elevation_scale_v;
					my $N = $NW + ($NE-$NW)*$h_ratio;
					my $S = $SW + ($SE-$SW)*$h_ratio;
					my $g = $S + ($N-$S)*$v_ratio;
					$ele->{$y+$yy}->{$x+$xx} = POSIX::floor( $g*1 );
				}
			}
		}
	}
	return $ele;
}
