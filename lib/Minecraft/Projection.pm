package Minecraft::Projection;

use Geo::Coordinates::OSGB;
use Math::Trig;
use Data::Dumper;
use Geo::Coordinates::OSTN02;
use JSON::PP;
use Carp;
use strict;
use warnings;

my $ZOOM = 18;
my $M_PER_PIX = 0.596;
my $TILE_W = 256;
my $TILE_H = 256;
my $SQUARE_SIZE = 512;

sub new
{
# change to setting an offset instead.
# change to take opts 
	my( $class, $world, $opts ) = @_;

	my $self = bless {},$class;
	$self->{world} = $world;
	$self->{opts} = $opts; # opts is the bit we save to disk

	return $self;
}

sub restore {
	my( $class, $world ) = @_;
	
	my $self = bless {},$class;
	$self->{world} = $world;
	$self->read_status;

	return $self;
}

sub read_status {
	my( $self ) = @_;

	my $filename = $self->{world}->{dir}."/map-maker-status.json";
	open( my $fh, "<:utf8", $filename ) || die "failed to open (for reading) $filename: $!";
	my $data = join("",<$fh>);
	close $fh;
  	$self->{opts} = decode_json( $data );
}

sub write_status {
	my( $self ) = @_;

	my $filename = $self->{world}->{dir}."/map-maker-status.json";
	open( my $fh, ">:utf8", $filename ) || die "failed to open (for writing) $filename: $!";
  	print $fh encode_json( $self->{opts} );
  	close $fh;
}

# returns absolute grid position, not minecraft position
sub ll_to_grid
{
	my( $self, $lat, $long ) = @_;
	# print "ll_to_grid($lat,$long)\n";

	my( $e, $n );

	if( defined $self->{opts}->{GRID} && $self->{opts}->{GRID} eq "MERC" )
	{
		# inverting north/south for some reason -- seems to work
		$e = ($long+180)/360 * 2**$ZOOM * ($TILE_W * $M_PER_PIX);	
		$n = -(1 - log(tan(deg2rad($lat)) + sec(deg2rad($lat)))/pi)/2 * 2**$ZOOM * ($TILE_H * $M_PER_PIX);
	}
	elsif( defined $self->{opts}->{GRID} && $self->{opts}->{GRID} eq "OSGB36" )
	{
		my ($x, $y) = Geo::Coordinates::OSGB::ll_to_grid($lat, $long, 'ETRS89'); # or 'WGS84'
		( $e,$n)= Geo::Coordinates::OSTN02::ETRS89_to_OSGB36($x, $y );
	#print "$lat,$long =$grid=> $e,$n\n";
	}
	else
	{
		( $e, $n ) =  Geo::Coordinates::OSGB::ll_to_grid( $lat,$long, $self->{opts}->{GRID} );
	}

	if( defined $self->{opts}->{ROTATE} && $self->{opts}->{ROTATE} != 0 ) 
	{
		my $ang = $self->{opts}->{ROTATE} * 2 * pi / 360;

		return( $e*cos($ang) - $n*sin($ang), $e*sin($ang) + $n*cos($ang) );
	}

	return( $e, $n );
}

sub grid_to_ll
{
	my( $self, $e, $n ) = @_;

	if( defined $self->{opts}->{ROTATE} && $self->{opts}->{ROTATE} != 0 ) 
	{
		my $ang = $self->{opts}->{ROTATE} * 2 * pi / 360;
		($e, $n) = ( $e*cos(-$ang) - $n*sin(-$ang), $e*sin(-$ang) + $n*cos(-$ang) );
	}

	if( defined $self->{opts}->{GRID} && $self->{opts}->{GRID} eq "MERC" )
	{
		my $lat = rad2deg(atan(sinh( pi - (2 * pi * -$n / (2**$ZOOM * ($TILE_H * $M_PER_PIX))) )));
		my $long = (($e / ($TILE_W * $M_PER_PIX)) / 2**$ZOOM)*360-180;
		return( $lat, $long );
	}
	if( defined $self->{opts}->{GRID} && $self->{opts}->{GRID} eq "OSGB36" )
	{
		my( $x,$y)= Geo::Coordinates::OSTN02::OSGB36_to_ETRS89($e, $n );
		return Geo::Coordinates::OSGB::grid_to_ll($x, $y, 'ETRS89'); # or 'WGS84'
	}


	return Geo::Coordinates::OSGB::grid_to_ll( $e,$n, $self->{opts}->{GRID} );
}





