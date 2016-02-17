
package Minecraft::Geometry;

use JSON::PP;
use utf8;
use strict;
use warnings;
use Data::Dumper;


sub new
{
	my( $class, %opts ) = @_;

	my $self = bless { %opts }, $class;

	my $fn = "$self->{bbox}.json";

  my $data;
  if( !-e "$self->{dir}/$fn" )
  {
#    my $cmd = "curl -s '$self->{url}?bbox=$self->{bbox}' > $self->{dir}/$fn";
#    print "$cmd\n";
#    my $json = `$cmd`;
#  	$data = decode_json $json;
  }
  else
  {
#   binmode STDOUT, ":utf8";
    my $json;
#    local $/; #Enable 'slurp' mode
#    open my $fh, "<", "$self->{dir}/$fn";
#    $json = <$fh>;
#    close $fh;
#    $data = decode_json($json);

#print Dumper $data;
#    print "ID " . $data->{'features'}->[0]->{'id'} . "\n";
  }

#my $features = $data->{'features'};s
#foreach my $element (@$data->{'features'})
#{
#      print Dumper $element;
#}

	return $self;
}

sub x_block_at
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
