package Minecraft::NBT::Parser;

sub new
{
	my( $class ) = @_;

	return bless {}, $class;
}

sub parse_file
{
	my( $self,$filename ) = @_;

	local $/ = undef;
	open( my $fh, "<", $filename ) || die "failed to open $filename: $!";
  	binmode $fh;
  	my $data = <$fh>;
  	close $fh;

	return $self->parse_string( $data );
}

sub parse_string
{
	my( $self, $data ) = @_;

	$self->{data} = $data;
	$self->{offset} = 0;
	$self->{length} = length($data);
	return $self->tag;
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
sub string
{
	my( $self ) = @_;

	# unsigned int
	my $length = unpack('n', $self->get(2) );
	return $self->get($length);
}
sub tag	
{
	my( $self ) = @_;

	my $type = $self->byte;
	my $v = $self->typed_tag( $type,1 );
	return $v;
}
sub typed_tag
{
	my( $self, $type, $needs_name ) = @_;

	if( $type == 0 ) { return bless {}, "Minecraft::NBT::Tag::End"; }
	if( $type == 1 ) { return $self->tag_byte( $needs_name ); }
	if( $type == 2 ) { return $self->tag_short( $needs_name ); }
	if( $type == 3 ) { return $self->tag_int( $needs_name ); }
	if( $type == 4 ) { return $self->tag_long( $needs_name ); }
	if( $type == 5 ) { return $self->tag_float( $needs_name ); }
	if( $type == 6 ) { return $self->tag_double( $needs_name ); }
	if( $type == 7 ) { return $self->tag_byte_array( $needs_name ); }
	if( $type == 8 ) { return $self->tag_string( $needs_name ); }
	if( $type == 9 ) { return $self->tag_list( $needs_name ); }
	if( $type == 10 ) { return $self->tag_compound( $needs_name ); }
	if( $type == 11 ) { return $self->tag_int_array( $needs_name ); }
	die "Unknown tag type: $type\n";
}
#1
sub tag_byte
{
	my( $self, $needs_name ) = @_;

	my $v = bless {}, "Minecraft::NBT::Tag::Byte";
	$v->{name} = $self->string if( $needs_name );
	$v->{value} = ord( $self->get(1) );
	return $v;
}
#2
sub tag_short
{
	my( $self, $needs_name ) = @_;

	my $v = bless {}, "Minecraft::NBT::Tag::Short";
	$v->{name} = $self->string if( $needs_name );
	$v->{value} = unpack('s', $self->gete(2) );
	return $v;
}
#3
sub tag_int
{
	my( $self, $needs_name ) = @_;

	my $v = bless {}, "Minecraft::NBT::Tag::Int";
	$v->{name} = $self->string if( $needs_name );
	$v->{value} = unpack('l', $self->gete(4) );
	return $v;
}
#4
sub tag_long
{
	my( $self, $needs_name ) = @_;

	my $v = bless {}, "Minecraft::NBT::Tag::Long";
	$v->{name} = $self->string if( $needs_name );
	$v->{value} = unpack('q', $self->gete(8) ); 
	return $v;
}
#5
sub tag_float
{
	my( $self, $needs_name ) = @_;

	my $v = bless {}, "NBT::Tag::Float";
	$v->{name} = $self->string if( $needs_name );
	$v->{value} = unpack('f', $self->gete(4) );
	return $v;
}
#6
sub tag_double
{
	my( $self, $needs_name ) = @_;

	my $v = bless {}, "NBT::Tag::Double";
	$v->{name} = $self->string if( $needs_name );
	$v->{value} = unpack('d', $self->gete(8) );
	return $v;
}
#7
sub tag_byte_array
{
	my( $self, $needs_name ) = @_;

	my $v = bless {}, "NBT::Tag::ByteArray";
	$v->{name} = $self->string if( $needs_name );
	$v->{length} = unpack('l', $self->gete(4) );
	$v->{value} = $self->get( $v->{length} );
	return $v;
}
#8
sub tag_string
{
	my( $self, $needs_name ) = @_;

	my $v = bless {}, "NBT::Tag::String";
	$v->{name} = $self->string if( $needs_name );
	$v->{value} = $self->string;
	return $v;
}
#9
sub tag_list
{
	my( $self, $needs_name ) = @_;

	my $v = bless {}, "NBT::Tag::TagList";
	$v->{name} = $self->string if( $needs_name );
	$v->{type} = $self->byte;
	$v->{length} = unpack('l', $self->gete(4) );
	$v->{value} = [];
	for( my $i=0; $i<$v->{length}; ++$i )
	{
		push @{$v->{value}}, $self->typed_tag( $v->{type},0 );
	}
	return $v;
}
#10
sub tag_compound
{
	my( $self, $needs_name ) = @_;

	my $v = bless {children=>{}}, "NBT::Tag::Compound";
	$v->{name} = $self->string if( $needs_name );
	while(1)
	{
		my $child = $self->tag;
		return $v if( $child->isa( "Minecraft::NBT::Tag::End" ) );
		$v->{children}->{ $child->{name} } = $child;
	}
}

1;
