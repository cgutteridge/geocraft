
package Minecraft::VectorMap::Raster;

use JSON::PP;
use Data::Dumper;
use POSIX;
use Math::Trig;
use Carp;

use strict;
use warnings;

sub add {
	my( $self, $raster2 ) = @_;

	foreach my $z ( keys %$raster2 ) {
		foreach my $x( keys %{$raster2->{$z}} ) {
			$self->{$z}->{$x} = 1;
		}
	}
}

sub subtract {
	my( $self, $raster2 ) = @_;

	foreach my $z ( keys %$raster2 ) {
		foreach my $x( keys %{$raster2->{$z}} ) {
			delete $self->{$z}->{$x} ;
			if( scalar %{$self->{$z}} == 0) { 
				delete $self->{$z};
			}
		}
	}
}

sub debug {
	my( $self ) = @_;

	my $min_x;
	my $max_x;

	my $min_z;
	my $max_z;

	if( scalar %$self == 0 ) { 
		print "[empty]\n";
		return;
	}
	foreach my $z ( keys %$self ) {
		$min_z = $z if( !defined $min_z || $z<$min_z );
		$max_z = $z if( !defined $max_z || $z>$max_z );
		foreach my $x( keys %{$self->{$z}} ) {
			$min_x = $x if( !defined $min_x || $x<$min_x );
			$max_x = $x if( !defined $max_x || $x>$max_x );
		}
	}
	print "$min_x,$min_z -- $max_x,$max_z\n";

	for( my $z=$max_z; $z>=$min_z; $z-- ) {
		for( my $x=$min_x; $x<=$max_x; $x++ ) {
			if( $self->{$z}->{$x} ) { 
				print "#";
			} else {
				print "_";
			}
		}
		print "\n";
	}
}
1;
