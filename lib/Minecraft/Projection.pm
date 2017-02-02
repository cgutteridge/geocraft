package Minecraft::Projection;

use Geo::Coordinates::OSGB;
use Math::Trig;
use Data::Dumper;
use Minecraft::Context;
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
	#print "$lat,$long =$grid=> $e,$n\n";
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


sub context 
{
	my( $self, $x, $z, %opts ) = @_;

	my( $transformed_x, $transformed_z ) = ( $x,$z );
	if( $opts{SCALE} ) {
		$transformed_x = $transformed_x / $opts{SCALE};
		$transformed_z = $transformed_z / $opts{SCALE};
	}
	
	my $e = $self->{offset_e} + $transformed_x;
	my $n = $self->{offset_n} - $transformed_z;

	my($lat,$long) = grid_to_ll( $e, $n, $self->{grid} );

	my $el = 0;
	my $feature_height = 0;

	if( $opts{ELEVATION} )
	{	
		my $dsm = $opts{ELEVATION}->ll( "DSM", $lat, $long );
		my $dtm = $opts{ELEVATION}->ll( "DTM", $lat, $long );
		if( defined $dsm && defined $opts{SCALE} )
		{
			$dsm = $dsm * $opts{SCALE};
		}
		if( defined $dtm && defined $opts{SCALE} )
		{
			$dtm = $dtm * $opts{SCALE};
		}
		$el = $dtm;
		$el = $dsm if( !defined $el );
		if( defined $dsm && defined $dtm )
		{
			$feature_height = int($dsm-$dtm);
		}
	}
	
	my $block = 1; # default to stone
	if( defined $opts{MAPTILES} )
	{
		$block = $opts{MAPTILES}->block_at( $lat,$long );
	}
	if( defined $opts{BLOCK} )
	{
		$block = $opts{BLOCK};
	}
	return bless {
		block => $block,
		elevation => $el,
		feature_height => $feature_height,
		easting => $e,
		northing => $n,
		lat => $lat,
		long => $long,
		x => $x,
		z => $z,
	}, "Minecraft::Context";
}

sub duration
{
	my( $s ) = @_;

	$s = int $s;

	my $seconds = $s % 60;
	$s -= $seconds;
	
	my $m = ($s / 60);
	my $minutes = $m % 60;
	$m -= $minutes;

	my $hours = ($m / 60);

	return sprintf( "%d:%02d:%02d", $hours,$minutes,$seconds );
}

