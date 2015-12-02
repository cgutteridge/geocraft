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



my $postcode = uc $ARGV[0];
my $worldname = $ARGV[1];
my $size = $ARGV[2];
my( $e, $n ) = postcode_to_en($postcode);
if( -e "$FindBin::Bin/saves/$worldname" )
{
	die "World Already exists.";
}
`cp -a "$FindBin::Bin/saves/BedRock" "$FindBin::Bin/saves/$worldname"`;

my $mc = new Minecraft( "$FindBin::Bin/saves" );
my $world = $mc->world( $worldname );


my $OPTS = {};

$OPTS->{MC_BL} = [-$size,-$size];
$OPTS->{MC_TR} = [$size,$size];

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

# $OPTS->{DTM} = new Elevation( "/Users/cjg/Projects/LIDAR-DSM-1M-SU41/DTM" );
# $OPTS->{DSM} = new Elevation( "/Users/cjg/Projects/LIDAR-DSM-1M-SU41/DSM" );
$OPTS->{ELEVATION} = new Elevation( "$FindBin::Bin/lidar", "$FindBin::Bin/uklidar/catalog", "/tmp" );

my $p = Minecraft::Projection->new( $world, 0,0, $e,$n, "OSGB36" );

$p->render( %$OPTS );
exit;

use JSON::PP;
sub postcode_to_en
{
	my( $postcode ) = @_;

	my $url = "http://data.ordnancesurvey.co.uk/doc/postcodeunit/$postcode.json";
	my $json = `curl -s $url`;
	my $data = decode_json $json;
	my $pdata = $data->{"http://data.ordnancesurvey.co.uk/id/postcodeunit/$postcode"};
    	my $e = $pdata->{'http://data.ordnancesurvey.co.uk/ontology/spatialrelations/easting'}->[0]->{value};
    	my $n = $pdata->{'http://data.ordnancesurvey.co.uk/ontology/spatialrelations/northing'}->[0]->{value};
	return( $e,$n );
}
