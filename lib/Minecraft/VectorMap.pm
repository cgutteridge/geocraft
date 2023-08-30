package Minecraft::VectorMap;

use JSON::PP;
use Data::Dumper;
use POSIX;
use Math::Trig;

use strict;
use warnings;

sub new
{
	my( $class, %opts ) = @_;

	my $self = bless { %opts },$class;

	return $self;
}

sub init_region {
	my( $self, $region_x, $region_z, $size, $projection ) = @_;

	print "INIT VECTOR REGION\n";

	$self->{projection} = $projection;

	my $edge = 3;
	$self->{x} = $region_x;
	$self->{z} = $region_z;
	$self->{min_x} = $region_x-$edge;
	$self->{max_x} = $region_x+($size-1)+$edge;
	$self->{min_z} = $region_z-($size-1)-$edge;
	$self->{max_z} = $region_z+$edge;
	print sprintf( "Region bounds %d,%d to %d,%d\n", $self->{min_x},$self->{min_z}, $self->{max_x},$self->{max_z});

	# Get the lat,long bounding box for OSM. Needs to be big enough to capture 
	# things with long lines
	my $grace = 200;
	my $x1 = $self->{min_x}-$grace;
	my $x2 = $self->{max_x}+$grace;
	my $z1 = $self->{min_z}-$grace;
	my $z2 = $self->{max_z}+$grace;
	my( $lat1,$long1 ) = $projection->grid_to_ll( $x1,$z1 );
	my( $lat2,$long2 ) = $projection->grid_to_ll( $x2,$z2 );

	
	# reset the map
	$self->{map} = {};

	my $ways = $self->get_ways(<<END);
(
  way["leisure"]($lat1,$long1,$lat2,$long2);
  way["building"]($lat1,$long1,$lat2,$long2);
  way["landuse"]($lat1,$long1,$lat2,$long2);
  way["water"]($lat1,$long1,$lat2,$long2);
);
END
	foreach my $way ( values %$ways ) {
		# only do ways with a bounding box
		next if( $way->{nodes}->[0]->[0] != $way->{nodes}->[-1]->[0] );
		next if( $way->{nodes}->[0]->[1] != $way->{nodes}->[-1]->[1] );
		my $code;
		if( defined $way->{tags}->{landuse} ) {
			if( $way->{tags}->{landuse} =~ m/^(brownfield|construction|allotments|farmland|farmyard|flowerbed)$/ ) {
	       			$code = "ALLOTMENT";
			} elsif( $way->{tags}->{landuse} =~ m/^(grass|greenfield|recreation_ground|village_green|cemetery|forest|meadow|orchard|plant_nursery|vineyard)$/ ) {
	       			$code = "GRASS";
			} elsif( $way->{tags}->{landuse} =~ m/^(basin|salt_pond)$/ ) {
	       			$code = "WATER";
			}
		}
		if( defined $way->{tags}->{leisure} ) {
			if( $way->{tags}->{leisure} =~ m/^(park|pitch|garden|dog_park|common)$/ ) {
				$code = "GRASS";
			}
			if( $way->{tags}->{leisure} =~ m/^(playground)$/ ) {
				$code = "FANCYROAD";
			}
		}
# Unhandled building tags
# building: hotel, kindergarten, kiosk, no, office, part, public, residential, roof, school, service, substation, terrace, toilets, train_station, transportation, viaduct,
# building:colour: maroon
# building:material: brick, plaster, 
		if( defined $way->{tags}->{building} ) {
			$code = "BUILDING";
			if( $way->{tags}->{building} =~ m/^(church)$/ ) {
				$code = "CHURCH";
			}
			if( $way->{tags}->{building} =~ m/^(retail|pub)$/ ) {
				$code = "RETAIL";
			}
			if( $way->{tags}->{building} =~ m/^(portakabin)$/ ) {
				$code = "BUILDING_WHITE";
			}
			if( $way->{tags}->{building} =~ m/^(shed)$/ ) {
				$code = "SHED";
			}
			if( $way->{tags}->{building} =~ m/^(industrial)$/ ) {
				$code = "INDUSTRIAL";
			}
		}
		if( defined $way->{tags}->{"building:material"} ) {
			if( $way->{tags}->{"building:material"} =~ m/^(stone)$/ ) {
				$code = "CHURCH";
			}
			if( $way->{tags}->{"building:material"} =~ m/^(stone)$/ ) {
				$code = "BUILDING_SANDSTONE";
			}
		}
		if( defined $way->{tags}->{"building:colour"} ) {
			if( $way->{tags}->{"building:colour"} =~ m/^(black)$/ ) {
				$code = "BUILDING_BLACK";
			}
			if( $way->{tags}->{"building:colour"} =~ m/^(brown|light_brown)$/ ) {
				$code = "BUILDING_BROWN";
			}
			if( $way->{tags}->{"building:colour"} =~ m/^(grey)$/ ) {
				$code = "BUILDING_GREY";
			}
			if( $way->{tags}->{"building:colour"} =~ m/^(white)$/ ) {
				$code = "BUILDING_WHITE";
			}
			if( $way->{tags}->{"building:colour"} =~ m/^(black)$/ ) {
				$code = "BUILDING_BLACK";
			}
		}
		if( defined $way->{tags}->{water} ) {
			$code = "WATER";
		}
		next unless defined $code;

		my $points = [];
		foreach my $node (@{$way->{nodes}}) {
			push @$points, [$projection->ll_to_grid(@$node)];
		}
		my $polygon = Minecraft::VectorMap::Polygon->new( [ $points ] );
		$self->add_poly( $code, $polygon );
	}


	my $roads = $self->get_ways(<<END);
(
  way["highway"]($lat1,$long1,$lat2,$long2);
);
END
	# PAVEMENT
	foreach my $road ( values %$roads ) {
		next if( $road->{tags}->{highway} =~ m/^(driveway|track|raceway|footway|bridleway|steps|corridor|path|via_ferrata|cycleway|proposed|construction|elevator|platform|services)$/ );
		my $width = 6;
		my @from = $projection->ll_to_grid(@{$road->{nodes}->[0]});
		for( my $i=1;$i<scalar @{$road->{nodes}}; $i++ ) {
			my @to = $projection->ll_to_grid(@{$road->{nodes}->[$i]});
			my $polygon = $self->extrude( \@from, \@to, $width, $width );
			$self->add_poly( "PAVEMENT", $polygon );
			$self->add_circle( "PAVEMENT", \@from, $width );
			@from = @to;	
		}
	}
	foreach my $road ( values %$roads ) {
		my $width = 4;
		my $code = "ROAD";
		next if( $road->{tags}->{highway} =~ m/^(via_ferrata|proposed|construction|services|elevator)$/ );
		if( $road->{tags}->{highway} =~ m/^(track|bridleway)$/ ) {
			$width = 3;
			$code = "TRACK";
		}
		if( $road->{tags}->{highway} =~ m/^(footway|steps|corridor|path)$/ ){
			$width = 2;
			$code = "PATH";
		}
		if( $road->{tags}->{highway} =~ m/^(raceway)$/ ){
			$width = 6;
			$code = "FANCYROAD";
		}
		if( $road->{tags}->{highway} =~ m/^(cycleway)$/ ){
			$width = 2;
			$code = "FANCYROAD";
		}
		my @from = $projection->ll_to_grid(@{$road->{nodes}->[0]});
		for( my $i=1;$i<scalar @{$road->{nodes}}; $i++ ) {
			my @to = $projection->ll_to_grid(@{$road->{nodes}->[$i]});
			my $polygon = $self->extrude( \@from, \@to, $width, $width );
			$self->add_poly( $code, $polygon );
			$self->add_circle( $code, \@from, $width );
			@from = @to;	
		}
	}

	if( 0 ) {
		# put a debug border around each region
		my $region_x2 = $region_x + $size -1;
		my $region_z2 = $region_z - ($size -1);
		for( my $x=$region_x; $x<$region_x2; ++$x ) {
			$self->set($x,$region_z, "WATER");
			$self->set($x,$region_z2,"WATER");
		}
		for( my $z=$region_z; $z>$region_z2; --$z ) {
			$self->set($region_x, $z,"ROAD");
			$self->set($region_x2,$z,"FANCYROAD");
		}
	}
	
}

