package Minecraft::Projection;

use Geo::Coordinates::OSGB qw(ll_to_grid grid_to_ll);

sub new_from_ll
{
	my( $class, $world, $mc_ref_x,$mc_ref_z, $lat,$long, $grid ) = @_;
	
	my( $e, $n ) = ll_to_grid( $lat,$long, $grid);
	return $class->new( $world, $mc_ref_x,$mc_ref_z,  $e,$n,  $grid );
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
	# ELEVATION_DIR = dir
	# ELEVATION_CORRECT = [x,z]
	#my( $mc_ref_x,$mc_ref_z,  $e_ref,$n_ref,  $mc_x1,$mc_z1,  $mc_x2,$mc_z2 ) = @_;

	die "x2<=x1" if $opts{MC_TR}->[0]<=$opts{MC_BL}->[0];
	die "z2<=z1" if $opts{MC_TR}->[1]<=$opts{MC_BL}->[1];

	for( my $z=$opts{MC_BL}->[1]; $z<=$opts{MC_TR}->[1]; ++$z ) 
	{
		print STDERR $opts{MC_BL}->[0]."..".$opts{MC_TR}->[0].",".$z."\n";
		for( my $x=$opts{MC_BL}->[1]; $x<=$opts{MC_TR}->[1]; ++$x ) 
		{
			my $e = $self->{offset_e} + $x;
			my $n = $self->{offset_n} - $z;
			my($lat,$long) = grid_to_ll( $e, $n, $self->{grid} );

			my $y = 10;
			if( defined $opts{ELEVATION} )
			{
				$y = 5+POSIX::floor($opts{ELEVATION}->ll( $lat, $long )) 
			}

			my $block = 1;
			if( defined $opts{MAPTILES} )
			{
				$block = $opts{MAPTILES}->block_at( $lat,$long );
			}
			$self->{world}->set_block( $x, $y, $z, $block );
		}
	}			
}

1;
