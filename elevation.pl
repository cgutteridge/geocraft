#!/usr/bin/env perl

use FindBin;
use lib "$FindBin::Bin/lib";
use Minecraft;
use Geo::Coordinates::OSGB qw(ll_to_grid grid_to_ll);
use strict;
use warnings;
use POSIX;
use Data::Dumper;

my $mc = new Minecraft( "$FindBin::Bin/saves" );
my $world = $mc->world( "Test23" );
#$world->init_region(0,0);

my( $lat,$long)=  ( 50.933, -1.38928 );

my( $width, $height ) = (256,256);
( $width, $height ) = (32,32);
( $width, $height ) = (512,512);

my( $easting_offset, $northing_offset ) = ll_to_grid( $lat,$long);
$easting_offset = int($easting_offset-$width/2);
$northing_offset = int($northing_offset-$height/2);
my $points = elevation();

my $mc_x_offset = 0;
my $mc_y = 2;
my $mc_z_offset = 0;
my $zoom  =19;


my $MAP_FILE = "map.txt";
my $elevation_scale_h = 20;
my $elevation_scale_v = 20;

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



my($x1,$y1) = ($easting_offset, $northing_offset );
my($x2,$y2) = ($easting_offset+$width+$elevation_scale_h, $northing_offset+$height+$elevation_scale_v );
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
		print "($SW)($SE)($NW)($NE)\n";

		for( my $xx=0;$xx<=$elevation_scale_h;++$xx) {
			for( my $yy=0;$yy<=$elevation_scale_v;++$yy) {
				my $h_ratio = $xx/$elevation_scale_h;
				my $v_ratio = $yy/$elevation_scale_v;
				my $N = $NW + ($NE-$NW)*$h_ratio;
				my $S = $SW + ($SE-$SW)*$h_ratio;
				my $g = $S + ($N-$S)*$v_ratio;
				$ele->{$y+$yy}->{$x+$xx} = POSIX::floor( $g*1 )+10;
			}
		}
	}
}
print Dumper( $ele );
