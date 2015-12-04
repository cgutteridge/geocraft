
package Elevation;

use Geo::Coordinates::OSGB qw(ll_to_grid grid_to_ll);
use Geo::Coordinates::OSTN02;
use POSIX;
use Data::Dumper;
use JSON::PP;
use Archive::Zip qw/ :ERROR_CODES /;
use strict;
use warnings;

sub new 
{
	my( $class, $height_dir, $tmp_dir, $correction ) = @_;

	if( !defined $correction ) { $correction = [0,0]; }
	my $self = bless { 
		files => {}, 
		loaded => {}, 
		cells => {}, 
		height_dir => $height_dir,
		tmp_dir => $tmp_dir,
		correction => $correction }, $class;

	$self->{cellsize} = 1;
	$self->{nrows} = 1000;
	$self->{ncols} = 1000;
	$self->{filesize_e} = $self->{ncols}*$self->{cellsize};
	$self->{filesize_n} = $self->{nrows}*$self->{cellsize};

	foreach my $model ( "DSM","DTM" ) 
	{
		print "Reading $model LIDAR metadata\n";
		opendir( my $hdir, $height_dir."/$model" ) || die "Can't read elevation dir $height_dir";
		while( my $file = readdir($hdir))
		{
			next if( $file =~ m/^\./ );
			next if( $file !~ m/\.asc$/ );
			$self->add_file( "$height_dir/$model/$file", $model );
		}
	}

	return $self;
}

sub get_url
{
	my( $self, $url ) = @_;

	my $cmd = "curl '$url'";
	print $cmd."\n";
	my $data = `$cmd`;
	return $data;
}
sub download_url
{
	my( $self, $url, $file ) = @_;

	my $cmd = "curl '$url' > $file";
	print $cmd."\n";
	my $data = `$cmd`;
	return $data;
}


sub download
{
	my( $self, $file_e, $file_n ) = @_;

	print "($file_e)($file_n)\n";
	my $url = sprintf( 
		"https://raw.githubusercontent.com/cgutteridge/uklidar/master/catalog/%04d-%04d.json",
		POSIX::floor( $file_e/10000 )*10,
		POSIX::floor( $file_n/10000 )*10 );
	if( $self->{loaded}->{$url} )
	{
		return; 
	}
	my $json_text = $self->get_url( $url );
	my $cat_record = decode_json( $json_text );

	my $target = {};
	foreach my $item ( @$cat_record )
	{
		my $id = $item->{metaDataUrl};
		$id =~ s/1$//;
		$target->{$id} = $item->{url};
	}

	if( defined $target->{"https://data.gov.uk/dataset/lidar-composite-dsm-1m"} )
	{
		$self->add_zip( $target->{"https://data.gov.uk/dataset/lidar-composite-dsm-1m"}, "DSM" );
	}
	if( defined $target->{"https://data.gov.uk/dataset/lidar-composite-dtm-1m"} )
	{
		$self->add_zip( $target->{"https://data.gov.uk/dataset/lidar-composite-dtm-1m"}, "DTM" );
	}

	$self->{loaded}->{$url} = 1;
}

sub add_zip
{
	my( $self, $url, $model ) = @_;

	my $tmp_file = $self->{tmp_dir}."/lidar.$$.zip";

	$self->download_url( $url, $tmp_file );

	# Read a Zip file
	my $zip = Archive::Zip->new();
	unless ( $zip->read( $tmp_file ) == AZ_OK ) 
	{
		unlink( $tmp_file );
		die 'read error: '.$tmp_file;
	}

	foreach my $member ( $zip->members )
	{
		my $file = $self->{height_dir}."/$model/".$member->fileName;
		print "Adding: $file\n";
		$member->extractToFileNamed( $file );
		$self->add_file( $file, $model );
	}
	unlink( $tmp_file );
}

