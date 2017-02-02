package Minecraft::Region;

use IO::Uncompress::Gunzip qw(gunzip $GunzipError) ;
use Compress::Zlib ;
use strict; 
use warnings;
use Data::Dumper;
use POSIX;

#coordinates are relative to the region


sub new
{
	my($class,$opts) = @_;

	my $self = bless {opts=>$opts}, $class;

	return $self;
}


sub chunk_xz
{
	my( $self, $rel_x, $rel_z ) = @_;

	my $cx = POSIX::floor($rel_x/16);
	my $cz = POSIX::floor($rel_z/16);

	return( $cx, $cz );
}


sub block_section
{
	my($self, $rel_x,$y,$rel_z ) = @_;

	# work out which chunk
	my( $chunk_x, $chunk_z ) = $self->chunk_xz($rel_x,$rel_z);
	my $section_y = POSIX::floor($y/16);

	my $chunk = $self->{$chunk_z}->{$chunk_x}->{chunk};
	return undef if( !defined $chunk );

	my $sections = $chunk->{Level}->{Sections};
	my $section = $sections->{_value}->[$section_y];
	return $section;
}

sub add_section
{
	my($self, $rel_x,$y,$rel_z ) = @_;

	# work out which chunk
	my( $chunk_x, $chunk_z ) = $self->chunk_xz($rel_x,$rel_z);

	if( !defined $self->{$chunk_z}->{$chunk_x}->{chunk} )
	{
		$self->add_chunk( $chunk_x, $chunk_z );
	}
	my $chunk = $self->{$chunk_z}->{$chunk_x}->{chunk};
	
	my $sections = $chunk->{Level}->{Sections};

	my $section_y = POSIX::floor($y/16);

	for( my $section_y_i=0; $section_y_i<=$section_y; ++$section_y_i )
	{
		next if( defined $sections->{_value}->[$section_y_i] );

		my $section = bless( {}, "Minecraft::NBT::Compound"  );
		$section->{Y} = bless { _name=>"Y", _value=>$section_y_i }, "Minecraft::NBT::Byte";
		$section->{Blocks} = bless { _name=>"Blocks", _value=>chr(0)x4096 }, "Minecraft::NBT::ByteArray";
		$section->{BlockLight} = bless { _name=>"BlockLight", _value=>chr(0)x2048 }, "Minecraft::NBT::ByteArray";
		$section->{SkyLight} = bless { _name=>"SkyLight", _value=>chr(255)x2048 }, "Minecraft::NBT::ByteArray";
		$section->{Data} = bless { _name=>"Data", _value=>chr(0)x2048 }, "Minecraft::NBT::ByteArray";
		$sections->{_value}->[$section_y_i]= $section;
	}

	$self->{_changed} = 1;

	return $sections->{_value}->[$section_y];
}

sub add_chunk
{
	my($self,   $c_x, $c_z ) = @_;


	my $level = bless { _name=>"Level" }, "Minecraft::NBT::Compound";	
	$self->{$c_z}->{$c_x} = {
		timestamp => time(),
		chunk => bless  { _name=>"", Level=>$level }, "Minecraft::NBT::Compound"
	};

	$level->{TerrainPopulated} = bless { _name=>"TerrainPopulated", _value=>1 }, 'Minecraft::NBT::Byte';
	$level->{Biomes} = bless { _name=>"Biomes", _value=>chr(0)x256 }, 'Minecraft::NBT::ByteArray';
	$level->{xPos} = bless { _name=>"xPos", _value=>$self->{opts}->{r_x}*32+$c_x }, 'Minecraft::NBT::Int';
	$level->{zPos} = bless { _name=>"zPos", _value=>$self->{opts}->{r_z}*32+$c_z }, 'Minecraft::NBT::Int';
	$level->{LightPopulated} = bless { _name=>"LightPopulated", _value=>1 }, 'Minecraft::NBT::Byte';
	$level->{Entities} = bless { _name=>"Entities", _value=>[], _type=>10 }, 'Minecraft::NBT::TagList';
	$level->{TileEntities} = bless { _name=>"TileEntities", _value=>[], _type=>10 }, 'Minecraft::NBT::TagList';
	$level->{LastUpdate} = bless { _name=>"LastUpdate", _value=>0 }, 'Minecraft::NBT::Long';
	$level->{HeightMap} = bless { _name=>"HeightMap", _value=>[] }, 'Minecraft::NBT::IntArray';
	for( 0..255 ) { push @{$level->{HeightMap}->{_value}},0; }
	$level->{Sections} = bless { _name=>"Sections", _value=>[], _type=>10 }, 'Minecraft::NBT::TagList';
	if( defined $self->{opts}->{init_chunk} )
	{
		&{$self->{opts}->{init_chunk}}( $self, $c_x, $c_z );
	}

	$self->{_changed} = 1;
}

