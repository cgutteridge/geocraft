
package Elevation::UKDEFRA;

use parent 'Elevation';

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

# from http://code.activestate.com/recipes/577450-perl-url-encode-and-decode/
sub url_encode {
	my $s = shift;
	$s =~ s/ /+/g;
	$s =~ s/([^A-Za-z0-9\+-])/sprintf("%%%02X", ord($1))/seg;
	return $s;
}

sub get_url
{
	my( $self, $url ) = @_;

	my $cmd = "curl -s '$url'";
	print $cmd."\n";
	my $data = `$cmd`;
	return $data;
}
sub download_url
{
	my( $self, $url, $file ) = @_;

	my $cmd = "curl -s '$url' > $file";
	print $cmd."\n";
	my $data = `$cmd`;
	return $data;
}


sub download
{
	my( $self, $model, $file_e, $file_n ) = @_;

	# LOAD CATALOGUE IF NEEDED

	my $SCALE_EW = 5000;
	my $SCALE_NS = 5000;
	
	# Work out the square to query
	my $left   = POSIX::floor( $file_e / $SCALE_EW ) * $SCALE_EW;
	my $bottom = POSIX::floor( $file_n / $SCALE_NS ) * $SCALE_NS;

	my $code = "${left}E-${bottom}N";

	my $catalog_cache_dir = $self->{height_dir}."/catalog";
	if( !-d( $catalog_cache_dir ) ) {
		mkdir( $catalog_cache_dir );
	}

	my $catalog_cache_file = $catalog_cache_dir."/$code.json";

	if( -e $catalog_cache_file ) {
		print "Using cached catalog: $catalog_cache_file\n";
	} else {
		print "Attempting to cache catalog: $catalog_cache_file\n";
	
		my $e1 = $left   + 50;
		my $n1 = $bottom + 50;
		my $e2 = $left   + $SCALE_EW - 50;
		my $n2 = $bottom + $SCALE_NS - 50;
	
		my $aoi = {"geometryType"=>"esriGeometryPolygon","features"=>[{"geometry"=>{"rings"=>[[]],"spatialReference"=>{"wkid"=>27700,"latestWkid"=>27700}}}],"sr"=>{"wkid"=>27700,"latestWkid"=>27700}};
		push @{$aoi->{features}->[0]->{geometry}->{rings}->[0]}, [ $e1, $n1 ];
		push @{$aoi->{features}->[0]->{geometry}->{rings}->[0]}, [ $e2, $n1 ];
		push @{$aoi->{features}->[0]->{geometry}->{rings}->[0]}, [ $e2, $n2 ];
		push @{$aoi->{features}->[0]->{geometry}->{rings}->[0]}, [ $e1, $n2 ];
		my $submit_job_url = "https://environment.data.gov.uk/arcgis/rest/services/gp/DataDownload/GPServer/DataDownload/submitJob?f=json&SourceToken=&OutputFormat=0&RequestMode=SURVEY&AOI=".url_encode(encode_json( $aoi ));
		my $submit_job_response = $self->get_url( $submit_job_url );
		my $submit_job = decode_json( $submit_job_response );
		# we expect back: {"jobId":"jcc3fa88c8eba49db915cd7ff0c701774","jobStatus":"esriJobSubmitted"}
		my $jobid = $submit_job->{jobId};
		print "JOB:$jobid\n";
	
		my $JOB_WAIT_MAX = 60;
		my $JOB_WAIT_INTERVAL = 3; # lets not hammer it too hard
	
		my $waiting = 0;
		my $done = 0;
		while( !$done && $waiting <= $JOB_WAIT_MAX ) {
			sleep( $JOB_WAIT_INTERVAL );
			$waiting += $JOB_WAIT_INTERVAL;
			my $job_watch_url = "https://environment.data.gov.uk/arcgis/rest/services/gp/DataDownload/GPServer/DataDownload/jobs/$jobid?f=json"; #&dojo.preventCache=1550585729682
			my $are_we_there_yet_response = $self->get_url( $job_watch_url );
			my $are_we_there_yet = decode_json( $are_we_there_yet_response );
			print "".$are_we_there_yet->{jobStatus}."\n";
			$done=1 if( $are_we_there_yet->{jobStatus} eq "esriJobSucceeded" );
		}
	
		if( !$done ) {
			print "Request to job timed out after 60 seconds.\n";
			return;
		}
	
		my $job_output_url = "https://environment.data.gov.uk/arcgis/rest/services/gp/DataDownload/GPServer/DataDownload/jobs/$jobid/results/OutputResult?f=json"; #&dojo.preventCache=1550585729682
		my $job_output_response = $self->get_url( $job_output_url );
		my $job_output = decode_json( $job_output_response );
	
		my $cat_url = $job_output->{value}->{url};

		$self->download_url( $cat_url, $catalog_cache_file );
	}

	if( !$self->{loaded}->{$catalog_cache_file} ) {
		open( my $cat_fh, "<:utf8", $catalog_cache_file ) || die "Can't read $catalog_cache_file: $!";
		my $catalog_raw = join( "", <$cat_fh> );
		close $cat_fh;
	
		my $catalog = decode_json( $catalog_raw );
		my $datasets = {};
		foreach my $cdataset ( @{$catalog->{data}} ) {
			my $dataset = {};
			foreach my $cyear ( @{$cdataset->{years}} ) {
				my $year = {};
				foreach my $cres ( @{$cyear->{resolutions}} ) {
					my $res = {};
					foreach my $ctile ( @{$cres->{tiles}} ) {
						$res->{$ctile->{tileName}} = $ctile->{url};
					}
					$year->{$cres->{resolutionName}} = $res;
				}
				$dataset->{$cyear->{year}} = $year;
			}
				
			$datasets->{$cdataset->{productName}} = $dataset;
		}

		$self->{loaded}->{$catalog_cache_file}=1;

		$self->{zips}->{$code} = { DSM=>[], DTM=>[] };
		# Query .json for relevant LiDAR data - Most recent is selected
		foreach my $model_i ( qw/ DSM DTM / ) {
    			my $maxyear = 0;
    			foreach my $k ( keys %{$datasets->{"LIDAR Composite $model_i"}} ) {
        			if ($k > $maxyear) {
            			$maxyear = $k;
        			}
    			}
    			foreach my $k ( keys %{$datasets->{"LIDAR Composite $model_i"}->{$maxyear}->{"$model_i 1M"}} ) {
        			push @{$self->{zips}->{$code}->{$model_i}}, $datasets->{"LIDAR Composite $model_i"}->{$maxyear}->{"$model_i 1M"}->{$k};
    			}
		}

print Dumper($self->{zips});
	}

	# keep trying packs until we get a hit for this file
	if( scalar @{$self->{zips}->{$code}->{$model}} ) {
		# while there's still some untried zips and we don't have the file we need
		while( scalar @{$self->{zips}->{$code}->{$model}} && !$self->{files}->{$model}->{ $file_n }->{ $file_e } ) {
			print "TRYING NEXT OPTION for $file_e/$file_n. ".scalar @{$self->{zips}->{$code}->{$model}}." remain.\n";
			my $zip_url = shift @{$self->{zips}->{$code}->{$model}};
			$self->add_zip( $zip_url, $model );
		}
	}
	

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
#		print "$filename had ncols=".$metadata->{ncols}.", expected ".$self->{ncols}.", skipping.\n";
		return;
	}
	if( defined $self->{nrows} && $metadata->{nrows} != $self->{nrows} )
	{
#		print "$filename had nrows=".$metadata->{nrows}.", expected ".$self->{nrows}.", skipping.\n";
		return;
	}
	if( defined $self->{cellsize} && $metadata->{cellsize} != $self->{cellsize} )
	{
#		print "$filename had cellsize=".$metadata->{cellsize}.", expected ".$self->{cellsize}.", skipping.\n";
		return;
	}
	$self->{files}->{$model}->{$metadata->{yllcorner}}->{$metadata->{xllcorner}} = $filename;
}

# STATIC
sub ll_to_en
{
	my( $lat, $long ) = @_;

	my ($x, $y) = Geo::Coordinates::OSGB::ll_to_grid($lat, $long, 'ETRS89'); # or 'WGS84'
	return Geo::Coordinates::OSTN02::ETRS89_to_OSGB36($x, $y );
}
# STATIC
sub en_to_ll
{
	my( $e, $n ) = @_;

	my( $x,$y ) =  Geo::Coordinates::OSTN02::OSGB36_to_ETRS89( $e, $n );
	return Geo::Coordinates::OSGB::grid_to_ll($x, $y, 'ETRS89'); # or 'WGS84'
}


# model is DSM or DTM
sub ll
{
	my( $self, $model, $lat, $long ) = @_;

	my( $e, $n ) = ll_to_en( $lat, $long );

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
		# print "no elevation for $file_e,$file_n\n"; 
		$self->download( $model, $file_e, $file_n );
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
