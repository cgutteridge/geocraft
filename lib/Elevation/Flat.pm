
package Elevation::Flat;

use parent 'Elevation';

use strict;
use warnings;

sub new 
{
	my( $class, $height_dir, $tmp_dir, $correction ) = @_;

	my $self = bless { 
		height_dir => $height_dir,
		tmp_dir => $tmp_dir,
		correction => $correction }, $class;

}

sub ll
{
	my( $self, $model, $lat, $long ) = @_;

	return 0;
}

1;
