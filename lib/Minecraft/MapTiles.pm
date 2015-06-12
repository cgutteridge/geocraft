package Minecraft::MapTiles;

use Image::Magick;
use Math::Trig;

sub new
{
	my( $class, %opts ) = @_;

	my $self = bless { %opts },$class;
	$self->{failcols} = 0;	
	$self->{tiles} = {};	

	return $self;
}
#	zoom=>19,
#	spread=>4,
#	width=>256,
#	height=>256,
#	dir=>"$FindBin::Bin/tiles", 
#	url=>"http://b.tile.openstreetmap.org/",

sub getTileNumber 
{
	my ($lat,$lon,$zoom) = @_;
	my $xtile = ($lon+180)/360 * 2**$zoom ;
	my $ytile = (1 - log(tan(deg2rad($lat)) + sec(deg2rad($lat)))/pi)/2 * 2**$zoom ;
	return (int($xtile), int($ytile), $xtile-int($xtile), $ytile-int($ytile));
}
sub block_at
{
	my( $self, $lat, $long ) = @_;
	
	my( $xtile,$ytile, $xr,$yr ) = getTileNumber( $lat,$long, $self->{zoom} );
	
	my $tile = $self->{zoom}."_${xtile}_${ytile}.png";

	if( !defined $self->{tiles}->{$tile} )
	{
		if( !-e "$self->{dir}/$tile" )
		{
			my $cmd = "curl '".$self->{url}.$self->{zoom}."/$xtile/$ytile.png' > ".$self->{dir}."/$tile";
			print "$cmd\n";
			`$cmd`;
		}
		$self->{tiles}->{$tile} = new Image::Magick;
		$self->{tiles}->{$tile}->Read( $self->{dir}."/$tile" );
	}

	return 1;
}


1;	
__DATA__
	
	
			my $pixel_x = POSIX::floor($tile_width*$xr);
			my $pixel_y = POSIX::floor($tile_height*$yr);
	
			my $scores = {};
			my $best = "FAIL";
			my $max = 0;
			my $midcol="eh";
			for( my $yy=-$SPREAD; $yy<=$SPREAD; ++$yy ) {
				X: for( my $xx=-$SPREAD; $xx<=$SPREAD; ++$xx ) {
					my $p_x = $pixel_x+$xx;
					my $p_y = $pixel_y+$yy;
					next if( $p_x<0 || $p_x>=$tile_width );
					next if( $p_y<0 || $p_y>=$tile_height );
					my @pixel = $tiles->{$tile}->GetPixel(x=>$p_x,y=>$p_y);
					my $col = int( $pixel[0]*100 ).":".int( $pixel[1]*100 ).":".int($pixel[2]*100);
					if( $xx==0 && $yy==0 ) { $midcol=$col;}
					#if( $x==30 && $y==23 ) { print "$xx,$yy : $col\n"; }
					#next X if( $X::skip->{$col} );
					next X if( !$X::map->{$col} );
	
					$scores->{$col}++;
					if( $scores->{$col} > $max )
					{
						$max = $scores->{$col};
						$best = $col;
					}
				}
			}
			my $underblock = 3;
			my $block = 57;
$block =1; #nicer default blocks
			if( $X::map->{$best} ) { $block = $X::map->{$best}; }
	
			my($lat1,$long1) = grid_to_ll( $e, $n );

			$mc_y = 5+POSIX::floor($elevation->ll( $lat, $long )) if $elevation;
	
			$failcols->{$midcol}++ if( $block == 57 );
			$underblock = 3 if $block==9;

#print "$mc_x,$mc_z: $block\n";
#print ":: mcoffx=$mc_x_offset w=$width - x=$x -1\n";
#print ":: mcoffz=$mc_z_offset h=$height - y=$y -1\n";
			$world->set_block( $mc_x, $mc_y-1, $mc_z, $underblock );
			$world->set_block( $mc_x, $mc_y, $mc_z, $block );

		}
	}
	$world->save;
}
	




#my $TREE_FILE = "$FindBin::Bin/trees.tsv";
#	my $trees = {};
#	open( my $tfh, "<", $TREE_FILE ) || die "can't treeread: $!";
#	while( my $line = <$tfh> )
#	{
#		chomp $line;
#		my( $lat, $long ) = split( /\t/,$line );
#		my( $e,$n ) = ll_to_grid( $lat,$long );
#		$trees->{POSIX::floor($n)}->{POSIX::floor($e)} = 1;
#	}

			elsif( $OPTS->{TREE} && $trees->{$n}->{$e} )
			{
	print "TREE!\n";
				my $TREESIZE=4;
				my $TRUNKSIZE=4;
				for( my $xx=-$TREESIZE;$xx<=$TREESIZE;++$xx ){
					for( my $yy=-$TREESIZE;$yy<=$TREESIZE;++$yy ){
						ZZ: for( my $zz=-$TREESIZE;$zz<=$TREESIZE;++$zz ){
							next ZZ if( abs($xx)+abs($yy)+abs($zz)>$TREESIZE );
							$world->set_block( $mc_x+$xx,$mc_y+$TRUNKSIZE+$TREESIZE+$yy,$mc_z+$zz, 18);
						}
					}
				}
				for( my $i=0;$i<$TRUNKSIZE+$TREESIZE;++$i )
				{
					$world->set_block( $mc_x,$mc_y+1+$i,$mc_z, 17);
				}
			}
############
			if( $OPTS->{EXTRUDE} && ($block == 45 || $block == 98))
			{
				my $BUILDINGSIZE=10;
				for( my $i=0;$i<$BUILDINGSIZE;++$i ) 
				{
					my $rblock = $block;
					if( $i % 3 == 1 ) { $rblock = 95.15; }
	
					$world->set_block( $mc_x, $mc_y+$i+1, $mc_z, $rblock );
				}
				# roof
				$world->set_block( $mc_x, $mc_y+$BUILDINGSIZE+1, $mc_z, 44.00 );
			}
$X::skip={};
$X::map={};
require "map.pl";



####################################################
my $c={};
foreach my $failcol ( keys %$failcols )
{
	my $v = $failcols->{$failcol};
	$c->{sprintf("%10d %s", $v, $failcol )} = "$failcol : $v";
}
foreach my $key ( sort keys %$c )
{
	print $c->{$key}."\n";
}
####################################################
exit;



