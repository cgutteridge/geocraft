package Minecraft::Projection;

use Geo::Coordinates::OSGB;
use Math::Trig;
use strict;
use warnings;

sub new_from_ll
{
	my( $class, $world, $mc_ref_x,$mc_ref_z, $lat,$long, $grid ) = @_;

	my( $e, $n ) = ll_to_grid( $lat,$long, $grid );

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

	return Geo::Coordinates::OSGB::ll_to_grid( $lat,$long, $grid );
}
sub grid_to_ll
{
	my( $e, $n, $grid ) = @_;
	#print "grid_to_ll($e,$n)\n";
	if( defined $grid && $grid eq "MERC" )
	{
		my $lat = rad2deg(atan(sinh( pi - (2 * pi * -$n / (2**$ZOOM * ($TILE_H * $M_PER_PIX))) )));
		my $long = (($e / ($TILE_W * $M_PER_PIX)) / 2**$ZOOM)*360-180;
		return( $lat, $long );
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
			my $el;
			if( defined $opts{ELEVATION} )
			{
				$el = POSIX::floor($opts{ELEVATION}->ll( $lat, $long ));
				$y = $el+2;
			}
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
			if( defined $opts{EXTEND_DOWNWARDS} )
			{
				for( my $i=0; $i<$opts{EXTEND_DOWNWARDS}; $i++ )
				{
					$self->{world}->set_block( $x, $y-1-$i, $z, $block );
				}
				$y-=$opts{EXTEND_DOWNWARDS};
			}
			if( $block==9 || $block==12 || $block==12.1 || $block==13 || $block==11 ) # water
			{
				$self->{world}->set_block( $x, $y-1, $z, 3 );
			}



			$block_count++;
			if( $block_count % (256*256) == 0 ) { $self->{world}->save(); }
		}
	}			
	$self->{world}->save(); 
}

1;
