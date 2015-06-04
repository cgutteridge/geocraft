package Minecraft::Region;

use Compress::Zlib ;
use strict; 
use warnings;
use Data::Dumper;

#coordinates are relative to the region

# need an 'ensure section' function later

sub block_section
{
	my($self, $x,$y,$z ) = @_;

	# work out which chunk
	my $chunk_x = $x >> 4;
	my $chunk_z = $z >> 4;
	my $section_y = $y >> 4;

	my $chunk = $self->{$chunk_z}->{$chunk_x}->{chunk};
	my $sections = $chunk->{children}->{Level}->{children}->{Sections};
	my $section = $sections->{value}->[$section_y];
	return $section;
}
sub add_section
{
	my($self, $x,$y,$z ) = @_;

	# work out which chunk
	my $chunk_x = $x >> 4;
	my $chunk_z = $z >> 4;
	my $section_y = $y >> 4;

	my $chunk = $self->{$chunk_z}->{$chunk_x}->{chunk};
	my $sections = $chunk->{children}->{Level}->{children}->{Sections};


	my $section = bless( { children=>{} }, "Minecraft::NBT::Compound"  );
	$section->{children}->{Y} = bless { name=>"Y", value=>$section_y }, "Minecraft::NBT::Byte";
	$section->{children}->{Blocks} = bless { name=>"Blocks", value=>chr(0)x4096 }, "Minecraft::NBT::ByteArray";
	$section->{children}->{BlockLight} = bless { name=>"BlockLight", value=>chr(0)x2048 }, "Minecraft::NBT::ByteArray";
	$section->{children}->{SkyLight} = bless { name=>"SkyLight", value=>chr(0)x2048 }, "Minecraft::NBT::ByteArray";
	$section->{children}->{Data} = bless { name=>"Data", value=>chr(0)x2048 }, "Minecraft::NBT::ByteArray";
	
	push @{$sections->{value}}, $section;

   #'Blocks' => bless( { 'length' => 4096, 'value' => '?', 'name' => 'Blocks' }, 'Minecraft::NBT::ByteArray' ),
   #'BlockLight' => bless( { 'length' => 2048, 'value' => '', 'name' => 'BlockLight' }, 'Minecraft::NBT::ByteArray' ),
   #'SkyLight' => bless( { 'length' => 2048, 'value' => '?????????????????????', 'name' => 'SkyLight' }, 'Minecraft::NBT::ByteArray' ),
   #'Y' => bless( { 'value' => 9, 'name' => 'Y' }, 'Minecraft::NBT::Byte' ),
   #'Data' => bless( { 'length' => 2048, 'value' => '', 'name' => 'Data' }, 'Minecraft::NBT::ByteArray' )

	return $section;
}


sub block_offset 
{
	my( $self, $x,$y,$z) = @_;

	my $local_x = $x&15;
	my $local_y = $y&15;
	my $local_z = $z&15;
	my $offset = 16*16*$local_y + 16*$local_z + $local_x;
	return $offset;
}
sub get_block
{
	my($self, $x,$y,$z ) = @_;

	my $section = $self->block_section($x,$y,$z);
	return 0 if( !$section );
	my $offset = $self->block_offset($x,$y,$z);
	return ord( substr( $section->{children}->{Blocks}->{value}, $offset, 1 ) );
}
sub set_block
{
	my( $self,   $x,$y,$z, $type ) = @_;

	my $section = $self->block_section($x,$y,$z);
	if( !$section ) 
	{ 
		$section = $self->add_section($x,$y,$z);
	}
	my $offset = $self->block_offset($x,$y,$z);

	substr( $section->{children}->{Blocks}->{value}, $offset, 1 ) = chr($type);
}




################################################################################
################################################################################
################################################################################
# IO Functions
################################################################################
################################################################################
################################################################################






sub from_file
{
	my( $class, $filename ) = @_;

	local $/ = undef;
	open( my $fh, "<:bytes", $filename ) || die "failed to open $filename: $!";
  	binmode $fh;
  	my $data = <$fh>;
  	close $fh;

	return $class->from_string( $data );
}

