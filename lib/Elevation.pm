package Elevation;

# needs to be subclassed
# these are the interface methods

sub new 
{
	my( $class, $cache_dir, $tmp_dir, $correction ) = @_;

	die "Elevation must be subclassed";
}

# model is DSM or DTM
sub ll
{
	my( $self, $model, $lat, $long ) = @_;

	die "ll must be subclassed";
}

1;