sub add_layer
{
	my( $self, $y, $type ) = @_;

#print "ADD LAYER:$y,$type\n";
	for( my $rel_z=0;$rel_z<512;++$rel_z) {
		for( my $rel_x=0;$rel_x<512;++$rel_x) {
#print "ADD LAYER BLOCK: $rel_x,$y,$rel_z\n";
			$self->set_block( $rel_x,$y,$rel_z, $type );
		}
	}
}

# Getters & Setters
# Coordinates relative to *Region*

sub biome_offset 
{
	my( $self, $rel_x, $rel_z ) = @_;

	my $local_x = $rel_x&15;
	my $local_z = $rel_z&15;

	my $offset = 16*$local_z + $local_x;
	return $offset;
}
sub block_offset 
{
	my( $self, $rel_x,$y,$rel_z) = @_;

	my $local_x = $rel_x&15;
	my $local_y = $y&15;
	my $local_z = $rel_z&15;


	my $offset = 16*16*$local_y + 16*$local_z + $local_x;
	return $offset;
}
sub has_block
{
	my($self, $rel_x,$y,$rel_z ) = @_;

	my $section = $self->block_section($rel_x,$y,$rel_z);
	return 0 if( !$section );
	return 1;
}
sub get_block
{
	my($self, $rel_x,$y,$rel_z ) = @_;

	my $section = $self->block_section($rel_x,$y,$rel_z);
	return 0 if( !$section );
	my $offset = $self->block_offset($rel_x,$y,$rel_z);
	return ord( substr( $section->{Blocks}->{_value}, $offset, 1 ) );
}
sub get_subtype
{
	my($self, $rel_x,$y,$rel_z ) = @_;

	my $section = $self->block_section($rel_x,$y,$rel_z);
	return 0 if( !$section );
	my $offset = $self->block_offset($rel_x,$y,$rel_z);

	my $byte = ord substr( $section->{Data}->{_value}, ($offset/2), 1 );
	if( $offset % 2 == 0 )
	{
		return $byte & 15;
	}
	else
	{
		return ($byte&240)/16;
	}
}
sub set_block
{
	my( $self,   $rel_x,$y,$rel_z, $type ) = @_;

	my $subtype = 0;
	if( int($type) != $type )
	{
		( $type, $subtype ) = split( /\./, $type );
		if( $subtype eq "1" ){$subtype="10";}
	}
	if( $type != ($type&255) ) { die "bad type passed to set_block: $type"; }
	if( $subtype != ($subtype&15) ) { die "bad subtype passed to set_block: $subtype"; }

#print "ADD BLOCK: $rel_x,$y,$rel_z {$type}\n";
	my $section = $self->block_section($rel_x,$y,$rel_z);
	if( !$section ) 
	{ 
		$section = $self->add_section($rel_x,$y,$rel_z);
	}
	my $offset = $self->block_offset($rel_x,$y,$rel_z);
#print "OFFSET: $offset\n\n";

	substr( $section->{Blocks}->{_value}, $offset, 1 ) = chr($type);

	# set subtype	
	my $byte = ord substr( $section->{Data}->{_value}, ($offset/2), 1 );
	if( $offset % 2 == 0 )
	{
		$byte = ($byte&240) + $subtype;
	}
	else
	{
		$byte = $subtype*16 + ($byte&15);
	}
	substr( $section->{Data}->{_value}, ($offset/2), 1 ) = chr($byte);

	$self->{_changed} = 1;
}
sub get_biome
{
	my( $self,   $rel_x,$rel_z ) = @_;

	my( $chunk_x, $chunk_z ) = $self->chunk_xz($rel_x,$rel_z);

	return undef if( !defined $self->{$chunk_z}->{$chunk_x}->{chunk} );
	my $chunk = $self->{$chunk_z}->{$chunk_x}->{chunk};
	my $level = $chunk->{Level};

	my $offset = $self->biome_offset($rel_x,$rel_z);

	return ord(substr( $level->{Biomes}->{_value}, $offset, 1 ));
}