sub to_file
{
	my( $self, $filename ) = @_;

	my $str = $self->to_string();
	local $/ = undef;
	open( my $fh, ">:bytes", $filename ) || die "failed to open $filename: $!";
  	binmode $fh;
  	syswrite( $fh, $str );
  	close $fh;
}

sub from_string
{
	my( $class, $data ) = @_;

	my $self = bless {}, $class;

	$self->{data} = $data;
	$self->{offset} = 0;
	$self->{length} = length($data);

	for( my $z=0; $z< 32; ++$z )
	{
		for( my $x=0; $x<32; ++$x )
		{
 			$self->{offset} = 4 * ($x + $z * 32);
			my $b1 = $self->byte;
			my $b2 = $self->byte;
			my $b3 = $self->byte;
			my $b4 = $self->byte;
			my $chunk_offset = ($b1<<16) + ($b2<<8) + ($b3);
			my $chunk_bits = $b4;
	
 			$self->{offset} = 4*32*32  + 4 * ($x + $z * 32);
			my $chunk_time = $self->int32;
	
			# << 12 is multiply 4096
			$self->{offset} = $chunk_offset<<12;
			my $chunk_length = $self->int32;
			my $compression_type = $self->byte;
			if( $compression_type != 2 ) { die "Oh, no, it's not zlib"; }
			my $zcomp = substr( $self->{data}, ($chunk_offset<<12)+5, $chunk_length-1 );
			my $chunk = uncompress( $zcomp );
			$self->{$z}->{$x}->{chunk} = Minecraft::NBT->from_string( $chunk );
			$self->{$z}->{$x}->{timestamp} = $chunk_time;
		}
	}

	return $self;
}

# get basic values from stream
sub get
{
	my( $self, $n ) = @_;
	if( $self->{offset} >= $self->{length} ) 
	{
		Carp::confess "out of data";
	}
	my $v = substr( $self->{data},$self->{offset},$n );
	$self->{offset}+=$n;
	return $v;
}
# get values from stream and reverse them IF the system is littlendian
sub gete
{
	my( $self, $n ) = @_;

	my $chars = $self->get( $n );

	# assume little endian
	return reverse $chars;
}
sub byte
{
	my( $self ) = @_;
	
	return ord( $self->get(1) );
}
sub int32
{
	my( $self ) = @_;
	my $t1 = $self->byte;
	my $t2 = $self->byte;
	my $t3 = $self->byte;
	my $t4 = $self->byte;
	return ($t1<<24) + ($t2<<16) + ($t3<<8) + $t4;
}

######################################################################

sub to_string
{
	my( $self ) = @_;

	my $chunk_offset=2;
	my $offset = [];
	my $time_data = [];
	my $chunk_data = [];

	# turn each chunk into data
	for( my $z=0; $z<32; ++$z )
	{
		for( my $x=0; $x<32; ++$x )
		{
			my $chunk_time = $self->{$z}->{$x}->{timestamp};
			my $chunk_nbt = $self->{$z}->{$x}->{chunk}->to_string();
			my $zcomp = compress( $chunk_nbt );
			my $length = length( $zcomp )+1;
		
			my $chunk = chr(($length>>24)&255).chr(($length>>16)&255).chr(($length>>8)&255).chr(($length)&255);
			$chunk .= chr(2);
			$chunk .= $zcomp;			

			if( length( $chunk ) % 4096 != 0 )
			{
				$chunk .= chr(0)x(4096-(length( $chunk ) % 4096));
			}
			if( length( $chunk ) % 4096 != 0 )
			{
				die "math fail";
			}
			my $sectors = length( $chunk )/4096;

			push @$chunk_data, $chunk;
			push @$offset, chr(($chunk_offset>>16)&255).chr(($chunk_offset>>8)&255).chr(($chunk_offset)&255).chr($sectors);
			push @$time_data, chr(($chunk_time>>24)&255).chr(($chunk_time>>16)&255).chr(($chunk_time>>8)&255).chr(($chunk_time)&255);
			$chunk_offset += $sectors;
		}
	}

	my $str = join( "", @$offset, @$time_data, @$chunk_data );
	return $str;
}

1;