# more mc_x : more easting
# more mc_y : less northing

sub add_point_ll
{
	my( $self, $lat,$long, $label, $beam_colour ) = @_;

	my( $e, $n ) = $self->ll_to_grid( $lat,$long );

	$self->add_point_en( $e, $n, $label, $beam_colour );
}

sub add_point_en 
{
	my( $self, $e,$n, $label, $beam_colour ) = @_;

	my $actual_x = $e - $self->{opts}->{OFFSET_E};
	my $actual_z = -$n + $self->{opts}->{OFFSET_N};

	# can't cope with scale being set as it's given to render. It should belong to projection, like rotate does.	
#	if( $opts{SCALE} ) {
#		$transformed_x = $transformed_x / $opts{SCALE};
#		$transformed_z = $transformed_z / $opts{SCALE};
#	}

	$self->add_point( $actual_x,$actual_z, $label, $beam_colour );
}

sub add_point
{
	my( $self, $x,$z, $label, $beam_colour ) = @_;

	$x = int $x;
	$z = int $z; 

	if( !defined $self->{opts}->{POINTS}->{$z}->{$x} ) {
		$self->{opts}->{POINTS}->{$z}->{$x} = [];
	}

	if( defined $beam_colour && $beam_colour eq "STONE" ) {
		push @{$self->{opts}->{POINTS}->{$z}->{$x}}, { type=>"standing-stone", status=>"todo" };
		return; # don't add a sign
	}
	push @{$self->{opts}->{POINTS}->{$z}->{$x}}, { type=>"sign", label=>$label, status=>"todo" };

	if( defined $beam_colour && $beam_colour eq "STONE" ) {
		# add a beacon too if beam_colour is set. Make the beam one to the north
		push @{$self->{opts}->{POINTS}->{$z-2}->{$x-1}}, { type=>"beacon-base", status=>"todo" };
		push @{$self->{opts}->{POINTS}->{$z-2}->{$x  }}, { type=>"beacon-base", status=>"todo" };
		push @{$self->{opts}->{POINTS}->{$z-2}->{$x+1}}, { type=>"beacon-base", status=>"todo" };
		push @{$self->{opts}->{POINTS}->{$z-1}->{$x-1}}, { type=>"beacon-base", status=>"todo" };
		push @{$self->{opts}->{POINTS}->{$z-1}->{$x  }}, { type=>"beacon", beam_colour=>$beam_colour, status=>"todo" };
		push @{$self->{opts}->{POINTS}->{$z-1}->{$x+1}}, { type=>"beacon-base", status=>"todo" };
		push @{$self->{opts}->{POINTS}->{$z  }->{$x-1}}, { type=>"beacon-base", status=>"todo" };
		push @{$self->{opts}->{POINTS}->{$z  }->{$x  }}, { type=>"beacon-base", status=>"todo" };
		push @{$self->{opts}->{POINTS}->{$z  }->{$x+1}}, { type=>"beacon-base", status=>"todo" };
	}
	
}
		
	
	


