
package Elevation;

use Geo::Coordinates::OSGB qw(ll_to_grid grid_to_ll);
use POSIX;
use strict;
use warnings;

sub new 
{
	my( $class, $mapfile, $cellsize ) = @_;

	my $self = bless { cellsize=>$cellsize, files=>{}, cells=>{} }, $class;

	open( my $mfh, "<", $mapfile );
	while( my $line = <$mfh> )
	{
		$line =~ s/\n//g;
		$line =~ s/\r//g;
		chomp $line;
		my($line_north, $line_east ,$filename) = split( / /, $line );
		$self->{files}->{$line_north}->{$line_east} = $filename;
	}
	close( $mfh );

	return $self;
}

sub ll
{
	my( $self, $lat, $long ) = @_;

	my( $e, $n ) = ll_to_grid( $lat,$long, "WGS84" );
	# Flatten to get SW cell corner
	
	my $ce = POSIX::floor( $e/$self->{cellsize} )*$self->{cellsize};
	my $cn = POSIX::floor( $n/$self->{cellsize} )*$self->{cellsize};

	my $SW = $self->cell_elevation( $ce, $cn );
	my $NW = $self->cell_elevation( $ce, $cn+$self->{cellsize} );
	my $NE = $self->cell_elevation( $ce+$self->{cellsize}, $cn+$self->{cellsize} );
	my $SE = $self->cell_elevation( $ce+$self->{cellsize}, $cn );

	my $h_ratio = ($e - $ce ) / $self->{cellsize};
	my $v_ratio = ($n - $cn ) / $self->{cellsize};

	my $N = $NW + ($NE-$NW)*$h_ratio;
	my $S = $SW + ($SE-$SW)*$h_ratio;
	my $height = $S + ($N-$S)*$v_ratio;

	return $height;
}

sub cell_elevation
{
	my( $self, $cell_e, $cell_n ) = @_;

	if( defined $self->{cells}->{$cell_n}->{$cell_e} )
	{
		return $self->{cells}->{$cell_n}->{$cell_e};
	}
	my $FILESCALE = 10000;
	# assume 10K files for now
	my $file_e = POSIX::floor( $cell_e / $FILESCALE )*$FILESCALE;
	my $file_n = POSIX::floor( $cell_n / $FILESCALE )*$FILESCALE;

	my $fn = $self->{files}->{ $file_n }->{ $file_e };
	
	if( !defined $fn ) { die "no elevation for $file_e,$file_n"; }
	
	my $file = "$FindBin::Bin/HeightData/$fn";
	open( my $hfh, "<", $file ) || die "can't read $file";
	my @lines = <$hfh>;
	close $hfh;

	for( my $i=6; $i<scalar(@lines); ++$i )
	{
		my $line = $lines[$i];
		$line =~ s/\n//g;
		$line =~ s/\r//g;
		my @row = split( / /, $line );
		for( my $j=0; $j<scalar(@row); $j++ )
		{
			$self->{cells}->{ $file_n + (499-($i-6))*$self->{cellsize} }->{ $file_e + $j*$self->{cellsize} } = $row[$j];

		}
	}

	return $self->{cells}->{$cell_n}->{$cell_e};
}


1;