# priority of blocks
my $SCORE = {
	RETAIL=>220,
	CHURCH=>210,
	BUILDING_WHITE=>201,
	BUILDING_BLACK=>201,
	BUILDING_BROWN=>201,
	BUILDING_GREY=>201,
	BUILDING_SANDSTONE=>201,
	BUILDING=>200,
	INDUSTRIAL=>200,
	SHED=>150,
	FANCYROAD=>100,
	ROAD=>90,
	WATER=>80, # bridges go over water, but tracks don't?
	TRACK=>50,
	PAVEMENT=>30,
	PATH=>20,
	GRASS=>10,
	ALLOTMENT=>5,
	DEFAULT=>0,
};

sub set {
	my( $self,$x,$z,$code ) = @_;

	my $current = $self->block_at_grid($x,$z);
	if( $SCORE->{current} <= $SCORE->{$code} ) {
		$self->{map}->{$z}->{$x} = $code;
	}
	else {
		print "won't overwrite $current with $code\n";
	}
}
			
sub extrude {
	my( $self, $from, $to, $left_width, $right_width ) = @_;

	my $xdelta = $to->[0]-$from->[0];
	my $zdelta = $to->[1]-$from->[1];
	if( $zdelta == 0 ) { $zdelta = 0.000001; }
	my $angle = atan($xdelta/$zdelta);
	# rotate by 90 to the left
	my $left_angle = $angle-(pi/2);
	my $left_to_x = $to->[0]+sin($left_angle)*$left_width;
	my $left_to_z = $to->[1]+cos($left_angle)*$left_width;
	my $left_from_x = $from->[0]+sin($left_angle)*$left_width;
	my $left_from_z = $from->[1]+cos($left_angle)*$left_width;
	my $right_angle = $angle+(pi/2);
	my $right_to_x = $to->[0]+sin($right_angle)*$right_width;
	my $right_to_z = $to->[1]+cos($right_angle)*$right_width;
	my $right_from_x = $from->[0]+sin($right_angle)*$right_width;
	my $right_from_z = $from->[1]+cos($right_angle)*$right_width;

	return Minecraft::VectorMap::Polygon->new( [[
					[$left_from_x, $left_from_z],
					[$left_to_x,   $left_to_z],
					[$right_to_x,  $right_to_z],
					[$right_from_x,$right_from_z]]]);
}
sub block_at {
	my( $self, $lat,$long ) = @_;

	my @cc = $self->{projection}->ll_to_grid($lat,$long);

	return $self->block_at_grid( int $cc[0], int $cc[1] );
}

