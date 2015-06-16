package Minecraft::MapTiles;

use Image::Magick;
use Math::Trig;
use strict;
use warnings;

sub new
{
	my( $class, %opts ) = @_;

	my $self = bless { %opts },$class;
	$self->{failcols} = {};
	$self->{tiles} = {};	
	$self->{colormap} = $self->colormap;

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
			my $cmd = "curl -s '".$self->{url}.$self->{zoom}."/$xtile/$ytile.png' > ".$self->{dir}."/$tile";
			#print "$cmd\n";
			`$cmd`;
		}
		$self->{tiles}->{$tile} = new Image::Magick;
		$self->{tiles}->{$tile}->Read( $self->{dir}."/$tile" );
	}

	my $pixel_x = POSIX::floor($self->{width}*$xr);
	my $pixel_y = POSIX::floor($self->{height}*$yr);

	my $scores = {};
	my $best = "FAIL";
	my $max = 0;
	my $midcol="eh";
	for( my $yy=-$self->{spread}; $yy<=$self->{spread}; ++$yy ) {
		X: for( my $xx=-$self->{spread}; $xx<=$self->{spread}; ++$xx ) {
			my $p_x = $pixel_x+$xx;
			my $p_y = $pixel_y+$yy;
			next if( $p_x<0 || $p_x>=$self->{width} );
			next if( $p_y<0 || $p_y>=$self->{height} );
			my @pixel = $self->{tiles}->{$tile}->GetPixel(x=>$p_x,y=>$p_y);
			next X if( !defined $pixel[0] );
			my $col = int( $pixel[0]*100 ).":".int( $pixel[1]*100 ).":".int($pixel[2]*100);
			if( $xx==0 && $yy==0 ) { $midcol=$col;}
#print $col."\n" if( !$self->{colormap}->{$col} );
			next X if( !$self->{colormap}->{$col} );

			$scores->{$col}++;
			if( $scores->{$col} > $max )
			{
				$max = $scores->{$col};
				$best = $col;
			}
		}
	}
	if( $self->{colormap}->{$best} ) 
	{ 
		return $self->{colormap}->{$best};
	}
	$self->{failcols}->{$midcol}++;
	if( defined $self->{default_block} )
	{
		return $self->{default_block};
	}
	return 1;
}

sub colormap
{
	return {
"100:94:72"=>12.0,#sand
"53:82:68"=> 159.09, #tennis courts?  cyan clay
"56:79:46"=> 2, #grass (tree?)
"60:60:60"=>17,#oak?!?
"63:72:82"=> 181, #redsand
"67:81:62"=> 2, #grass (garden);
"68:61:54"=>98,#church
"68:61:55"=>98,#church
"68:81:62"=> 2, #woods?
"70:81:81"=> 9, # water
"80:100:94"=> 2, #grass (playground)
"80:80:78"=> 98, #church
"80:92:65"=> 2, # grass?
"80:96:78"=> 2, # grass (park?)
"80:99:94"=> 2, #grass playground
"81:92:65"=> 2, #grass
"84:81:78"=> 45, #building
"85:81:78"=> 45, #building
"86:61:61"=> 159.15, #road 
"87:87:87"=> 159.09, # private -cyan clay
"87:88:88"=> 159.09, # private -cyan clay
"88:87:87"=> 159.09, # private -cyan clay
"88:88:87"=> 159.09, # private -cyan clay
"88:88:88"=> 159.09, # private -cyan clay
"89:77:66"=> 3, #allotment dirt
"89:77:67"=> 3, #allotment dirt
"89:78:67"=> 3, #allotment, dirt
"92:85:90"=> 159.08, # light grey clay( docks)
"92:92:92"=> 1, #stone
"94:85:84"=> 159.09, # cyan clay kinda pink on map
"94:93:90"=> 159.03, #tarmac? 
"94:93:91"=> 159.03, #tarmac
"94:94:84"=> 159.09, #campus? cyan clay
"96:82:82"=>1.05,#andesite
"96:93:71"=> 13, # carpark?
"97:97:72"=> 159.15, #road
"99:83:81"=> 159.09, # cyan clay kinda pink on map
"99:94:72"=>12.0,#sand
"99:99:99"=> 159.15, #road

#"71:70:57"=>170, #hay
#"97:83:66"=>95.13, #green wool

#EDGING TO IGNORE
#"97:83:66"=>5.05, #dark oak
#"72:87:80"=>14, some random edging

	};
}

1;	

__DATA__
"xxxxxxxx"=> 30, #cobs
"xxxxxxxx" => 95.4 	, #Yellow Stained Glass
"92:91:89"=> 17.0, #oak wood
"86:62:62"=> 14, #gold ore
"57:66:83"=> 35.10, #purple wool
"80:80:77"=> 35.05, #lime wool
"75:75:74"=> 5.05, # dark oak
"67:67:66"=> 35.13, #green wool
"95:95:90"=> 170 , #hay

	


	




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
			
{
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



