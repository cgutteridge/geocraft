
package Elevation;

use Geo::Coordinates::OSGB qw(ll_to_grid grid_to_ll);
use POSIX;
use Data::Dumper;
use strict;
use warnings;

sub new 
{
	my( $class, $heightdir, $correction ) = @_;

	if( !defined $correction ) { $correction = [0,0]; }
	my $self = bless { files=>{}, cells=>{}, correction=>$correction }, $class;

	opendir( my $hdir, $heightdir ) || die "Can't read elevation dir $heightdir";
	while( my $file = readdir($hdir))
	{
		next if( $file =~ m/^\./ );
		my $filename = "$heightdir/$file";
		open( my $fh, "<", $filename ) 
			|| die "can't read elevation file $filename: $!";
		my $metadata = {};
		for(my $i=0;$i<6;++$i)
		{
			my $line = readline( $fh );
			chomp $line;
			my( $k,$v ) = split( /\s+/, $line );
			$metadata->{$k}=$v;
		}	
		close( $fh );
		if( defined $self->{ncols} && $metadata->{ncols} != $self->{ncols} )
		{
			die "$file had ncols=".$metadata->{ncols}.", expected ".$self->{ncols};
		}
		if( defined $self->{nrows} && $metadata->{nrows} != $self->{nrows} )
		{
			die "$file had nrows=".$metadata->{nrows}.", expected ".$self->{nrows};
		}
		if( defined $self->{cellsize} && $metadata->{cellsize} != $self->{cellsize} )
		{
			die "$file had cellsize=".$metadata->{cellsize}.", expected ".$self->{cellsize};
		}
		$self->{cellsize} = $metadata->{cellsize} if( !defined $self->{cellsize} );
		$self->{nrows} = $metadata->{nrows} if( !defined $self->{nrows} );
		$self->{ncols} = $metadata->{ncols} if( !defined $self->{ncols} );
		# NODATA_value ??
		$self->{files}->{$metadata->{yllcorner}}->{$metadata->{xllcorner}} = $filename;
	}
	$self->{filesize_e} = $self->{ncols}*$self->{cellsize};
	$self->{filesize_n} = $self->{nrows}*$self->{cellsize};
	return $self;
}

sub ll
{
	my( $self, $lat, $long ) = @_;

	my( $e, $n ) = ll_to_grid( $lat,$long );
	$e += $self->{correction}->[0];
	$n += $self->{correction}->[1];
	# Flatten to get SW cell corner
	
	my $ce = POSIX::floor( $e/$self->{cellsize} )*$self->{cellsize};
	my $cn = POSIX::floor( $n/$self->{cellsize} )*$self->{cellsize};

	my $SW = $self->cell_elevation( $ce, $cn );
	my $NW = $self->cell_elevation( $ce, $cn+$self->{cellsize} );
	my $NE = $self->cell_elevation( $ce+$self->{cellsize}, $cn+$self->{cellsize} );
	my $SE = $self->cell_elevation( $ce+$self->{cellsize}, $cn );
	if( !defined $SW || !defined $NW || !defined $SE || !defined $NE )
	{
print "no data $ce, $cn\n";
		return 0;
	}	

	my $h_ratio = ($e - $ce ) / $self->{cellsize};
	my $v_ratio = ($n - $cn ) / $self->{cellsize};

	my $N = $NW + ($NE-$NW)*$h_ratio;
	my $S = $SW + ($SE-$SW)*$h_ratio;
	my $height = $S + ($N-$S)*$v_ratio;

	$height = 0 if( $height < 0 );

	return $height;
}

sub cell_elevation
{
	my( $self, $cell_e, $cell_n ) = @_;

	if( defined $self->{cells}->{$cell_n}->{$cell_e} )
	{
		return $self->{cells}->{$cell_n}->{$cell_e};
	}
	my $file_e = POSIX::floor( $cell_e / $self->{filesize_e} )*$self->{filesize_e};
	my $file_n = POSIX::floor( $cell_n / $self->{filesize_n} )*$self->{filesize_n};

	my $fn = $self->{files}->{ $file_n }->{ $file_e };
	
	if( !defined $fn ) 
	{ 
		print "no elevation for $file_e,$file_n\n"; 
		return undef;
	}
	
	open( my $hfh, "<", $fn ) || die "can't read $fn";
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
