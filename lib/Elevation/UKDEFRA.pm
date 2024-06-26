
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

my $GDAL_TRANSLATE = "/Applications/QGIS.app/Contents/MacOS/bin/gdal_translate";

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
	$self->{nrows} = 5000;
	$self->{ncols} = 5000;
	$self->{filesize_e} = $self->{ncols}*$self->{cellsize};
	$self->{filesize_n} = $self->{nrows}*$self->{cellsize};

	foreach my $model ( "DSM","DTM" ) 
	{
		print "Reading $model LIDAR metadata\n";
		opendir( my $hdir, $height_dir."/$model" ) || die "Can't read elevation dir $height_dir";
		while( my $file = readdir($hdir))
		{
			next if( $file =~ m/^\./ );
			next if( $file !~ m/\.tif$/ );
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
	my( $self, $url, $reqestData, $headers ) = @_;

	my $cmd = "curl -s '$url'";
    if( defined $reqestData ) {
        $cmd .= " --data '$reqestData'";
    }
    if( defined $headers ) {
        foreach my $header ( @$headers ) {
            $cmd.= " -H '$header'";
        }
    }
	print $cmd."\n";
	my $data = `$cmd`;
	return $data;
}
sub download_url
{
	my( $self, $url, $file ) = @_;

	my $cmd = "curl -s '$url' > '$file'";
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

        my $coordinates = [];
		push @$coordinates, [reverse en_to_ll( $e1, $n1 )];
		push @$coordinates, [reverse en_to_ll( $e2, $n1 )];
		push @$coordinates, [reverse en_to_ll( $e2, $n2 )];
		push @$coordinates, [reverse en_to_ll( $e1, $n2 )];
		push @$coordinates, [reverse en_to_ll( $e1, $n1 )];
        my $geojson = { coordinates=> [$coordinates], type=> "Polygon" };

        my $endpoint = "https://environment.data.gov.uk/backend/catalog/api/tiles/collections/survey/search";

		my $response = $self->get_url( $endpoint, encode_json( $geojson), ["Content-type: application/geo+json"] );
        open( my $fh, ">:utf8", $catalog_cache_file ) || die "can't write $catalog_cache_file: $?";
        print {$fh} $response;
        close $fh;
	}

	if( !$self->{loaded}->{$catalog_cache_file} ) {
		open( my $cat_fh, "<:utf8", $catalog_cache_file ) || die "Can't read $catalog_cache_file: $!";
		my $catalog_raw = join( "", <$cat_fh> );
		close $cat_fh;

        # format of result
        #                {
        #                   'product' => { 'label' => 'LIDAR Composite DTM', 'id' => 'lidar_composite_dtm' },
        #                   'year' => { 'label' => '2022', 'id' => '2022' },
        #                   'tile' => { 'id' => 'SU4015', 'label' => 'SU41nw' },
        #                   'label' => 'lidar_composite_dtm-2022-1m-SU41nw',
        #                   'uri' => 'https://api.agrimetrics.co.uk/tiles/collections/survey/lidar_composite_dtm/2022/1/SU4015',
        #                   'resolution' => { 'label' => '1m', 'id' => '1' }
        #                 },

        # datasets->{ product_id }->{ year }->{ resolution_id }->{tile_id}  = url;
	
		my $catalog = decode_json( $catalog_raw );
		my $datasets = {};
		foreach my $result ( @{$catalog->{results}} ) {
            $datasets->{ $result->{product}->{id} }->{ $result->{year}->{id} }->{ $result->{resolution}->{id} }->{ $result->{tile}->{id} } = $result->{uri}."?subscription-key=public";
		}

		$self->{loaded}->{$catalog_cache_file}=1;
		# later maybe look at years, but with luck composite will do
		$self->{zips}->{$code} = { DSM=>[], DTM=>[] };
#national_lidar_programme_dtm
#lidar_composite_dtm
#lidar_tiles_dtm
#
#national_lidar_programme_first_return_dsm
#lidar_composite_first_return_dsm
#national_lidar_programme_dsm
#lidar_composite_last_return_dsm
#lidar_tiles_dsm

		# this is to deal with the inconsistant naming in DEFRA DTM/DSM
		my $SETMAP = {
		       	"DSM"=>"lidar_composite_last_return_dsm",
	       		"DTM"=>"lidar_composite_dtm" };
		foreach my $model_i ( qw/ DSM DTM / ) {
			my $target_set = $SETMAP->{$model_i};
			my $set = $datasets->{$target_set};
			# pick the latest key from this set. Hopefully it's the latest data although
			# currently both composite DTM & DSM seem to only have one year
			my @years = sort keys %$set;
			my $models = $set->{$years[0]};
			
		    foreach my $key ( keys %{$models->{"1"}} ) {
				push @{$self->{zips}->{$code}->{$model_i}}, $models->{"1"}->{$key};
			}
		}
	}

	# keep trying packs until we get a hit for this file
	if( scalar @{$self->{zips}->{$code}->{$model}} ) {
		# while there's still some untried zips and we don't have the file we need
		while( scalar @{$self->{zips}->{$code}->{$model}} && !$self->{files}->{$model}->{ $file_n }->{ $file_e } ) {
			# print "TRYING NEXT OPTION for $file_e/$file_n. ".scalar @{$self->{zips}->{$code}->{$model}}." remain.\n";
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
		if( $file=~m/\.tif$/ ) {
			$member->extractToFileNamed( $file );
			$self->add_file( $file, $model );
		}
	}
	unlink( $tmp_file );
}

sub add_file
{
	my( $self, $tif_filename, $model ) = @_;

	my $filename = $tif_filename;
	$filename =~ s/\.tif$/.asc/;

	if( !-e $filename ) {
		# print "Converting: $tif_filename to ASC using gdal_translate\n";
		`$GDAL_TRANSLATE -of AAIGrid -ot Int32 $tif_filename $filename`;
	}

	# print "Adding: $filename\n";

	open( my $fh, "<", $filename ) 
		|| die "can't read elevation file $filename: $!";
	my $metadata = {};
	for(my $i=0;$i<6;++$i)
	{
		my $line = readline( $fh );
		chomp $line;
		my( $k,$v ) = split( /\s+/, $line );
		$metadata->{$k}=$v+0; # adding 0 forces it to be a number and removes trailing .0000
	}	
	close( $fh );

	if( defined $self->{ncols} && $metadata->{ncols} != $self->{ncols} )
	{
		# print "$filename had ncols=".$metadata->{ncols}.", expected ".$self->{ncols}.", skipping.\n";
		return;
	}
	if( defined $self->{nrows} && $metadata->{nrows} != $self->{nrows} )
	{
		# print "$filename had nrows=".$metadata->{nrows}.", expected ".$self->{nrows}.", skipping.\n";
		return;
	}
	if( defined $self->{cellsize} && $metadata->{cellsize} != $self->{cellsize} )
	{
		# print "$filename had cellsize=".$metadata->{cellsize}.", expected ".$self->{cellsize}.", skipping.\n";
		return;
	}
	$self->{files}->{$model}->{$metadata->{yllcorner}}->{$metadata->{xllcorner}} = $filename;
}

# STATIC
sub ll_to_en
{
	my( $lat, $long ) = @_;

	my ($x, $y) = Geo::Coordinates::OSGB::ll_to_grid($lat, $long, 'WGS84'); # or 'OSGB36'
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
		return;
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

	my $file_e = POSIX::floor( $cell_e / $self->{filesize_e} )*$self->{filesize_e};
	my $file_n = POSIX::floor( $cell_n / $self->{filesize_n} )*$self->{filesize_n};

	my $fn = $self->{files}->{$model}->{ $file_n }->{ $file_e };

	if( !defined $fn ) 
	{
		# attempt to download lidar
		# print "no elevation for $file_e,$file_n\n"; 
		$self->download( $model, $file_e, $file_n );
		$fn = $self->{files}->{$model}->{ $file_n }->{ $file_e };
	}
	if( !defined $fn ) 
	{
		# give up 
		return;
	}
	if( ! $self->{loaded}->{$fn} )
	{
		$self->load_file( $fn, $model, $file_n, $file_e );
	}
	return $self->{cells}->{$model}->{$cell_n}->{$cell_e};
}

sub load_file {
	my( $self, $fn, $model, $file_n, $file_e ) = @_;

	my $info = "Loading $model LIDAR \"$fn\":";
	print "\n";
	print $info;
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
		if( $i%100==6 ) { 
			my $ratio = ($i-6)/(scalar(@lines)-6);
			print sprintf( "\r%s %d%%", $info, $ratio*100);
		}
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
	print "\n";
	$self->{loaded}->{$fn} = 1;
}


1;
