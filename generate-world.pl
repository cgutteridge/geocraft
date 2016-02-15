#!/usr/bin/env perl

use Data::Dumper;
use FindBin;
use lib "$FindBin::Bin/lib";
use Geo::Coordinates::OSGB qw(ll_to_grid grid_to_ll);
use Minecraft;
use Elevation;
use Minecraft::Projection;
use Minecraft::MapTiles;
use Getopt::Long;

my $from;
my $to;
my $postcode;
my $centre;
my $size;
my $ll;
my $help;
my $yshift;
my $replace;
my $blocks;
my $colours;

BEGIN { 
	sub load_config
	{
		my( $file ) = @_;
		my $return;
		unless ($return = do $file) {
			warn "couldn't parse $file: $@" if $@;
			warn "couldn't do $file: $!"    unless defined $return;
			warn "couldn't run $file"       unless $return;
			exit 1;
		}
	}

	sub help 
	{
		print "$0 [--saves <mc-saves-dir>] [--ll] --from <x>,<y> --to <x>,<y> <world-name>\n";
		print "$0 [--saves <mc-saves-dir>] [--ll] [--centre <x>,<y> | --postcode <code> ] --size <n>|<w>,<h> <world-name>\n";
		print "Additional options: --replace --yshift <n> --blocks <file> --colours <file>\n";
	}

	if( !GetOptions (
    "from=s"   => \$from,
    "to=s"   => \$to,
              	"postcode=s"   => \$postcode,
              	"centre=s"   => \$centre,
              	"size=s"   => \$size,
    "blocks=s"   => \$blocks,
    "colours=s"   => \$colours,
              	"ll"  => \$ll,
    "replace"  => \$replace,
    "yshift=i", \$yshift,
    "help"  => \$help,
	)) {
		print STDERR ("Error in command line arguments\n");
		help();
		exit( 1 );
	}


	foreach my $part ( qw/ colours blocks / )
	{
		if( !-e "$FindBin::Bin/config/$part" )
		{
			`cp $FindBin::Bin/config/$part.template $FindBin::Bin/config/$part`;
		}
	}

	if( defined $colours && $colours ne "" )
	{
		load_config( $colours );
	}
	else
	{
		load_config( "$FindBin::Bin/config/colours" );
	}

	if( defined $blocks && $blocks ne "" )
	{
		load_config( $blocks );
	}
	else
	{
		load_config( "$FindBin::Bin/config/blocks" );
	}
}

use strict;
use warnings;

if( $help )
{
	help();
	exit( 0 );
}


my $OPTS = {};

$OPTS->{FLATLAND} = 0;
$OPTS->{FLOOD} = 0;

my $worldname = $ARGV[0];
if( !defined $worldname )
{
	die "No worldname given";
}

# goal is to end up with bottom left & top right corners in Easting/Northing

if( defined $postcode )
{
	$postcode = uc $postcode;
	$postcode =~ s/\s//g;

	my( $e, $n ) = postcode_to_en($postcode);
	$centre = "$e,$n";
	$ll = 0;
}

sub mya
{
	return @_;
}

my( $e1, $e2, $n1, $n2 );
my( $ANCHOR_E, $ANCHOR_N );
if( defined $centre )
{
	my( $x,$y ) = split( ",", $centre );

	my( $e,$n );
	if( $ll )
	{
		($e,$n) = Elevation::ll_to_en( $x,$y);
	}
	else
	{
		($e,$n)=( $x,$y);
	}

	if( !defined $size )
	{
		die( "--size required with --postcode or --centre" );
	}
	my( $width,$height );
	if( $size =~ m/,/ )
	{
		($width,$height) = split( ",", $size );
	}
	else
	{
		($width,$height) = ($size,$size);
	}
	($ANCHOR_E,$ANCHOR_N) = (int $e,int $n);

	$OPTS->{EAST1} = -int( $width/2 );
	$OPTS->{EAST2} = int( $width/2 );
	$OPTS->{NORTH1} = -int( $height/2 );
	$OPTS->{NORTH2} = int( $height/2 );
}
elsif( defined $from && defined $to )
{
	my( $x1, $y1 ) = split( ",", $from );
	my( $x2, $y2 ) = split( ",", $to );
	my( $e1,$n1 );
	my( $e2,$n2 );
	if( $ll )
	{
		($e1,$n1)=Elevation::ll_to_en( $x1,$y1);
		($e2,$n2)=Elevation::ll_to_en( $x2,$y2);
	}
	else
	{
		($e1,$n1)=($x1,$y1);
		($e2,$n2)=($x2,$y2);
	}
	if( $e1 > $e2 ) { ($e2, $e1) = ($e1, $e2); }
	if( $n1 > $n2 ) { ($n2, $n1) = ($n1, $n2); }

	$ANCHOR_E = int($e1);
	$ANCHOR_N = int($n1);
	$OPTS->{EAST1} = 0;
	$OPTS->{EAST2} = int( $e2-$e1 );
	$OPTS->{NORTH1} = 0;
	$OPTS->{NORTH2} = -int( $n2-$n1 );
}
else
{
	die "missing centre+size or from+to";
}
	
