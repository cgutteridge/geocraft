

package Minecraft::VectorMap::Line;

use strict;
use warnings;

sub new {
	my( $class, $from, $to ) = @_;

	my $self = bless {from=>$from, to=>$to }, $class;

	return $self;
}

1;
