package Minecraft::Context;

# context to pass to configuration for a single block

use strict;
use warnings;

sub is_inside {
	my( $context ) = @_;

	# the top of a feature is always exterior
	if( $context->{y_offset} == $context->{feature_height} )
	{
		return 0;
	}

	# for each direction
	for my $dir ( qw/ north east south west /)
	{
		# if it's not brick at all then this is defo brick
		if( $context->{block} ne $context->{$dir}->{block} ) {
			return 0;
		}
		# now check that this block is not higher than the neigbouring block's feature
		if( $context->{elevation}+$context->{y_offset} > $context->{$dir}->{elevation}+$context->{$dir}->{feature_height} )
		{
			return 0;
		}
	}
	return 1;
}

1;