# expects ints
sub block_at_grid {
	my( $self, $x,$z ) = @_;
	# test scope as we can't answer questions out of scope correctly
	
	if( $x<$self->{min_x} || $x>$self->{max_x} ) { print "Out of scope: x=".$x."\n"; die; }
	if( $z<$self->{min_z} || $z>$self->{max_z} ) { print "Out of scope: z=".$z."\n";  die;}
	if( $self->{map}->{$z}->{$x} ) {
		return $self->{map}->{$z}->{$x};
	}
	return "DEFAULT";
}

sub add_circle {
	my( $self, $code, $centre, $radius ) = @_;

	for(my $z_off = -$radius; $z_off<=$radius;$z_off++ ) {
		my $z = int $centre->[1]+$z_off;
		next if $z < $self->{min_z};
		next if $z > $self->{max_z};
		my $width = sqrt( $radius*$radius - $z_off*$z_off );
		for( my $x_off=0; $x_off<$width; $x_off++ ) {
			$self->{map}->{$z}->{int $centre->[0]-$x_off} = $code;
			$self->{map}->{$z}->{int $centre->[0]+$x_off} = $code;
		}
	}
}

sub add_poly {
	my( $self, $code, $poly ) = @_;

	#$poly->debug;
	for( my $z=int $poly->{min_z}; $z<=$poly->{max_z}; $z++ ) {
		next if $z < $self->{min_z};
		next if $z > $self->{max_z};

		my $toggles = {};
		# our raster line is $z+0.5
		my $raster_z = $z+0.5;
		# let's see which lines it intersects with and if so where.
		my @x_intersect_points = ();
		foreach my $line ( @{$poly->{lines}} ) {
			# line is entirely above or below this raster line?
			next if( $line->{from}->[1] > $raster_z && $line->{to}->[1] > $raster_z );
			next if( $line->{from}->[1] < $raster_z && $line->{to}->[1] < $raster_z );

			my($a,$b);
			# a will be the west most of the two points
			if( $line->{from}->[0] < $line->{to}->[0] ) {
				($a,$b)=($line->{from},$line->{to});
			} else {
				($a,$b)=($line->{to},$line->{from});
			}
			# distance from point a to the raster line
			my $a_vdist_to_line = $raster_z - $a->[1];
			my $a_vdist_to_b = $b->[1] - $a->[1];
			if( $a_vdist_to_b == 0 ) { $a_vdist_to_b = 0.0000001; }
			my $ratio_to_line = $a_vdist_to_line / $a_vdist_to_b;
			my $a_hdist_to_b = $b->[0] - $a->[0];
			my $intersect_x = int($a->[0] + $a_hdist_to_b * $ratio_to_line);
			if( $toggles->{$intersect_x} ) {
				delete $toggles->{$intersect_x};
			} else {
				$toggles->{$intersect_x} = 1;
			}
		}	
		my $draw = 0;
		for( my $x=int $poly->{min_x}; $x<=$poly->{max_x}; ++$x ) {
			my $draw_cell = $draw;
			if( $toggles->{$x} ) {
				$draw = !$draw;
				$draw_cell = 1;
			}
			if( $draw_cell && $x >= $self->{min_x} && $x<=$self->{max_x}) {
				$self->{map}->{$z}->{$x} = $code;
			}
		}
	}
}


sub get_ways {
	my( $self,$search ) = @_;

	my $query = "
[out:json][timeout:25];
$search
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
	}
	foreach my $element ( @{$info->{elements}} ) {
		if( $element->{type} eq "way" ) {
			my @node_ids = @{$element->{nodes}};
			$element->{nodes} = [];
			foreach my $node_id ( @node_ids ) {
				push @{$element->{nodes}}, $nodes->{$node_id};
			}
			$ways->{$element->{id}} = $element;
		}
	}
	return $ways;
}

sub urlencode {
	my $s = shift;
	$s =~ s/ /+/g;
	$s =~ s/([^A-Za-z0-9\+-])/sprintf("%%%02X", ord($1))/seg;
	return $s;
}

1;
