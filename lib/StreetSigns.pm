package Minecraft::StreetSigns;

use JSON::PP;
use Data::Dumper;
use POSIX;
use Math::Trig;

use strict;
use warnings;

my $MIN_SIGN_SPACING = 10;

sub get {
	my( $lat1,$long1, $lat2,$long2 ) = @_;

	if( $lat1 > $lat2 ) { my $a=$lat1; $lat1=$lat2; $lat2=$a; }
	if( $long1 > $long2 ) { my $a=$long1; $long1=$long2; $long2=$a; }

	my $query = "
[out:json][timeout:25];
(
  way[\"highway\"][\"name\"]($lat1,$long1,$lat2,$long2);
);
(._;>;);
out body;
";
	my $url = "https://overpass-api.de/api/interpreter?data=".urlencode($query);
	
	print "Getting URL: $url\n";
	my $json = `curl -L -s '$url' `;
	my $info = decode_json $json;

	my $nodes = {};
	my $ways = {};
	foreach my $element ( @{$info->{elements}} ) {
		if( $element->{type} eq "node" ) {
			$nodes->{$element->{id}} = [ $element->{lat},$element->{lon} ];
		}
		if( $element->{type} eq "way" ) {
			$ways->{$element->{id}} = $element;
		}
	}

	my $points = [];
	foreach my $way ( values %$ways ) {
		my $last_ll;
		my $set_points = [];
		foreach my $node_id ( @{$way->{nodes}} ) {
			my $node_ll = $nodes->{$node_id};
			if( $last_ll ) {
				my $midpoint = [
					($last_ll->[0] + $node_ll->[0])/2.0,
					($last_ll->[1] + $node_ll->[1])/2.0 ];
				# if the midpoint is within range of any signs already
				# placed for this road then don't place a sign
				my $place = 1;
				foreach my $placed_sign ( @$set_points ) {
					my $dist = get_ll_distance_in_m( $midpoint->[0],$midpoint->[1],$placed_sign->[0],$placed_sign->[1] );
					if( $dist <= $MIN_SIGN_SPACING ) {
						$place = 0;
						last;
					}
				}
				if( $place ) {
					push @{$set_points}, [
						$midpoint->[0],
						$midpoint->[1],
						$way->{tags}->{name}
					];
				}
			}
			$last_ll = $node_ll;
		}
		foreach my $point (@{$set_points} ) {
			push @$points, $point;
		}
	}
	return $points;
}

sub urlencode {
	my $s = shift;
	$s =~ s/ /+/g;
	$s =~ s/([^A-Za-z0-9\+-])/sprintf("%%%02X", ord($1))/seg;
	return $s;
}

# Haversine formula (we just need an approximate value to not put signs too near each other)
sub get_ll_distance_in_m {
	my( $lat1,$lon1,$lat2,$lon2 ) = @_;

	my $R = 6371000; # Radius of the earth in m
  	my $dLat = deg_to_rad($lat2-$lat1);  # deg_to_rad below
  	my $dLon = deg_to_rad($lon2-$lon1);
	my $a = 
		sin($dLat/2) * sin($dLat/2) +
		cos(deg_to_rad($lat1)) * cos(deg_to_rad($lat2)) *
		sin($dLon/2) * sin($dLon/2)
		;
	my $c = 2 * atan2(sqrt($a), sqrt(1-$a));
	my $d = $R * $c; # Distance in m
	return $d;
}

sub deg_to_rad {
	my( $deg ) = @_;
	return $deg * (pi/180)
}


1;
