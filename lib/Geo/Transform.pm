
# TODO: switch this to Proj4

package Geo::Transform;

use Geo::Coordinates::EPSG4326;
use Geo::Coordinates::OSGB;
use Geo::Coordinates::OSTN02;

sub ll_to_en
{
	my( $lat, $lon, $srs ) = @_;
	if (defined $srs && $srs eq "EPSG4326")
	{
    return Geo::Coordinates::EPSG4326::ll_to_en($lat, $lon);
  }

	if (defined $srs && $srs eq "ETRS89")
  {
  	my ($x, $y) = Geo::Coordinates::OSGB::ll_to_grid($lat, $lon, $srs); # or "WGS84"
  	return Geo::Coordinates::OSTN02::ETRS89_to_OSGB36($x, $y);
  }

	return Geo::Coordinates::OSGB::ll_to_grid($lat, $lon, $srs);
}

sub en_to_ll
{
	my( $e, $n, $srs ) = @_;

#	if( defined $grid && $grid eq "MERC" )
#	{
#		my $lat = rad2deg(atan(sinh( pi - (2 * pi * -$n / (2**$ZOOM * ($TILE_H * $M_PER_PIX))) )));
#		my $long = (($e / ($TILE_W * $M_PER_PIX)) / 2**$ZOOM)*360-180;
#		return( $lat, $long );
#	}

	if (defined $srs && $srs eq "EPSG4326")
	{
    return Geo::Coordinates::EPSG4326::en_to_ll($e, $n);
  }

	if (defined $srs && $srs eq "ETRS89")
  {
  	my( $x, $y ) = Geo::Coordinates::OSTN02::OSGB36_to_ETRS89( $e, $n );
	  return Geo::Coordinates::OSGB::grid_to_ll($x, $y, $srs); # or "WGS84"
  }

	return Geo::Coordinates::OSGB::grid_to_ll($e, $n, $srs);
}

1;