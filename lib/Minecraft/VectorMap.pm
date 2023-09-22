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
	my $grace = 0;
	my $x1 = $self->{min_x}-$grace;
	my $x2 = $self->{max_x}+$grace;
	my $z1 = $self->{min_z}-$grace;
	my $z2 = $self->{max_z}+$grace;
	my( $lat1,$long1 ) = $projection->grid_to_ll( $x1,$z1 );
	my( $lat2,$long2 ) = $projection->grid_to_ll( $x2,$z2 );

	
	# reset the map
	$self->{map} = {};

	# WAYS
	
	my $ways = $self->get_ways(<<END);
	(
  way["leisure"]($lat1,$long1,$lat2,$long2);
  way["building"]($lat1,$long1,$lat2,$long2);
  way["landuse"]($lat1,$long1,$lat2,$long2);
  way["water"]($lat1,$long1,$lat2,$long2);
  way["natural"]($lat1,$long1,$lat2,$long2);
  );
END

	foreach my $way ( values %$ways ) {
		# only do ways with a bounding loop
		next if( $way->{nodes}->[0]->[0] != $way->{nodes}->[-1]->[0] );
		next if( $way->{nodes}->[0]->[1] != $way->{nodes}->[-1]->[1] );

		my $code = $self->tags_to_block_code($way->{tags});
		next unless defined $code;

		my $polygon = $self->nodes_to_polygon( @{$way->{nodes}} );
		$self->draw_poly( $code, $polygon );
	}

	# $self->map_debug;
	
	# RELATIONS

	my $relations = $self->get_relations(<<END);  
(
  relation["leisure"]($lat1,$long1,$lat2,$long2);
  relation["building"]($lat1,$long1,$lat2,$long2);
  relation["landuse"]($lat1,$long1,$lat2,$long2);
  relation["water"]($lat1,$long1,$lat2,$long2);
  relation["natural"]($lat1,$long1,$lat2,$long2);
  );
END
	foreach my $relation ( values %$relations ) {

		my $code = $self->tags_to_block_code($relation->{tags});
		next unless defined $code;

		my $polys = { outer=>[], inner=>[] };
		foreach my $mode ( qw/ outer inner / ) {
			foreach my $way ( @{$relation->{members}->{$mode}} ) {
				# only do ways with a bounding loop
				# if( $way->{nodes}->[0]->[0] != $way->{nodes}->[-1]->[0] || $way->{nodes}->[0]->[1] != $way->{nodes}->[-1]->[1] ) {
					# print "Skipping $mode way\n";
					# next;
					# }

				my $polygon = $self->nodes_to_polygon( @{$way->{nodes}} );
				push @{$polys->{$mode}}, $polygon;
			}
		}
		$self->draw_multipoly( $code, $polys->{outer}, $polys->{inner} );
	}


	# ROADS AND RIVERS

	my $roads_and_rivers = $self->get_ways(<<END);
