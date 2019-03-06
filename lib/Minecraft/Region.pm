package Minecraft::Region;

use IO::Uncompress::Gunzip qw(gunzip $GunzipError) ;
use Compress::Zlib ;
use strict; 
use warnings;
use Data::Dumper;
use POSIX;
use JSON::PP;
use utf8;

#coordinates are relative to the region


sub new
{
	my($class,$opts) = @_;

	my $self = bless {opts=>$opts}, $class;

	return $self;
}

# test if the section a block is in exists
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

	return $self->block_section( $rel_x,$y,$rel_z, 1)->get_block( $rel_x%16,$y%16,$rel_z%16 );
}

sub set_block
{
	my( $self,   $rel_x,$y,$rel_z, $blockstate ) = @_;

	$self->block_section( $rel_x,$y,$rel_z, 1)->set_block( $rel_x%16,$y%16,$rel_z%16, $blockstate );

	$self->{_changed} = 1;
}

sub add_sign
{
	my( $self,   $rel_x,$y,$rel_z, $x,$z, $text ) = @_;

	my $SIGNWIDTH = 16;
	my @lines = ();
	while( length( $text ) )
	{
		$text =~ s/\s*$//;
		$text =~ s/^\s*//;
		my $line;
		if( $text =~ m/^(.{1,16})(\s|$)/ ) {
			$line = $1;
		} else {
			$line = substr( $text, 0, $SIGNWIDTH );	
		}
		push @lines, $line;
		$text = substr( $text, length( $line ) );
	}
	$lines[0] = "" unless defined $lines[0];
	$lines[1] = "" unless defined $lines[1];
	$lines[2] = "" unless defined $lines[2];
	$lines[3] = "" unless defined $lines[3];

	$self->set_block( $rel_x,$y,$rel_z,  63 );
	my $data = bless {
		x => (bless { _name=>"x", _value=>$x }, 'Minecraft::NBT::Int'),
		y => (bless { _name=>"y", _value=>$y }, 'Minecraft::NBT::Int'),
		z => (bless { _name=>"z", _value=>$z }, 'Minecraft::NBT::Int'),
		id => (bless { _name=>"id", _value=> "minecraft:sign" }, 'Minecraft::NBT::String'),
		Text1 => (bless { _name=>"Text1", _value=> encode_json( { "bold"=>1, "text"=>"§l".$lines[0] } ) }, 'Minecraft::NBT::String'),
		Text2 => (bless { _name=>"Text2", _value=> encode_json( { "bold"=>1, "text"=>"§l".$lines[1] } ) }, 'Minecraft::NBT::String'),
		Text3 => (bless { _name=>"Text3", _value=> encode_json( { "bold"=>1, "text"=>"§l".$lines[2] } ) }, 'Minecraft::NBT::String'),
		Text4 => (bless { _name=>"Text4", _value=> encode_json( { "bold"=>1, "text"=>"§l".$lines[3] } ) }, 'Minecraft::NBT::String'),
	}, "Minecraft::NBT::Compound";

print Dumper( $data );
	# doing set_block above should force the chunk to exist
	my $chunk = $self->chunk( $rel_x,$rel_z );

	push @{ $chunk->{Level}->{TileEntities}->{_value} }, $data;
}


sub get_biome
{
	my( $self,   $rel_x,$rel_z ) = @_;

	my $chunk = $self->chunk($rel_x,$rel_x);
	return undef if( !defined $chunk );

	my $offset = $self->biome_offset($rel_x,$rel_z);

	return ord(substr( $chunk->{Level}->{Biomes}->{_value}, $offset, 1 ));
}

sub set_biome
{
	my( $self,   $rel_x,$rel_z, $type ) = @_;

	if( $type != ($type&255) ) { die "bad type passed to set_biome: $type"; }

	my $chunk = $self->chunk($rel_x,$rel_x, 1);

	my $offset = $self->biome_offset($rel_x,$rel_z);

	substr( $chunk->{Level}->{Biomes}->{_value}, $offset, 1 ) = chr($type);
	
	$self->{_changed} = 1;
}

sub get_top
{
	my( $self,   $rel_x,$rel_z ) = @_;

	# could be better -- need to use the HeightMap?
	if( !defined $self->{top}->{$rel_z}->{$rel_x} ) 
	{
		my $y = 255;
		# work down until we get passed the non existant sections and air
		while( $y>0 && (!$self->has_block( $rel_x,$y,$rel_z) || $self->get_block( $rel_x,$y,$rel_z )==0 )) { --$y }
		$self->{top}->{$rel_z}->{$rel_x}= $y;
	}

	return $self->{top}->{$rel_z}->{$rel_x};
}