sub context 
{
	my( $self, $x, $z, %opts ) = @_;

	my( $transformed_x, $transformed_z ) = ( $x,$z );
	if( $opts{SCALE} ) {
		$transformed_x = $transformed_x / $opts{SCALE};
		$transformed_z = $transformed_z / $opts{SCALE};
	}
	
	my $e = $self->{opts}->{OFFSET_E} + $transformed_x;
	my $n = $self->{opts}->{OFFSET_N} - $transformed_z;

	my($lat,$long) = $self->grid_to_ll( $e, $n );

	my $el = 0;
	my $feature_height = 0;

	my $dsm = $self->elevation->ll( "DSM", $lat, $long );
	my $dtm = $self->elevation->ll( "DTM", $lat, $long );
	my $dsm_available = 1;
	my $dtm_available = 1;
	if( !defined $dtm ) {
		$dtm_available = 0;
		$dtm = 0;
		$dsm = 0;
	}
	if( !defined $dsm ) {
		$dsm_available = 0;
		$dtm = 0;
		$dsm = 0;
	}
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
	
	my $block = "DEFAULT"; # default to stone
	if( defined $self->{maptiles} )
	{
		$block = $self->{maptiles}->block_at( $lat,$long );
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
		dsm_available => $dsm_available,
		dtm_available => $dtm_available,
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

sub configure
{
	my( $self, %opts ) = @_;

	die "missing coords EAST1"  if( !defined $opts{EAST1} );
	die "missing coords EAST2"  if( !defined $opts{EAST2} );
	die "missing coords NORTH1" if( !defined $opts{NORTH1} );
	die "missing coords NORTH2" if( !defined $opts{NORTH2} );

	$self->{opts} = \%opts;

	( $self->{opts}->{WEST}, $self->{opts}->{EAST} )  = ( $self->{opts}{EAST1}, $self->{opts}{EAST2} );
	( $self->{opts}->{SOUTH},$self->{opts}->{NORTH} ) = ( $self->{opts}{NORTH1},$self->{opts}{NORTH2} );

	if( $self->{opts}->{EAST} < $self->{opts}->{WEST} ) { ( $self->{opts}->{EAST},$self->{opts}->{WEST} ) = ( $self->{opts}->{WEST},$self->{opts}->{EAST} ); }
	if( $self->{opts}->{NORTH} < $self->{opts}->{SOUTH} ) { ( $self->{opts}->{NORTH},$self->{opts}->{SOUTH} ) = ( $self->{opts}->{SOUTH},$self->{opts}->{NORTH} ); }

	$self->elevation();
	if( $self->{elevation} && defined $self->{opts}->{SCALE} && $self->{opts}->{SCALE}>1 )
	{	
		my($lat,$long) = $self->grid_to_ll( $self->{opts}->{OFFSET_E}, $self->{opts}->{OFFSET_N} );
		my $dtm = $self->elevation->ll( "DTM", $lat, $long );
		$self->{opts}->{YSHIFT} -= $dtm * ( $self->{opts}->{SCALE}-1 );
	}

	$self->{opts}->{SEA_LEVEL} = 2;
	if( $self->{opts}->{EXTEND_DOWNWARDS} )
	{	
		$self->{opts}->{SEA_LEVEL}+=$self->{opts}->{EXTEND_DOWNWARDS};
	}
	if( $self->{opts}->{YSHIFT} )
	{	
		$self->{opts}->{SEA_LEVEL}+=$self->{opts}->{YSHIFT};
	}

	
	$self->{opts}->{REGIONS} = {};
	for( my $z=$self->{opts}->{SOUTH}-($self->{opts}->{SOUTH} % $SQUARE_SIZE); $z<$self->{opts}->{NORTH}; $z+=$SQUARE_SIZE ) 
	{
		for( my $x=$self->{opts}->{WEST}-($self->{opts}->{WEST} % $SQUARE_SIZE); $x<$self->{opts}->{EAST}; $x+=$SQUARE_SIZE )
		{
			$self->{opts}->{REGIONS}->{"$x,$z"} = {x=>$x, z=>$z, status=>"todo"};
		}
	}

	# save config
	$self->write_status;
}


sub elevation {
	my( $self ) = @_;

	if( !defined $self->{elevation} ) {
		my $elevation_class = "Elevation::".$self->{opts}->{ELEVATION_PLUGIN};
		my $rc = eval "use $elevation_class; 1;";
		if( !$rc ) {
			die "Error in loading elevation; $@";
		}
		$self->{elevation} = $elevation_class->new( 
			"$FindBin::Bin/var/lidar", 
			"$FindBin::Bin/var/tmp", 
		);
	}
	return $self->{elevation};
}

sub continue {
	my( $self ) = @_;

	# set autoflush to show every dot as it appears.
	my $old_fh = select(STDOUT);
	$| = 1;
	select($old_fh); 

	if( 0 ) {
		$self->{maptiles} = new Minecraft::MapTiles(
			zoom=>$self->{opts}->{MAP_ZOOM},
			spread=>3,
			width=>256,
			height=>256,
			dir=>"$FindBin::Bin/var/tiles", 
			url=>"http://b.tile.openstreetmap.org/",
			default_block=>"DEFAULT",
			colours_file=>$self->{opts}->{COLOURS_FILE},
		);
	} else {
		
		$self->{maptiles} = new Minecraft::VectorMap();
	}
	

	Minecraft::Config::load_config( $self->{opts}->{BLOCKS_FILE} );
	 
	$self->{blocks_config} = {};
	foreach my $id ( keys %{$Minecraft::Config::BLOCKS} )
	{
		my %default = %{$Minecraft::Config::BLOCKS->{DEFAULT}};
		$self->{blocks_config}->{$id} = \%default;
		bless $self->{blocks_config}->{$id}, "Minecraft::Projection::BlockConfig";
		foreach my $field ( keys %{$Minecraft::Config::BLOCKS->{$id}} )
		{
			$self->{blocks_config}->{$id}->{$field} = $Minecraft::Config::BLOCKS->{$id}->{$field};
		}	
	}

	# do square
	my @todo = ();
	my $xt=0;
	my $zt=0;
	foreach my $k ( keys %{$self->{opts}->{REGIONS}} ) {
		my $region = $self->{opts}->{REGIONS}->{$k};
		if( !defined $region->{status} || $region->{status} eq "todo" ) {
			push @todo, $k; 
			$xt += $self->{opts}->{REGIONS}->{$k}->{x};
			$zt += $self->{opts}->{REGIONS}->{$k}->{z};
		}
	}	

	if( scalar @todo == 0 ) {
		print "Nothing to do\n";
		return;
	}
	
	my $xmid = $xt/(scalar @todo);
	my $zmid = $zt/(scalar @todo);

	@todo = sort {
		my $ra = $self->{opts}->{REGIONS}->{$a};
		my $rb = $self->{opts}->{REGIONS}->{$b};
		my $ad = ($ra->{x}-$xmid)*($ra->{x}-$xmid) + ($ra->{z}-$zmid)*($ra->{z}-$zmid);
		my $bd = ($rb->{x}-$xmid)*($rb->{x}-$xmid) + ($rb->{z}-$zmid)*($rb->{z}-$zmid);
		return $ad <=> $bd;
	} @todo;

#			$self->{opts}->{REGIONS}->{"$x,$z"} = {x=>$x, z=>$z, status=>"todo"};
	my $todo_at_start_count = scalar @todo;
	while( scalar @todo ) {
		my $region_id = shift @todo;



		my $region_info = $self->{opts}->{REGIONS}->{$region_id};
		if( !defined $region_info ) {
			print Dumper( $self->{opts}->{REGIONS} );
			die "Failed to load $region_id";
		}
		$self->{maptiles}->init_region( 
			$region_info->{x}+$self->{opts}->{OFFSET_E},
			-$region_info->{z}+$self->{opts}->{OFFSET_N},
			$SQUARE_SIZE,
			$self );
			
		my $start_t = time();
		my $info = sprintf( "Region #%d areas of %d of %dx%d at %d,%d: ",
			$todo_at_start_count-scalar @todo,
			$todo_at_start_count,
			${SQUARE_SIZE},
			${SQUARE_SIZE},
		       	$region_info->{x},
			$region_info->{z} );

		# Main loop over the region
		my $min_z = $region_info->{z};
		$min_z = $self->{opts}->{SOUTH} if( $self->{opts}->{SOUTH} > $min_z );
		my $max_z = $region_info->{z}+$SQUARE_SIZE-1;
		$max_z = $self->{opts}->{NORTH} if( $self->{opts}->{NORTH} < $max_z );
		print "\n"; # prep a line to report to.
		for( my $z=$min_z; $z<=$max_z; ++$z ) {
			my $ratio = ($z-$min_z)/($max_z-$min_z);
			print sprintf( "\r%s %d%% ",$info,$ratio*100);
			for( my $x=$region_info->{x}; $x<$region_info->{x}+$SQUARE_SIZE; ++$x ) {
				next if( $x<$self->{opts}->{WEST} || $x>$self->{opts}->{EAST} );
				$self->render_xz( $x,$z );
			}
		}		
		print " (".(time()-$start_t)." seconds)";
		print "\n";
		$self->{world}->save(); 
		$self->{world}->uncache(); 
		if( $self->{opts}->{WEST} <= $region_info->{x} 
		 && $self->{opts}->{EAST} >= $region_info->{x}+$SQUARE_SIZE-1 
		 && $self->{opts}->{NORTH} <= $region_info->{z}
		 && $self->{opts}->{SOUTH} >= $region_info->{z}+$SQUARE_SIZE-1 ) {
			$region_info->{status} = "partial";
		} else {
			$region_info->{status} = "complete";
		}
		$region_info->{timestamp} = time();
		$self->write_status;
	}

}

my $TYPE_DEFAULT = {
DEFAULT=>1,
GRASS=>2,
LAWN=>2,
WETLAND=>2,
HEATH=>2,
WOOD=>2,
CHURCH=>98,
BUILDING=>45,
WATER=>9,
ROAD=>159.07,
PATH=>1.01,
FANCYROAD=>251.15,
TRACK=>3.01,
PAVEMENT=>159.07,
ALLOTMENT=>3.01,
SAND=>12,
CARPARK=>159.08,
AREA1=>1,
AREA2=>1,
AREA3=>1,
AREA4=>1,
AREA5=>1,
AREA6=>1,
AREA7=>1,
RETAIL=>1,
BUILDING_WHITE=>1,
BUILDING_BLACK=>1,
BUILDING_BROWN=>1,
BUILDING_GREY=>1,
BUILDING_SANDSTONE=>1,
INDUSTRIAL=>1,
SHED=>1,
};

sub render_xz
{
	my( $self, $x,$z ) = @_;

	my $context = $self->context( $x, $z );
	my $block = $context->{block};
	my $el = int $context->{elevation};
	my $feature_height = int $context->{feature_height};

	# we now have $block, $el, $SEA_LEVEL and $feature_height
	# that's enough to work out what to place at this location

	# config options based on value of block

	my $bc = $self->{blocks_config}->{$block};
	$bc = $self->{blocks_config}->{DEFAULT} if !defined $bc;
	if( !defined $bc) { die "No DEFAULT block"; }

	if( $bc->{look_around} ) {
		my $dirmap = {
			north=>{ x=>0, z=>-1 },
			south=>{ x=>0, z=>1 },
			west=>{ x=>-1, z=>0 },
			east=>{ x=>1, z=>0 },
		};
		foreach my $dir ( qw/ north south east west / ) { 
			$context->{$dir} = $self->context( $x+$dirmap->{$dir}->{x}, $z+$dirmap->{$dir}->{z}, %{$self->{opts}} );
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
	my $default = $TYPE_DEFAULT->{$block};
	if( !defined $default ) { confess "unknown block: $block"; }
	$blocks->{0} = $bc->val( $context, "block", $default );

	my $bottom=0;
	if( defined $self->{opts}->{EXTEND_DOWNWARDS} )
	{
		for( my $i=1; $i<=$self->{opts}->{EXTEND_DOWNWARDS}; $i++ )
		{
			$context->{y_offset} = -$i;
			$blocks->{-$i} = $bc->val( $context, "down_block", $blocks->{0} );
		}
		$bottom-=$self->{opts}->{EXTEND_DOWNWARDS};
	}

	delete $context->{y_offset};
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
			my $light = $bc->val( $context, "light" );
			if( defined $light ) {
				print "$light\n";
			}
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

	if( $self->{opts}->{FLOOD} )
	{
		for( my $i=1; $i<=$self->{opts}->{FLOOD}; $i++ )
		{
			$context->{y_offset} = $i; # not currently used
			my $block_el = $el+$i;
			if( $el+$i <= $self->{opts}->{FLOOD} && (!defined $blocks->{$i} || $blocks->{$i}==0 ))
			{
				$blocks->{$i} = 9; # water, obvs.
			}
		}	
	}

	my $maxy = -1;
	foreach my $offset ( sort keys %$blocks )
	{
		my $y = $self->{opts}->{SEA_LEVEL}+$offset;
		$y+=$el if( !$self->{opts}->{FLATLAND} );
		next if( $y>$self->{opts}->{TOP_OF_WORLD} );
		$self->{world}->set_block( $x, $y, $z, $blocks->{$offset} );
		$maxy=$y if( $y>$maxy );
	}


	if( defined $self->{opts}->{POINTS}->{$z} && defined $self->{opts}->{POINTS}->{$z}->{$x} ) {
		foreach my $point ( @{$self->{opts}->{POINTS}->{$z}->{$x}} ) {
			if( $maxy+2< $self->{opts}->{TOP_OF_WORLD} ) {
				if( $point->{type} eq "beacon" ) {
					# 95.x
					# turn non air blocks into glass
					for( my $y = 1; $y<=$maxy; $y++ ) {
						my $block = $self->{world}->get_block( $x, $y, $z );
						if( $block != 0 ) {
							$self->{world}->set_block( $x, $y, $z, "95.".$point->{beam_colour} );
						}
					}
					# make a beacon
					$self->{world}->add_beacon( $x, 2, $z );
					$self->{world}->set_block( $x, 1, $z, 57 );
				}
				if( $point->{type} eq "beacon" || $point->{type} eq "beacon-base" ) {
					$self->{world}->set_block( $x, 1, $z, 57 );
				} 
				if( $point->{type} eq "standing-stone" ) {
					$self->{world}->set_block( $x, $maxy+1, $z, 1 );
					$self->{world}->set_block( $x, $maxy+2, $z, 1 );
					$self->{world}->set_block( $x, $maxy+3, $z, 1 );
					$maxy+=3;
				}
				if( $point->{type} eq "sign" ) {
					# simple signpost
					my $stand_y = $maxy; 
					my $sign_y = $maxy+1; 
					$maxy+=1;

					
					# turn the top world block to wood UNLESS it's a signpost in which case the block above the signpost
					my $stand_type =  $self->{world}->get_block( $x,$stand_y,$z );
					$stand_type =~ s/\..*$//; # remove subtype
					# types used in this app that can't have a sign on top
					# 0 air
					# 18 leaves
					# 31 plants
					# 8,9 Water
					# 10,11 Lava
					# 63 Sign
					# 171 carpet
					# 78 snow
					if( $stand_type =~ m/^(0|18|31|8|9|10|11|63|171|78)$/ ) {
						$stand_y+=1;
						$sign_y+=1;
						$maxy+=1;
						$self->{world}->set_block( $x,$stand_y,$z, 5 ); # wood for it to stand on
					}
					
					my $text = $point->{label};
					$self->{world}->add_sign( $x,$sign_y,$z, $text );
				}

				$point->{status} = "done";
			}
		}
	}

	my $biome = $bc->val( $context,"biome");
	if( defined $biome ) { $self->{world}->set_biome( $x,$z, $biome ); }
}




1;
