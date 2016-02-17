
package Minecraft::Geometry;

use strict;
use warnings;

sub new
{
	my( $class, %opts ) = @_;

	my $self = bless { %opts }, $class;

	my $fn = "$self->{bbox}.json";

  if( !-e "$self->{dir}/$fn" ) {
    my $cmd = "curl -s '$self->{url}?bbox=$self->{bbox}' > $self->{dir}/$fn";
    print "$cmd\n";
    `$cmd`;
  }

	return $self;
}

sub block_at
{
	my( $self, $lat, $long ) = @_;

#	my $scores = {};
#	my $best = "FAIL";
#	my $max = 0;
#	foreach my $col ( @colours )
#	{
#		next if( !$self->{map}->{$col} );
#		$scores->{$col}++;
#		if( $scores->{$col} > $max )
#		{
#			$max = $scores->{$col};
#			$best = $col;
#		}
#	}
#	if( $self->{map}->{$best} )
#	{
#		return $self->{map}->{$best};
#	}
#	if( defined $self->{default_block} )
#	{
#		return $self->{default_block};
#	}

	return 1;
}

1;
