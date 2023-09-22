

package Minecraft::VectorMap::Polygon;

use Data::Dumper;
use strict;
use warnings;


# ways is a list of polygons, each polygon is a list of nodes, assumed to be a loop
sub new {
	my( $class, $ways ) = @_;

	my $self = bless { lines => [] }, $class;

	foreach my $way ( @$ways ) {
		for( my $i=0; $i<@$way; $i++ ) {
			my $next_i = ($i+1) % @$way;
			push @{$self->{lines}}, new Minecraft::VectorMap::Line( $way->[$i], $way->[$next_i] );
		}
		foreach my $node ( @$way ) {
			$self->{min_x} = $node->[0] if(!defined $self->{min_x} || $self->{min_x} >= $node->[0] );
			$self->{min_z} = $node->[1] if(!defined $self->{min_z} || $self->{min_z} >= $node->[1] );
			$self->{max_x} = $node->[0] if(!defined $self->{max_x} || $self->{max_x} <= $node->[0] );
			$self->{max_z} = $node->[1] if(!defined $self->{max_z} || $self->{max_z} <= $node->[1] );
		}
	}

	return $self;
}

sub debug {
	my( $self ) = @_;
	print sprintf( "POLY %d,%d -> %d,%d\n", int $self->{min_x},int $self->{min_z},int $self->{max_x},int $self->{max_z} );
	foreach my $line ( @{$self->{lines}} ) {
		my @from = $self->to_local( @{$line->{from}} );
		my @to = $self->to_local( @{$line->{to}} );
		print sprintf( "%d,%d -> %d,%d\n", int $from[0], int $from[1], int $to[0], int $to[1] );
	}
	print "END Poly\n";
}

sub to_local {
	my( $self, @coords ) = @_;

	return($coords[0]-int $self->{min_x}, $coords[1]-int $self->{min_z} );
}

1;
