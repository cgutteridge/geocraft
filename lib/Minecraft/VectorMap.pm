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
	my( $self, $x, $z, $size, $projection ) = @_;

	my $edge = 100;

	my $x1 = $x-$edge;
	my $x2 = $x+$size+$edge-1;
	my $z1 = $z-$edge;
	my $z2 = $z+$size+$edge-1;

	$self->{projection} = $projection;

	my( $lat1,$long1 ) = $projection->grid_to_ll( $x1,$z1 );
	my( $lat2,$long2 ) = $projection->grid_to_ll( $x2,$z2 );

	$self->{map} = {};
	my $roads = $self->get_roads($lat1,$long1,$lat2,$long2 );	

	foreach my $road ( values %$roads ) {
		my $width = 6;
		my @from = $projection->ll_to_grid(@{$road->{nodes}->[0]});
		for( my $i=1;$i<scalar @{$road->{nodes}}; $i++ ) {
			my @to = $projection->ll_to_grid(@{$road->{nodes}->[$i]});
			my $polygon = $self->extrude( \@from, \@to, $width, $width );
			#$self->add_poly( "PAVEMENT", $polygon );
			$self->add_circle( "WATER", \@from, 6 );
			@from = @to;	
		}
	}
	if(0){
	foreach my $road ( values %$roads ) {
		my $width = 4;
		my @from = $projection->ll_to_grid(@{$road->{nodes}->[0]});
		for( my $i=1;$i<scalar @{$road->{nodes}}; $i++ ) {
			my @to = $projection->ll_to_grid(@{$road->{nodes}->[$i]});
			my $polygon = $self->extrude( \@from, \@to, $width, $width );
			#$self->add_poly( "ROAD", $polygon );
			@from = @to;	
		}
	}
	}}
}
			
			
sub extrude {
	my( $self, $from, $to, $left_width, $right_width ) = @_;

	my $xdelta = $to->[0]-$from->[0];
	my $zdelta = $to->[1]-$from->[1];
	my $angle = atan($xdelta/-$zdelta);
	# rotate by 90 to the left
	my $left_angle = $angle-(pi/2);
	my $left_to_x = $to->[0]+sin($left_angle)*$left_width/2;
	my $left_to_z = $to->[1]+cos($left_angle)*$left_width/2;
	my $left_from_x = $from->[0]+sin($left_angle)*$left_width/2;
	my $left_from_z = $from->[1]+cos($left_angle)*$left_width/2;
	my $right_angle = $angle+(pi/2);
	my $right_to_x = $to->[0]+sin($right_angle)*$right_width/2;
	my $right_to_z = $to->[1]+cos($right_angle)*$right_width/2;
	my $right_from_x = $from->[0]+sin($right_angle)*$right_width/2;
	my $right_from_z = $from->[1]+cos($right_angle)*$right_width/2;

	return Minecraft::VectorMap::Polygon->new( [[
					[$left_from_x,$left_from_z],
					[$left_to_x,$left_to_z],
					[$right_to_x,$right_to_z],
					[$right_from_x,$right_from_z]]]);
}
sub block_at {
	my( $self, $lat,$long ) = @_;

	my @cc = $self->{projection}->ll_to_grid($lat,$long);
	if( $self->{map}->{int $cc[1]}->{int $cc[0]} ) {
		return $self->{map}->{int $cc[1]}->{int $cc[0]};
	}
	return "DEFAULT";
}

sub add_circle {
	my( $self, $code, $centre, $radius ) = @_;

	


}

sub add_poly {
	my( $self, $code, $poly ) = @_;

	#$poly->debug;
	for( my $z=int $poly->{min_z}; $z<=$poly->{max_z}; $z++ ) {
		my $toggles = {};
		# our raster line is $z+0.5
		my $raster_z = $z+0.5;
		# let's see which lines it intersects with and if so where.
		my @x_intersect_points = ();
		foreach my $line ( @{$poly->{lines}} ) {
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
			if( $draw_cell ) {
				$self->{map}->{$z}->{$x} = $code;
				#				print "#";
			}
			else {
				#print "_";
			}
		}
		#print "\n";
	}
	#print "\n";
}


sub get_roads {
	my( $self,$lat1,$long1,$lat2,$long2 ) = @_;

	my $query = "
[out:json][timeout:25];
(
  way[\"highway\"]($lat1,$long1,$lat2,$long2);
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
