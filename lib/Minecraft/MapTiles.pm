package Minecraft::MapTiles;

use Image::Magick;
use Math::Trig;
use strict;
use warnings;

sub new
{
	my( $class, %opts ) = @_;

	my $self = bless { %opts },$class;
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

sub tile
{
	my( $self, $zoom, $xtile, $ytile ) = @_;	

	my $fn = $zoom."_${xtile}_${ytile}.png";

	if( !defined $self->{tiles}->{$fn} )
	{
		if( !-e "$self->{dir}/$fn" )
		{
			my $cmd = "curl -s '".$self->{url}.$self->{zoom}."/$xtile/$ytile.png' > ".$self->{dir}."/$fn";
			#print "$cmd\n";
			`$cmd`;
		}
		$self->{tiles}->{$fn} = new Image::Magick;
		$self->{tiles}->{$fn}->Read( $self->{dir}."/$fn" );
	}
	return $self->{tiles}->{$fn};
}



sub col_on_tile
{
	my( $self, $tile, $p_x,$p_y ) = @_;

	my @pixel = $tile->GetPixel(x=>$p_x,y=>$p_y);
	return undef if( !defined $pixel[0] );
	return int( $pixel[0]*100 ).":".int( $pixel[1]*100 ).":".int($pixel[2]*100);
}

sub spread_colours
{
	my( $self,$lat,$long ) = @_;

	my( $xtile,$ytile, $xr,$yr ) = getTileNumber( $lat,$long, $self->{zoom} );
	my $tile = $self->tile( $self->{zoom}, $xtile, $ytile );

	my $pixel_x = POSIX::floor($self->{width}*$xr);
	my $pixel_y = POSIX::floor($self->{height}*$yr);

	my @colours = ();
	for( my $yy=-$self->{spread}; $yy<=$self->{spread}; ++$yy ) {
		X: for( my $xx=-$self->{spread}; $xx<=$self->{spread}; ++$xx ) {
			my $p_x = $pixel_x+$xx;
			my $p_y = $pixel_y+$yy;
			next if( $p_x<0 || $p_x>=$self->{width} );
			next if( $p_y<0 || $p_y>=$self->{height} );
			my $col = $self->col_on_tile( $tile, $p_x, $p_y );
			next X if( !defined $col );
			push @colours, $col;
		}
	}
	return @colours;
}

sub block_at
{
	my( $self, $lat, $long ) = @_;
	
	my $scores = {};
	my $best = "FAIL";
	my $max = 0;
	my @colours = $self->spread_colours($lat,$long);
	foreach my $col ( @colours )
	{
		next if( !$self->{map}->{$col} );
		$scores->{$col}++;
		if( $scores->{$col} > $max )
		{
			$max = $scores->{$col};
			$best = $col;
		}
	}
	if( $self->{map}->{$best} ) 
	{ 
		return $self->{map}->{$best};
	}
	if( defined $self->{default_block} )
	{
		return $self->{default_block};
	}
	return 1;
}

1;	