sub from_file
{
	my( $class, $filename, $r_x,$r_z ) = @_;

	local $/ = undef;
	open( my $fh, "<:bytes", $filename ) || die "failed to open $filename: $!";
  	binmode $fh;
  	my $data = <$fh>;
  	close $fh;

	return $class->new_from_bindata( $data, $r_x,$r_z );
}

sub to_file
{
	my( $self, $filename ) = @_;

	my $str = $self->to_bindata();
	local $/ = undef;
	open( my $fh, ">:bytes", $filename ) || die "failed to open $filename: $!";
  	binmode $fh;
  	syswrite( $fh, $str );
  	close $fh;
}


################################
 ##### PRIVATE FUNCTIONS ######
################################


#private
# returns the chunk containing a block at a region-relative position
# if $create flag is true the chunk will be created if required.
sub chunk {
	my($self, $rel_x,$rel_z, $create ) = @_;

	# convert region-relative x,z to a chunk ID
	my $chunk_x = POSIX::floor($rel_x/16);
	my $chunk_z = POSIX::floor($rel_z/16);

	if( $create && !defined $self->{chunk}->{$chunk_z}->{$chunk_x} )
	{
		$self->{chunk}->{$chunk_z}->{$chunk_x} = Minecraft::Chunk->new( $chunk_x,$chunk_z, $self->{opts}  );
		$self->{_changed} = 1;
	}

	return $self->{chunk}->{$chunk_z}->{$chunk_x};
}


# private
# return the section within a chunk within a region based on relative coords
sub block_section
{
	my($self, $rel_x,$y,$rel_z, $create ) = @_;

	my $chunk = $self->chunk( $rel_x, $rel_z, $create );
	return undef if( !defined $chunk );

	return $chunk->block_section( $y, ($create?$self:undef) );
}


#private,unused
sub add_layer
{
	my( $self, $y, $blockstate ) = @_;

#print "ADD LAYER:$y,$type\n";
	for( my $rel_z=0;$rel_z<512;++$rel_z) {
		for( my $rel_x=0;$rel_x<512;++$rel_x) {
#print "ADD LAYER BLOCK: $rel_x,$y,$rel_z\n";
			$self->set_block( $rel_x,$y,$rel_z, $blockstate );
		}
	}
}

# Getters & Setters
# Coordinates relative to *Region*

# private
sub biome_offset 
{
	my( $self, $rel_x, $rel_z ) = @_;

	my $local_x = $rel_x&15;
	my $local_z = $rel_z&15;

	my $offset = 16*$local_z + $local_x;
	return $offset;
}

# private
sub block_offset 
{
	my( $self, $rel_x,$y,$rel_z) = @_;

	my $local_x = $rel_x&15;
	my $local_y = $y&15;
	my $local_z = $rel_z&15;


	my $offset = 16*16*$local_y + 16*$local_z + $local_x;
	return $offset;
}


# private, unused
sub set_light
{
	my( $self,   $rel_x,$y,$rel_z, $level ) = @_;

	my $section = $self->block_section($rel_x,$y,$rel_z, 1);
	my $offset = $self->block_offset($rel_x,$y,$rel_z);

	# set subtype	
	my $byte = ord substr( $section->{BlockLight}->{_value}, ($offset/2), 1 );
	if( $offset % 2 == 0 )
	{
		$byte = ($byte&240) + $level;
	}
	else
	{
		$byte = $level*16 + ($byte&15);
	}
	substr( $section->{BlockLight}->{_value}, ($offset/2), 1 ) = chr($byte);

	$self->{_changed} = 1;
}