sub set_biome
{
	my( $self,   $rel_x,$rel_z, $type ) = @_;

	if( $type != ($type&255) ) { die "bad type passed to set_biome: $type"; }

	my( $chunk_x, $chunk_z ) = $self->chunk_xz($rel_x,$rel_z);

	if( !defined $self->{$chunk_z}->{$chunk_x}->{chunk} )
	{
		$self->add_chunk( $chunk_x, $chunk_z );
	}
	my $chunk = $self->{$chunk_z}->{$chunk_x}->{chunk};
	my $level = $chunk->{Level};

	my $offset = $self->biome_offset($rel_x,$rel_z);

	substr( $level->{Biomes}->{_value}, $offset, 1 ) = chr($type);
	
	$self->{_changed} = 1;
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
	my( $class, $filename, $r_x,$r_z ) = @_;

	local $/ = undef;
	open( my $fh, "<:bytes", $filename ) || die "failed to open $filename: $!";
  	binmode $fh;
  	my $data = <$fh>;
  	close $fh;

	return $class->from_string( $data, $r_x,$r_z );
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
	my( $class, $data, $r_x,$r_z ) = @_;

	my $self = bless {}, $class;

	$self->{data} = $data;
	$self->{offset} = 0;
	$self->{length} = length($data);
	$self->{opts}->{r_x} = $r_x;
	$self->{opts}->{r_z} = $r_z;

	for( my $c_z=0; $c_z< 32; ++$c_z )
	{
		for( my $c_x=0; $c_x<32; ++$c_x )
		{
 			$self->{offset} = 4 * ($c_x + $c_z * 32);
			my $b1 = $self->byte;
			my $b2 = $self->byte;
			my $b3 = $self->byte;
			my $b4 = $self->byte;
			my $chunk_offset = ($b1<<16) + ($b2<<8) + ($b3);
			my $chunk_bits = $b4;

			next if( $chunk_offset == 0 );

			#print "$c_x, $c_z :: offset=$chunk_offset, bits=$chunk_bits\n";	
 			$self->{offset} = 4*32*32  + 4 * ($c_x + $c_z * 32);
			my $chunk_time = $self->int32;
	
			# << 12 is multiply 4096
			$self->{offset} = $chunk_offset<<12;
			my $chunk_length = $self->int32;
			my $compression_type = $self->byte;
			my $c_zcomp = substr( $self->{data}, ($chunk_offset<<12)+5, $chunk_length-1 );

			my $chunk;
			if( $compression_type == 1 )
			{
				gunzip \$c_zcomp => \$chunk;
			}
			elsif( $compression_type == 2 )
			{
				$chunk = uncompress( $c_zcomp );
			}
			else
			{
				open( my $tmp, ">:bytes", "/tmp/comp.example" );
				print {$tmp} $c_zcomp;
				close $tmp;
				die "Unknown compression type [$compression_type]"; 
			}

			$self->{$c_z}->{$c_x}->{chunk} = Minecraft::NBT->from_string( $chunk );
			$self->{$c_z}->{$c_x}->{timestamp} = $chunk_time;
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
	for( my $c_z=0; $c_z<32; ++$c_z )
	{
		X: for( my $c_x=0; $c_x<32; ++$c_x )
		{
			if( !defined $self->{$c_z}->{$c_x} )
			{
				push @$offset, chr(0).chr(0).chr(0).chr(0);
				push @$time_data, chr(0).chr(0).chr(0).chr(0);
				next X;
			}
			my $chunk_time = $self->{$c_z}->{$c_x}->{timestamp};
			my $chunk_nbt = $self->{$c_z}->{$c_x}->{chunk}->to_string();
			my $c_zcomp = compress( $chunk_nbt );
			my $length = length( $c_zcomp )+1;
		
			my $chunk = chr(($length>>24)&255).chr(($length>>16)&255).chr(($length>>8)&255).chr(($length)&255);
			$chunk .= chr(2);
			$chunk .= $c_zcomp;			

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