sub render
{
	my( $self, %opts ) = @_;

	die "missing coords EAST1"  if( !defined $opts{EAST1} );
	die "missing coords EAST2"  if( !defined $opts{EAST2} );
	die "missing coords NORTH1" if( !defined $opts{NORTH1} );
	die "missing coords NORTH2" if( !defined $opts{NORTH2} );

	my( $WEST, $EAST )  = ( $opts{EAST1}, $opts{EAST2} );
	my( $SOUTH,$NORTH ) = ( $opts{NORTH1},$opts{NORTH2} );

	if( $EAST < $WEST ) { ( $EAST,$WEST ) = ( $WEST,$EAST ); }
	if( $NORTH < $SOUTH ) { ( $NORTH,$SOUTH ) = ( $SOUTH,$NORTH ); }

	if( $opts{ELEVATION} && defined $opts{SCALE} && $opts{SCALE}>1 )
	{	
		my($lat,$long) = grid_to_ll( $self->{offset_e}, $self->{offset_n}, $self->{grid});
		my $dtm = $opts{ELEVATION}->ll( "DTM", $lat, $long );
		$opts{YSHIFT} -= $dtm * ( $opts{SCALE}-1 );
	}



	my $SEALEVEL = 2;
	if( $opts{EXTEND_DOWNWARDS} )
	{	
		$SEALEVEL+=$opts{EXTEND_DOWNWARDS};
	}
	if( $opts{YSHIFT} )
	{	
		$SEALEVEL+=$opts{YSHIFT};
	}

	$self->{start} = time();
	my $BCONFIG = {};
	foreach my $id ( keys %{$opts{BLOCKS}} )
	{
		my %default = %{$opts{BLOCKS}->{DEFAULT}};
		$BCONFIG->{$id} = \%default;
		bless $BCONFIG->{$id}, "Minecraft::Projection::BlockConfig";
		foreach my $field ( keys %{$opts{BLOCKS}->{$id}} )
		{
			$BCONFIG->{$id}->{$field} = $opts{BLOCKS}->{$id}->{$field};
		}	
	}

	my $block_count = 0;
	for( my $z=$SOUTH; $z<=$NORTH; ++$z ) 
	{
		my $ratio = ($z-$SOUTH)/($NORTH-$SOUTH+1);
		my $spent = time()-$self->{start};
		
		print sprintf( "ROW: %d..%dE,%dN", $WEST,$EAST,$z );
		if( $ratio > 0 && $ratio < 1 )
		{
			my $remaining = $spent / $ratio * (1-$ratio);
			print sprintf( ".. %d%% %s remaining", int(100*$ratio), duration( $remaining ) );
		}
		print "\n";
		for( my $x=$WEST; $x<=$EAST; ++$x )
		{
			my $context = $self->context( $x, $z, %opts );
			my $block = $context->{block};
			my $el = $context->{elevation};
			my $feature_height = $context->{feature_height};
		
			# we now have $block, $el, $SEALEVEL and $feature_height
			# that's enough to work out what to place at this location

			# config options based on value of block

			my $bc = $BCONFIG->{$block};
			$bc = $BCONFIG->{DEFAULT} if !defined $bc;
			if( !defined $bc) { die "No DEFAULT block"; }

			if( $bc->{look_around} ) {
				my $dirmap = {
					north=>{ x=>0, z=>-1 },
					south=>{ x=>0, z=>1 },
					west=>{ x=>-1, z=>0 },
					east=>{ x=>1, z=>0 },
				};
				foreach my $dir ( qw/ north south east west / ) { 
					$context->{$dir} = $self->context( $x+$dirmap->{$dir}->{x}, $z+$dirmap->{$dir}->{z}, %opts );
				}
			}


			# block : blocktype [ block ID or "DEFAULT" ]
			# down_block: blocktype [ block ID or "DEFAULT" ]
			# up_block: blocktype [ block ID or "DEFAULT" ]
			# bottom_block: blocktype [ block ID or "DEFAULT" ]
			# under_block: blocktype [ block ID or "DEFAULT" ]
			# top_block: blocktype [ block ID or "DEFAULT" ]
			# over_block: blocktype [ block ID or "DEFAULT" ]
			# feature_filter - filter features of this height or less
			# feature_min_height - force this min feature height even if lidar is lower

			my $blocks = {};
			$blocks->{0} = $bc->val( $context, "block", $block );

			my $bottom=0;
			if( defined $opts{EXTEND_DOWNWARDS} )
			{
				for( my $i=1; $i<=$opts{EXTEND_DOWNWARDS}; $i++ )
				{
					$blocks->{-$i} = $bc->val( $context, "down_block", $blocks->{0} );
				}
				$bottom-=$opts{EXTEND_DOWNWARDS};
			}

			my $top = 0;
			my $fmh = $bc->val( $context, "feature_min_height" );
			if( defined $fmh && $fmh>$feature_height )
			{
				$feature_height = $fmh;
			}	
			my $ff = $bc->val( $context, "feature_filter" );
			if( !defined $ff || $feature_height > $ff )
			{
				for( my $i=1; $i<= $feature_height; ++$i )
				{
					$context->{y_offset} = $i;
					$blocks->{$i} = $bc->val( $context, "up_block", $blocks->{0} );
				}
				$top+=$feature_height;
			}

			my $v;

			$context->{y_offset} = $bottom;
			$v = $bc->val( $context,"bottom_block"); 
			if( defined $v ) { $blocks->{$bottom} = $v; }

			$context->{y_offset} = $bottom-1;
			$v = $bc->val( $context,"under_block"); 
			if( defined $v ) { $blocks->{$bottom-1} = $v; }

			$context->{y_offset} = $top;
			$v = $bc->val( $context,"top_block"); 
			if( defined $v ) { $blocks->{$top} = $v; }

			$context->{y_offset} = $top+1;
			$v = $bc->val( $context,"over_block"); 
			if( defined $v ) { $blocks->{$top+1} = $v; }

			if( $opts{FLOOD} )
			{
				for( my $i=1; $i<=$opts{FLOOD}; $i++ )
				{
					$context->{y_offset} = $i; # not currently used
					my $block_el = $el+$i;
					if( $el+$i <= $opts{FLOOD} && (!defined $blocks->{$i} || $blocks->{$i}==0 ))
					{
						$blocks->{$i} = 9; # water, obvs.
					}
				}	
			}
#print Dumper( $bc, $blocks );
#print "...\n";
			foreach my $offset ( sort keys %$blocks )
			{
				my $y = $SEALEVEL+$offset;
				$y+=$el if( !$opts{FLATLAND} );
				next if( $y>$opts{TOP_OF_WORLD} );
				$self->{world}->set_block( $x, $y, $z, $blocks->{$offset} );
			}

			my $biome = $bc->val( $context,"biome");
			if( defined $biome ) { $self->{world}->set_biome( $x,$z, $biome ); }
	
			$block_count++;
			if( $block_count % (256*256) == 0 ) { $self->{world}->save(); }
		}
	}			
	$self->{world}->save(); 
}

package Minecraft::Projection::BlockConfig;
use strict;
use warnings;

sub val
{
	my( $self, $context, $term, $default ) = @_;

	my $v = $self->{$term};
	$v=$default if( !defined $v );
	return unless defined $v;

	if( ref($v) eq "CODE" )
	{
		$v = &$v( $context );
	}

	return $v;
}


1;