# private?
sub new_from_bindata
{
	my( $class, $data, $r_x,$r_z ) = @_;

	my $self = bless {}, $class;
	$self->{opts}->{r_x} = $r_x;
	$self->{opts}->{r_z} = $r_z;

	$self->{bindata} = $data;
	$self->{offset} = 0;
	$self->{length} = length($data);

	for( my $c_z=0; $c_z< 32; ++$c_z )
	{
		for( my $c_x=0; $c_x<32; ++$c_x )
		{
 			$self->{offset} = 4 * ($c_x + $c_z * 32);
			my $b1 = $self->next_byte;
			my $b2 = $self->next_byte;
			my $b3 = $self->next_byte;
			my $b4 = $self->next_byte;
			my $chunk_offset = ($b1<<16) + ($b2<<8) + ($b3);
			my $chunk_bits = $b4;

			next if( $chunk_offset == 0 );

			#print "$c_x, $c_z :: offset=$chunk_offset, bits=$chunk_bits\n";	
 			$self->{offset} = 4*32*32  + 4 * ($c_x + $c_z * 32);
			my $chunk_time = $self->next_int32;
	
			# << 12 is multiply 4096
			$self->{offset} = $chunk_offset<<12;
			my $chunk_length = $self->next_int32;
			my $compression_type = $self->next_byte;
			my $c_zcomp = substr( $self->{bindata}, ($chunk_offset<<12)+5, $chunk_length-1 );

			my $chunk_bindata;
			if( $compression_type == 1 )
			{
				gunzip \$c_zcomp => \$chunk_bindata;
			}
			elsif( $compression_type == 2 )
			{
				$chunk_bindata = uncompress( $c_zcomp );
			}
			else
			{
				open( my $tmp, ">:bytes", "/tmp/comp.example" );
				print {$tmp} $c_zcomp;
				close $tmp;
				die "Unknown compression type [$compression_type]"; 
			}

			my $chunk_nbt = Minecraft::NBT->new_from_bindata( $chunk_bindata );
			$self->{chunk}->{$c_z}->{$c_x} = Minecraft::Chunk->new_from_nbt( $chunk_nbt );
			$self->{chunk}->{$c_z}->{$c_x}->time( $chunk_time );
		}
	}
	# save RAM
	delete $self->{bindata};
	delete $self->{offset};
	delete $self->{length};

	return $self;
}

#private
# get basic values from stream
sub next_data
{
	my( $self, $n ) = @_;
	if( $self->{offset} >= $self->{length} ) 
	{
		Carp::confess "out of data";
	}
	my $v = substr( $self->{bindata},$self->{offset},$n );
	$self->{offset}+=$n;
	return $v;
}
#private
# get values from stream and reverse them IF the system is littlendian
sub next_data_sort_endian
{
	my( $self, $n ) = @_;

	my $chars = $self->next_data( $n );

	# assume little endian
	return reverse $chars;
}
#private
sub next_byte
{
	my( $self ) = @_;
	
	return ord( $self->next_data(1) );
}
#private
sub next_int32
{
	my( $self ) = @_;
	my $t1 = $self->next_byte;
	my $t2 = $self->next_byte;
	my $t3 = $self->next_byte;
	my $t4 = $self->next_byte;
	return ($t1<<24) + ($t2<<16) + ($t3<<8) + $t4;
}

######################################################################

#private
sub to_bindata
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
			if( !defined $self->{chunk}->{$c_z}->{$c_x} )
			{
				push @$offset, chr(0).chr(0).chr(0).chr(0);
				push @$time_data, chr(0).chr(0).chr(0).chr(0);
				next X;
			}
			my $chunk = $self->{chunk}->{$c_z}->{$c_x};
			my $chunk_time = $chunk->time();
			my $chunk_nbt = $chunk->to_bindata();
			my $c_zcomp = compress( $chunk_nbt );
			my $length = length( $c_zcomp )+1;
		
			my $string = chr(($length>>24)&255).chr(($length>>16)&255).chr(($length>>8)&255).chr(($length)&255);
			$string .= chr(2);
			$string .= $c_zcomp;			

			if( length( $string ) % 4096 != 0 )
			{
				$string .= chr(0)x(4096-(length( $string ) % 4096));
			}
			if( length( $string ) % 4096 != 0 )
			{
				die "math fail";
			}
			my $sectors = length( $string )/4096;

			push @$chunk_data, $string;
			push @$offset, chr(($chunk_offset>>16)&255).chr(($chunk_offset>>8)&255).chr(($chunk_offset)&255).chr($sectors);
			push @$time_data, chr(($chunk_time>>24)&255).chr(($chunk_time>>16)&255).chr(($chunk_time>>8)&255).chr(($chunk_time)&255);
			$chunk_offset += $sectors;
		}
	}

	my $str = join( "", @$offset, @$time_data, @$chunk_data );
	return $str;
}

1;