############################### ###############################

if( !-d "$FindBin::Bin/saves" ) { mkdir( "$FindBin::Bin/saves" ); }
if( !-d "$FindBin::Bin/var" ) { mkdir( "$FindBin::Bin/var" ); }
if( !-d "$FindBin::Bin/var/tiles" ) { mkdir( "$FindBin::Bin/var/tiles" ); }
if( !-d "$FindBin::Bin/var/tmp" ) { mkdir( "$FindBin::Bin/var/tmp" ); }
if( !-d "$FindBin::Bin/var/lidar" ) { mkdir( "$FindBin::Bin/var/lidar" ); }
if( !-d "$FindBin::Bin/var/lidar/DSM" ) { mkdir( "$FindBin::Bin/var/lidar/DSM" ); }
if( !-d "$FindBin::Bin/var/lidar/DTM" ) { mkdir( "$FindBin::Bin/var/lidar/DTM" ); }

############################### ###############################
print "=======================================================\n";
print "University of Southampton Open Data Minecraft Map Maker\n";
print "=======================================================\n";

if( -e "$FindBin::Bin/saves/$worldname" )
{
	if( !$replace )
	{
		die "World Already exists. Use --replace to erase it.";
	}
	print "World exists, removing it\n";
	`rm -rf "$FindBin::Bin/saves/$worldname"`;
}
print "Cloning 'bedrock' as a base world\n";
`cp -a "$FindBin::Bin/BedRock" "$FindBin::Bin/saves/$worldname"`;

print "Setting World Options\n";
my $nbt = Minecraft::NBT->from_gzip_file( "$FindBin::Bin/saves/$worldname/level.dat" );
$nbt->{Data}->{LevelName}->{_value} = $worldname;
$nbt->{Data}->{LastPlayed}->{_value} = time()."000";
$nbt->to_gzip_file( "$FindBin::Bin/saves/$worldname/level.dat" );


my $mc = new Minecraft( "$FindBin::Bin/saves" );
my $world = $mc->world( $worldname, init_chunk=>sub {
	my( $region, $cx,$cz ) = @_;
	for( my $off_z=0;$off_z<16;$off_z++ ) {
		for( my $off_x=0;$off_x<16;$off_x++ ) {
			$region->set_block( $cx*16+$off_x, 0, $cz*16+$off_z, 7 ); #bedrock
		}
	}
});


$OPTS->{MAPTILES} = new Minecraft::MapTiles(
	zoom=>19,
	spread=>3,
	width=>256,
	height=>256,
	dir=>"$FindBin::Bin/var/tiles", 
	url=>"http://b.tile.openstreetmap.org/",
	default_block=>1,
	map=>$Minecraft::Config::COLOURS,
);

$OPTS->{BLOCKS} = $Minecraft::Config::BLOCKS;
$OPTS->{EXTEND_DOWNWARDS} = 9;
$OPTS->{TOP_OF_WORLD} = 254;
$OPTS->{YSHIFT} = $yshift;

$OPTS->{ELEVATION} = new Elevation( 
	"$FindBin::Bin/var/lidar", 
	"$FindBin::Bin/var/tmp", 
);

my $p = Minecraft::Projection->new( $world, 0,0, $ANCHOR_E,$ANCHOR_N, "OSGB36" );
print "Projection created. MC0,0 = ${ANCHOR_E}E ${ANCHOR_N}N\n";

$p->render( %$OPTS );
print "Map rendered OK\n";
exit;

use JSON::PP;
sub postcode_to_en
{
	my( $postcode ) = @_;

	my $url = "http://data.ordnancesurvey.co.uk/doc/postcodeunit/$postcode.json";
	print "Getting postcode: $url\n";
	my $json = `curl -s $url`;
	my $data = decode_json $json;
	my $pdata = $data->{"http://data.ordnancesurvey.co.uk/id/postcodeunit/$postcode"};
    	my $e = $pdata->{'http://data.ordnancesurvey.co.uk/ontology/spatialrelations/easting'}->[0]->{value};
    	my $n = $pdata->{'http://data.ordnancesurvey.co.uk/ontology/spatialrelations/northing'}->[0]->{value};
	return( $e,$n );
}
