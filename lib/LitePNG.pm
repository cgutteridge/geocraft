
package LitePNG;
use strict;
use warnings;
use Compress::Zlib ;
use Data::Dumper;

sub new
{
	my( $class, $filename ) = @_;

	local $/ = undef;	
	my $fh;
	if( !open( $fh, "<:bytes", $filename ) ) 
	{
		print STDERR "failed to open $filename: $!\n";
		return;
	}
  	binmode $fh;
  	my $data = <$fh>;
  	close $fh;


	my $magic = chr(0x89).chr(0x50).chr(0x4E).chr(0x47).chr(0x0D).chr(0x0a).chr(0x1A).chr(0x0A);
	my $header = substr( $data,0, 8);
	
	if( $header ne $magic ) {
		print STDERR "missing PNG header on $filename\n";
		return;
	}

	my $self = bless {}, $class;
	my $offset = 8;	
	while( $offset<length( $data) )
	{
		# read chunk
		my $length = unpack( 'N', substr( $data,$offset,4));
		$offset += 4;

		my $type = substr( $data,$offset,4);
		$offset += 4;

		my $chunk = substr( $data,$offset,$length);
		$offset += $length;

		my $checksum = substr( $data,$offset,4);
		$offset += 4;

		# process chunk
		$self->add_chunk( $type, $chunk );
	}

	return $self;
}

sub add_chunk
{
	my( $self, $type, $chunk ) = @_;

	if( $type eq "IHDR" )
	{
		$self->{width} = unpack( 'N', substr( $chunk, 0, 4 ) );
		$self->{height} = unpack( 'N', substr( $chunk, 4, 4 ) );
		$self->{bit_depth} = ord( substr( $chunk, 8, 1 ) );
		$self->{color_type} = ord( substr( $chunk, 9, 1 ) );
		$self->{compression} = ord( substr( $chunk, 10, 1 ) );
		$self->{filter} = ord( substr( $chunk, 11, 1 ) );
		$self->{interlace} = ord( substr( $chunk, 12, 1 ) );

		print Dumper( $self );
		if( $self->{color_type} !=3 ) { die "Color type ".$self->{color_type}." not supported"; }
		if( $self->{bit_depth} !=8 ) { die "Bit depth ".$self->{bit_depth}." not supported"; }
		if( $self->{compression} !=0 ) { die "Compression ".$self->{compression}." not supported"; }
		if( $self->{filter} !=0 ) { die "Filter ".$self->{filter}." not supported"; }
		if( $self->{interlace} !=0 ) { die "Interlace ".$self->{interlace}." not supported"; }
		return;
	}

	if( $type eq "PLTE" )
	{		
		$self->{palette} = [];
		for( my $i=0; $i<length($chunk)/3; ++$i )
		{
			$self->{palette}->[$i] = [ 
				ord( substr( $chunk, $i*3+0, 1 )),
				ord( substr( $chunk, $i*3+1, 1 )),
				ord( substr( $chunk, $i*3+2, 1 )),
			];
		}
		return;
	}

	if( $type eq "IDAT" )
	{
		print length($chunk)."\n";
		my $idat = uncompress( $chunk );
		print length($idat)."\n";
		my $offset = 0;
		for(my $y=0;$y<$self->{height};++$y) {
			$offset++; # filter type byte
			for(my $x=0;$x<$self->{width};++$x) {
				$self->{pixel}->{$y}->{$x} = $self->{palette}->[ ord( substr($idat,$offset,1) ) ];
				$offset++;
			}
		}
		return;
	}
	print "$type\n";
}