sub add_file
{
	my( $self, $filename, $model ) = @_;

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
		die "$filename had ncols=".$metadata->{ncols}.", expected ".$self->{ncols};
	}
	if( defined $self->{nrows} && $metadata->{nrows} != $self->{nrows} )
	{
		die "$filename had nrows=".$metadata->{nrows}.", expected ".$self->{nrows};
	}
	if( defined $self->{cellsize} && $metadata->{cellsize} != $self->{cellsize} )
	{
		die "$filename had cellsize=".$metadata->{cellsize}.", expected ".$self->{cellsize};
	}
	$self->{files}->{$model}->{$metadata->{yllcorner}}->{$metadata->{xllcorner}} = $filename;
}

sub ll
{
	my( $self, $model, $lat, $long ) = @_;

	my ($x, $y) = Geo::Coordinates::OSGB::ll_to_grid($lat, $long, 'ETRS89'); # or 'WGS84'
	my ($e, $n) = Geo::Coordinates::OSTN02::ETRS89_to_OSGB36($x, $y );
	return $self->en( $model, $e,$n );
}

sub en
{
	my( $self, $model, $e, $n ) = @_;

	$e += $self->{correction}->[0];
	$n += $self->{correction}->[1];
	# Flatten to get SW cell corner
	return $self->raw_en( $model, $e,$n );
}
	
sub raw_en
{
	my( $self, $model, $e, $n ) = @_;

#print "Inspecting: ${e}E ${n}N\n";

	my $ce = POSIX::floor( $e/$self->{cellsize} )*$self->{cellsize};
	my $cn = POSIX::floor( $n/$self->{cellsize} )*$self->{cellsize};

	my $SW = $self->cell_elevation( $model, $ce, $cn );
	my $NW = $self->cell_elevation( $model, $ce, $cn+$self->{cellsize} );
	my $NE = $self->cell_elevation( $model, $ce+$self->{cellsize}, $cn+$self->{cellsize} );
	my $SE = $self->cell_elevation( $model, $ce+$self->{cellsize}, $cn );
	if( !defined $SW || !defined $NW || !defined $SE || !defined $NE )
	{
		# print "no data $ce, $cn\n";
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
	my( $self, $model, $cell_e, $cell_n ) = @_;

	if( defined $self->{cells}->{$model}->{$cell_n}->{$cell_e} )
	{
		return $self->{cells}->{$model}->{$cell_n}->{$cell_e};
	}
	my $file_e = POSIX::floor( $cell_e / $self->{filesize_e} )*$self->{filesize_e};
	my $file_n = POSIX::floor( $cell_n / $self->{filesize_n} )*$self->{filesize_n};

	my $fn = $self->{files}->{$model}->{ $file_n }->{ $file_e };
	
	if( !defined $fn ) 
	{
		# attempt to download lidar
		print "no elevation for $file_e,$file_n\n"; 
		$self->download( $file_e, $file_n );
		$fn = $self->{files}->{$model}->{ $file_n }->{ $file_e };
		if( !defined $fn ) 
		{
			# give up 
			return;
		}
	}
	if( $self->{loaded}->{$fn} )
	{
		# don't try to load the same file twice
		return undef;
	}
	print "LOADING LIDAR: $fn\n";
	
	open( my $hfh, "<", $fn ) || die "can't read $fn";
	my @lines = <$hfh>;
	close $hfh;
	my $lidar = {};
        for( my $i=0; $i<6; ++$i )
        {
                my $line = $lines[$i];
                $line =~ s/[\n\r]//g;
                if( $line =~ m/^([^\s]+)\s+(.*)$/ )
                {
                        $lidar->{uc $1} = $2;
                }
                else
                {
                        die "Bad line in .asc file: $line";
                }
        }

	for( my $i=6; $i<scalar(@lines); ++$i )
	{
		my $line = $lines[$i];
		$line =~ s/\n//g;
		$line =~ s/\r//g;
		$line =~ s/\s*$//g;
		$line =~ s/^\s*//g;
		my @row = split( / /, $line );
		CELL: for( my $j=0; $j<scalar(@row); $j++ )
		{
			$self->{cells}->{$model}->{ $file_n + ($lidar->{NROWS}-1-($i-6))*$self->{cellsize} }->{ $file_e + $j*$self->{cellsize} } = $row[$j];
		}
	}
	$self->{loaded}->{$fn} = 1;

	return $self->{cells}->{$model}->{$cell_n}->{$cell_e};
}


1;
