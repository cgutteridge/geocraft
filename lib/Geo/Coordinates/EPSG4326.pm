
package Geo::Coordinates::EPSG4326;

use Math::Trig;

{
  # $EARTH_RADIUS_M        = 6378137;
  # $EARTH_CIRCUMFERENCE_M = $EARTH_RADIUS_M * pi * 2;
  # $M_PER_DEGREE_LAT      = $EARTH_CIRCUMFERENCE_M / 360;

  my $M_PER_DEGREE_LAT = 6378137 * pi / 180;

  sub ll_to_en
  {
    my( $lat, $lon ) = @_;
    my $m_per_degree_lon = $M_PER_DEGREE_LAT * cos($lat / 180 * pi);
    return( $lon * $m_per_degree_lon, $lat * $M_PER_DEGREE_LAT );
  }

  sub en_to_ll
  {
    my $lat = $n / $M_PER_DEGREE_LAT;
    my $m_per_degree_lon = $M_PER_DEGREE_LAT * cos($lat / 180 * pi);
    my $lon = $e / $m_per_degree_lon;
    return( $lon, $lat );
  }
}

1;