(
  way["highway"]($lat1,$long1,$lat2,$long2);
  way["waterway"]($lat1,$long1,$lat2,$long2);
);
END
	#$self->map_debug;


	# Ignored waterways include: pressurised canoe_pass fairway fish_pass
	foreach my $river ( values %$roads_and_rivers ) {
		next if( !defined $river->{tags}->{waterway} );
		my $width = 1.5;
		next if( $river->{tags}->{waterway} !~ m/^(river|stream|tidal_channel|canal|drain|ditch)$/ );
		if(  $river->{tags}->{waterway} eq "river" ) {
			$width=8;
		}
		my @route = $self->nodes_to_grid( @{$river->{nodes}} );
		$self->draw_route( "WATER", $width, @route );
	}
	

	# PAVEMENT
	foreach my $road ( values %$roads_and_rivers ) {
		next if( !defined $road->{tags}->{highway} );
		next if( $road->{tags}->{highway} =~ m/^(pedestrian|driveway|track|raceway|footway|bridleway|steps|corridor|path|via_ferrata|cycleway|proposed|construction|elevator|platform|service|motorway|services)$/ );
		next if( defined $road->{tags}->{area} && $road->{tags}->{area} eq "yes" );
		my $width = 6;
		my @route = $self->nodes_to_grid( @{$road->{nodes}} );
		$self->draw_route( "PAVEMENT", $width, @route );
	}
	# ROADS INNER
	foreach my $road ( values %$roads_and_rivers ) {
		next if( !defined $road->{tags}->{highway} );
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
		if( $road->{tags}->{highway} =~ m/^(raceway|motorway)$/ ){
			$width = 6;
			$code = "FANCYROAD";
		}
		if( $road->{tags}->{highway} =~ m/^(cycleway)$/ ){
			$width = 2;
			$code = "FANCYROAD";
		}
		if( $road->{tags}->{highway} =~ m/^(pedestrian)$/ ){
			$width = 4;
			$code = "FANCYROAD";
		}
		if( $road->{tags}->{highway} =~ m/^(service)$/ ){
			$width = 2;
			$code = "ROAD";
		}
		if( defined $road->{tags}->{area} && $road->{tags}->{area} eq "yes" ) {
			my $polygon = $self->nodes_to_polygon( @{$road->{nodes}} );
			$self->draw_poly( $code, $polygon );
		} else {
			my @route = $self->nodes_to_grid( @{$road->{nodes}} );
			$self->draw_route( $code, $width, @route );
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


# takes a list of lat/long nodes and returns a list of east/north nodes
sub nodes_to_grid {
	my( $self, @nodes ) = @_;

	my @points = ();
	foreach my $node (@nodes) {
		push @points, [$self->{projection}->ll_to_grid(@$node)];
	}
	return @points;
}
	
# takes a ref to a  list of lat/long nodes and returns a polygon of minecraft coordinates
sub nodes_to_polygon {
	my( $self, @nodes ) = @_;

	return Minecraft::VectorMap::Polygon->new( [[  $self->nodes_to_grid( @nodes ) ]] );
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
	SAND=>85,
	WATER=>80, # bridges go over water, but tracks don't?
	TRACK=>50,
	PAVEMENT=>30,
	PATH=>20,
	WOOD=>15,
	HEATH=>14,
	WETLAND=>13,
	LAWN=>11,
	GRASS=>10,
	ALLOTMENT=>5,
	DEFAULT=>0,
};

sub set {
	my( $self,$x,$z,$code ) = @_;

        my @cc = $self->{projection}->ll_to_grid(50.93562,-1.3961);

	my $current = $self->block_at_grid($x,$z);
	if( !defined $SCORE->{$code} ) { die "No SCORE for $code"; }
	if( $SCORE->{$current} <= $SCORE->{$code} ) {
		$self->{map}->{$z}->{$x} = $code;
	}
	else {
		#print "won't overwrite $current with $code\n";
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
	
	if( $x<$self->{min_x} || $x>$self->{max_x} ) { return "DEFAULT"; }
	if( $z<$self->{min_z} || $z>$self->{max_z} ) { return "DEFAULT"; }
	if( $self->{map}->{$z}->{$x} ) {
		return $self->{map}->{$z}->{$x};
	}
	return "DEFAULT";
}
sub draw_route {
	my( $self, $code, $width, @route ) = @_;

	my $from = $route[0];
	for( my $i=1;$i<scalar @route; $i++ ) {
		my $to = $route[$i];
		my $polygon = $self->extrude( $from, $to, $width, $width );
		$self->draw_poly( $code, $polygon );
		$self->draw_circle( $code, $from, $width );
		$from = $to;	
	}
	$self->draw_circle( $code, $from, $width );
}

sub draw_circle {
	my( $self, $code, $centre, $radius ) = @_;

	for(my $z_off = -$radius; $z_off<=$radius;$z_off++ ) {
		my $z = int $centre->[1]+$z_off;
		next if $z < $self->{min_z};
		next if $z > $self->{max_z};
		my $width = sqrt( $radius*$radius - $z_off*$z_off );
		for( my $x_off=0; $x_off<$width; $x_off++ ) {
			$self->set(int $centre->[0]-$x_off,$z,$code);
			$self->set(int $centre->[0]+$x_off,$z,$code);
		}
	}
}

sub poly_to_raster {
	my( $self, $poly ) = @_;

	my $raster = bless {}, "Minecraft::VectorMap::Raster";
	for( my $z=int $poly->{min_z}; $z<=$poly->{max_z}; $z++ ) {
		next if $z < $self->{min_z};
		next if $z > $self->{max_z};

		my $toggles = {};
		# our raster line is about $z+0.5
		# we use a slightly off value to avoid any people who use round numbers as we might 
		# not properly intersect a perfectly horizontal parallel line<F2>
		my $raster_z = $z+0.5000123123123123;
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
		for( my $x=int $poly->{min_x}-1; $x<=$poly->{max_x}+1; ++$x ) {
			my $draw_cell = $draw;
			if( $toggles->{$x} ) {
				$draw = !$draw;
				$draw_cell = 1;
			}
			if( $draw_cell && $x >= $self->{min_x} && $x<=$self->{max_x}) {
				$raster->{$z}->{$x} = 1;
			}
		}
	}
	return $raster;
}


sub draw_poly {
	my( $self, $code, $poly ) = @_;

	my $raster = $self->poly_to_raster( $poly );
	$self->draw_raster( $code, $raster );
}

# outer - list of polygons to draw
# inner - list of holes in polygons
sub draw_multipoly {
	my( $self, $code, $outer_polys, $inner_polys ) = @_;

	my $raster = bless {}, "Minecraft::VectorMap::Raster";
	foreach my $poly ( @{$outer_polys} ) {
		my $raster2 = $self->poly_to_raster( $poly );
		$raster->add( $raster2 );
	}
	foreach my $poly ( @{$inner_polys} ) {
		$raster->subtract( $self->poly_to_raster( $poly ) );
	}
	$self->draw_raster( $code, $raster );
}


sub draw_raster {
	my( $self, $code, $raster ) = @_;

	foreach my $z ( keys %$raster ) {
		foreach my $x( keys %{$raster->{$z}} ) {
			$self->set($x,$z,$code);
		}
	}
}


sub get_relations {
	my( $self,$search ) = @_;

	my $query = "
[out:json][timeout:25];
$search
(._;>>;);
out body;
";
	my $url = "https://overpass-api.de/api/interpreter?data=".urlencode($query);
	
	print "Getting URL: $url\n";
	my $json = `curl -L -s '$url' `;
	my $info = decode_json $json;
	my $nodes = {};
	my $ways = {};
	my $relations = {};
	foreach my $element ( @{$info->{elements}} ) {
		next unless ( $element->{type} eq "node" );
		$nodes->{$element->{id}} = [ $element->{lat},$element->{lon} ];
	}
	foreach my $element ( @{$info->{elements}} ) {
		next unless ( $element->{type} eq "way" );
		my @node_ids = @{$element->{nodes}};
		$element->{nodes} = [];
		foreach my $node_id ( @node_ids ) {
			push @{$element->{nodes}}, $nodes->{$node_id};
		}
		$ways->{$element->{id}} = $element;
	}
	# loop over relations
	foreach my $element ( @{$info->{elements}} ) {
		next unless ( $element->{type} eq "relation" );

		my @members = @{$element->{members}};
		$element->{members} = { outer=>[], inner=>[] };
		# we only care about way members, not node members
		
		foreach my $member ( @members ) {
			next unless $member->{type} eq "way";

			my $way = $ways->{$member->{ref}};
			push @{$element->{members}->{$member->{role}}}, $way;
    		}

		# next we should merge ways of inner and outers
		foreach my $role ( qw/ inner outer / ) {
			while(1) {
				my $before;
				my $after;
				# find a merge pair; where one ends with what another starts with
				SEEK: for( my $i=0; $i<scalar @{$element->{members}->{$role}}; $i++ ) {
					for( my $j=0; $j<scalar @{$element->{members}->{$role}}; $j++ ) {
						next if $i==$j; # don't link to yourself
						my $i_end   = join( ",", @{$element->{members}->{$role}->[$i]->{nodes}->[-1]} );
						my $j_start = join( ",", @{$element->{members}->{$role}->[$j]->{nodes}->[0]} );
						if( $i_end eq $j_start ) { 
							$before = $i;
							$after = $j;
							last SEEK;
						}
					}
				}

				# if not exit loop
				last unless defined $before;		
	
				# merge the pair
				# add all nodes from after to before 
				my @after_nodes = @{$element->{members}->{$role}->[$after]->{nodes}};
				# (except the first one)
				shift @after_nodes;
				for( my $i=1; $i<scalar @after_nodes; ++$i ) {
					push @{$element->{members}->{$role}->[$before]->{nodes}}, $after_nodes[$i];
				}
				# now remove the one we plundered
				splice( @{$element->{members}->{$role}}, $after, 1 );
			}
		}
		$relations->{$element->{id}} = $element;
	}

	return $relations;
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
		next unless ( $element->{type} eq "node" );
		$nodes->{$element->{id}} = [ $element->{lat},$element->{lon} ];
	}
	foreach my $element ( @{$info->{elements}} ) {
		next unless ( $element->{type} eq "way" );
		my @node_ids = @{$element->{nodes}};
		$element->{nodes} = [];
		foreach my $node_id ( @node_ids ) {
			push @{$element->{nodes}}, $nodes->{$node_id};
		}
		$ways->{$element->{id}} = $element;
	}
	return $ways;
}

sub urlencode {
	my $s = shift;
	$s =~ s/ /+/g;
	$s =~ s/([^A-Za-z0-9\+-])/sprintf("%%%02X", ord($1))/seg;
	return $s;
}

sub tags_to_block_code {
	my( $self, $tags ) = @_;

	# last matching definiton will be used if multiple matches are found
	my $code;

	if( defined $tags->{landuse} ) {
		if( $tags->{landuse} =~ m/^(brownfield|construction|allotments|farmland|farmyard|flowerbed)$/ ) {
	       		$code = "ALLOTMENT";
		} elsif( $tags->{landuse} =~ m/^(grass|greenfield|meadow|plant_nursery|vineyard)$/ ) {
	       		$code = "GRASS";
		} elsif( $tags->{landuse} =~ m/^(recreation_ground|village_green|cemetery)$/ ) {
	       		$code = "LAWN";
		} elsif( $tags->{landuse} =~ m/^(forest|orchard)$/ ) {
	       		$code = "WOOD";
		} elsif( $tags->{landuse} =~ m/^(basin|salt_pond)$/ ) {
	       		$code = "WATER";
		}
	}
	if( defined $tags->{leisure} ) {
		if( $tags->{leisure} =~ m/^(park|pitch|garden|dog_park|common)$/ ) {
			$code = "GRASS";
		}
		if( $tags->{leisure} =~ m/^(playground)$/ ) {
			$code = "FANCYROAD";
		}
	}
# Unhandled natural tags:
# NO IDEA: arch arete	cave_entrance fumarole hill peak ridge	saddle sinkhole valley volcano tree_row blowhole cape coastline crevasse geyser tree isthmus peninsula
# ROCKY ONES: bare_rock cliff rock stone
# EARTH: earth_bank	
# FLINT?: scree		
# ICE: glacier
# MUD: mud
# FLINT:  shingle
	if( defined $tags->{natural} ) {
		if( $tags->{natural} =~ m/^(bay|reef|hot_spring|shoal|spring|strait|water)$/ ) {
			$code = "WATER";
		}
		if( $tags->{natural} =~ m/^(wetland)$/ ) {
			$code = "WETLAND";
		}
		if( $tags->{natural} =~ m/^(wood)$/ ) {
			$code = "WOOD";
		}
		if( $tags->{natural} =~ m/^(fell|heath|moor|scrub)$/ ) {
			$code = "HEATH";
		}
		if( $tags->{natural} =~ m/^(grassland|tundra)$/ ) {
			$code = "GRASS";
		}
		if( $tags->{natural} =~ m/^(dune|beach|sand)$/ ) {
			$code = "SAND";
		}
	}


# Unhandled building tags
# building: hotel, kindergarten, kiosk, no, office, part, public, residential, roof, school, service, substation, terrace, toilets, train_station, transportation, viaduct,
# building:colour: maroon
# building:material: brick, plaster, 
	if( defined $tags->{building} ) {
		$code = "BUILDING";
		if( $tags->{building} =~ m/^(church)$/ ) {
			$code = "CHURCH";
		}
		if( $tags->{building} =~ m/^(retail|pub)$/ ) {
			$code = "RETAIL";
		}
		if( $tags->{building} =~ m/^(portakabin)$/ ) {
			$code = "BUILDING_WHITE";
		}
		if( $tags->{building} =~ m/^(shed)$/ ) {
			$code = "SHED";
		}
		if( $tags->{building} =~ m/^(industrial)$/ ) {
			$code = "INDUSTRIAL";
		}
	}
	if( defined $tags->{"building:material"} ) {
		if( $tags->{"building:material"} =~ m/^(stone)$/ ) {
			$code = "CHURCH";
		}
		if( $tags->{"building:material"} =~ m/^(stone)$/ ) {
			$code = "BUILDING_SANDSTONE";
		}
	}
	if( defined $tags->{"building:colour"} ) {
		if( $tags->{"building:colour"} =~ m/^(black)$/ ) {
			$code = "BUILDING_BLACK";
		}
		if( $tags->{"building:colour"} =~ m/^(brown|light_brown)$/ ) {
			$code = "BUILDING_BROWN";
		}
		if( $tags->{"building:colour"} =~ m/^(grey)$/ ) {
			$code = "BUILDING_GREY";
		}
		if( $tags->{"building:colour"} =~ m/^(white)$/ ) {
			$code = "BUILDING_WHITE";
		}
		if( $tags->{"building:colour"} =~ m/^(black)$/ ) {
			$code = "BUILDING_BLACK";
		}
	}
	if( defined $tags->{water} ) {
		$code = "WATER";
	}
	if( defined $tags->{waterway} ) {
		$code = "WATER";
	}
	return $code;
}

sub map_debug {
	my( $self ) = @_;

	my $hist = {};
	foreach my $row ( values %{$self->{map}} ) {
		foreach my $cell ( values %{$row} ) {
			$hist->{$cell}++;
		}
	}
	foreach my $code ( sort keys %$hist ) {
		print sprintf( "%6d %s\n", $hist->{$code}, $code );
	}
}


1;
