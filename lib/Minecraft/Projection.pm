package Minecraft::Projection;

use Geo::Coordinates::OSGB;
use Math::Trig;
use Data::Dumper;
use strict;
use warnings;

sub new_from_ll
{
	my( $class, $world, $mc_ref_x,$mc_ref_z, $lat,$long, $grid ) = @_;

	my( $e, $n ) = ll_to_grid( $lat,$long, $grid );
print "new world, base: $e,$n\n";
	return $class->new( $world, $mc_ref_x,$mc_ref_z,  $e,$n,  $grid );
}

my $ZOOM = 18;
my $M_PER_PIX = 0.596;
my $TILE_W = 256;
my $TILE_H = 256;
sub ll_to_grid
{
	my( $lat, $long, $grid ) = @_;
	#print "ll_to_grid($lat,$long)\n";

	if( defined $grid && $grid eq "MERC" )
	{
		# inverting north/south for some reason -- seems to work
		my $e = ($long+180)/360 * 2**$ZOOM * ($TILE_W * $M_PER_PIX);	
		my $n = -(1 - log(tan(deg2rad($lat)) + sec(deg2rad($lat)))/pi)/2 * 2**$ZOOM * ($TILE_H * $M_PER_PIX);
		return( $e, $n );
	}
	if( defined $grid && $grid eq "OSGB36" )
	{
		my ($x, $y) = Geo::Coordinates::OSGB::ll_to_grid($lat, $long, 'ETRS89'); # or 'WGS84'
		my( $e,$n)= Geo::Coordinates::OSTN02::ETRS89_to_OSGB36($x, $y );
	print "$lat,$long =$grid=> $e,$n\n";
		return( $e, $n );
	}

	return Geo::Coordinates::OSGB::ll_to_grid( $lat,$long, $grid );
}
sub grid_to_ll
{
	my( $e, $n, $grid ) = @_;

	if( defined $grid && $grid eq "MERC" )
	{
		my $lat = rad2deg(atan(sinh( pi - (2 * pi * -$n / (2**$ZOOM * ($TILE_H * $M_PER_PIX))) )));
		my $long = (($e / ($TILE_W * $M_PER_PIX)) / 2**$ZOOM)*360-180;
		return( $lat, $long );
	}
	if( defined $grid && $grid eq "OSGB36" )
	{
		my( $x,$y)= Geo::Coordinates::OSTN02::OSGB36_to_ETRS89($e, $n );
		return Geo::Coordinates::OSGB::grid_to_ll($x, $y, 'ETRS89'); # or 'WGS84'
	}


	return Geo::Coordinates::OSGB::grid_to_ll( $e,$n, $grid );
}




sub new
{
	my( $class, $world, $mc_ref_x,$mc_ref_z,  $e,$n,  $grid ) = @_;

	my $self = bless {},$class;
	$self->{grid} = $grid;
	$self->{world} = $world;

	# the real world E & N at MC 0,0
	$self->{offset_e} = $e-$mc_ref_x;
	$self->{offset_n} = $n+$mc_ref_z;

	return $self;
}
	
# more mc_x : more easting
# more mc_y : less northing

