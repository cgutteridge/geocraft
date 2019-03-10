
package Minecraft::Projection::BlockConfig;
use strict;
use warnings;
use Data::Dumper;
use Carp;

sub val
{
	my( $self, $context, $term, $default ) = @_;

	my $v = $self->{$term};
	$v=$default if( !defined $v );
	return unless defined $v;

	if( ref($v) eq "CODE" )
	{
		$v = &$v( $context );
	}

	return $v;
}

1;