sub render
{
	my( $self, %opts ) = @_;

	# MC_BL = [x,z]	 (NW)
	# MC_TR = [x,z]	 (SE)
	#my( $mc_ref_x,$mc_ref_z,  $e_ref,$n_ref,  $mc_x1,$mc_z1,  $mc_x2,$mc_z2 ) = @_;

	die "x2<=x1" if $opts{MC_TR}->[0]<=$opts{MC_BL}->[0];
	die "z2<=z1" if $opts{MC_TR}->[1]<=$opts{MC_BL}->[1];
	my $block_count = 0;
	for( my $z=$opts{MC_BL}->[1]; $z<=$opts{MC_TR}->[1]; ++$z ) 
	{
		print STDERR $opts{MC_BL}->[0]."..".$opts{MC_TR}->[0].",".$z."\n";
		for( my $x=$opts{MC_BL}->[0]; $x<=$opts{MC_TR}->[0]; ++$x ) 
		{
#print "LOOP($x,$z)\n";
			my $e = $self->{offset_e} + $x;
			my $n = $self->{offset_n} - $z;
			my($lat,$long) = grid_to_ll( $e, $n, $self->{grid} );

			my $y = 2;
			my $el = 0;
			my $feature_height = 0;
			my $el2;
			my $dsm;
			my $dtm;
		
			if( $opts{ELEVATION} )
			{	
				$dsm = $opts{ELEVATION}->ll( "DSM", $lat, $long );
				$dtm = $opts{ELEVATION}->ll( "DTM", $lat, $long );
				$el = $dtm;
				$el = $dsm if( !defined $el );
				if( defined $dsm && defined $dtm )
				{
					$feature_height = int($dsm-$dtm);
				}
			}
			
			$y = $el+2;
		
			if( defined $opts{EXTEND_DOWNWARDS} )
			{
				$y += $opts{EXTEND_DOWNWARDS};
			}

			if( defined $opts{FLOOD} && $opts{FLOOD}>$el )
			{
				for( my $yi = $y+$opts{FLOOD}-$el; $yi>$y; $yi-- )
				{
					$self->{world}->set_block( $x, $yi, $z, 9 );
				}
			}

			my $block = 1;
			if( defined $opts{MAPTILES} )
			{
				$block = $opts{MAPTILES}->block_at( $lat,$long );
			}
			if( defined $opts{BLOCK} )
			{
				$block = $opts{BLOCK};
			}
			
			$self->{world}->set_block( $x, $y, $z, $block );
			if( defined $opts{EXTRUDE}->{$block} )
			{
				for( my $i=0; $i<@{$opts{EXTRUDE}->{$block}}; $i++ )
				{
					$self->{world}->set_block( $x, $y+1+$i, $z, $opts{EXTRUDE}->{$block}->[$i] );
				}
			}
			my $bottom=$y;
			if( defined $opts{EXTEND_DOWNWARDS} )
			{
				for( my $i=0; $i<$opts{EXTEND_DOWNWARDS}; $i++ )
				{
					$self->{world}->set_block( $x, $y-1-$i, $z, $block );
				}
				$bottom-=$opts{EXTEND_DOWNWARDS};
			}
			# put a dirt block under water and lava and other
			# blocks which need support
			if( $block==9 || $block==12 || $block==12.1 || $block==13 || $block==11 ) 
			{
				$self->{world}->set_block( $x, $bottom-1, $z, 3 );
			}

			# now look at difference between DTM and DSM

			my $up_block = $block;
			$up_block = "35.7";
			my $min = 3;
			my $fmap = {
				"3.1"=>[ 18, 0 ], #dirt
				"3"=>[ 18, 0 ], #dirt
				"2"=>[ 18, 0 ], #grass
				"45"=>[ 45, 0 ], #brick
				"98"=>[ 98, 0 ], #brick
				"8"=>[ 1, 10 ], # water
				"9"=>[ 1, 10 ], # water
			};
			if( $fmap->{$block} ) { 
				$up_block = $fmap->{$block}->[0];
				$min = $fmap->{$block}->[1];
			}
			if( $up_block eq "45" && $feature_height < 3 ) { $feature_height=3; } # buildings min height 3
			if( $up_block eq "98" && $feature_height < 3 ) { $feature_height=5; } # churches min height 5
			if( $feature_height >= $min )
			{
				for( my $up=1; $up<= $feature_height; ++$up )
				{
					$self->{world}->set_block( $x, $y+$up, $z, $up_block );
				}
				# top-off brick things in dark grey
				#$self->{world}->set_block( $x, $y+$feature_height, $z, "3" );
				if( $up_block eq "45" )
				{
					$self->{world}->set_block( $x, $y+$feature_height+1, $z, "171.8" );
				}
			}

			$block_count++;
			if( $block_count % (256*256) == 0 ) { $self->{world}->save(); }
		}
	}			
	$self->{world}->save(); 
}

1;
