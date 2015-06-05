package Minecraft::NBT;
use strict;
use warnings;

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

sub from_string
{
	my( $class, $data ) = @_;

	my $self = bless {}, $class;
	$self->{data} = $data;
	$self->{offset} = 0;
	$self->{length} = length($data);

	my $tag = $self->tag;
	if( $self->{offset} < $self->{length} ) 
	{
		die "Warning, reached end of initial compound with data left\n";
	}

	return $tag;
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

	# print "GET: "; foreach my $char ( split //, $v ) { print sprintf( " %02X", ord($char) ); } print "\n";


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
	my $str =  $self->get($length);
	# print "#'$str'\n";
	return $str;
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
# print "TAG: $type\n";
	if( $type == 0 ) { return bless {}, "Minecraft::NBT::End"; }
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
	die "Unknown tag type: $type at offset ".($self->{offset}-1)."\n";
}
#1
sub tag_byte
{
	my( $self, $needs_name ) = @_;

	my $v = bless {}, "Minecraft::NBT::Byte";
	$v->{_name} = $self->string if( $needs_name );
	$v->{_value} = ord( $self->get(1) );
	return $v;
}
#2
sub tag_short
{
	my( $self, $needs_name ) = @_;

	my $v = bless {}, "Minecraft::NBT::Short";
	$v->{_name} = $self->string if( $needs_name );
	$v->{_value} = unpack('s', $self->gete(2) );
	return $v;
}
#3
sub tag_int
{
	my( $self, $needs_name ) = @_;

	my $v = bless {}, "Minecraft::NBT::Int";
	$v->{_name} = $self->string if( $needs_name );
	$v->{_value} = unpack('l', $self->gete(4) );
	return $v;
}
#4
sub tag_long
{
	my( $self, $needs_name ) = @_;

	my $v = bless {}, "Minecraft::NBT::Long";
	$v->{_name} = $self->string if( $needs_name );
	$v->{_value} = unpack('q', $self->gete(8) ); 
	return $v;
}
#5
sub tag_float
{
	my( $self, $needs_name ) = @_;

	my $v = bless {}, "Minecraft::NBT::Float";
	$v->{_name} = $self->string if( $needs_name );
	$v->{_value} = unpack('f', $self->gete(4) );
	return $v;
}
#6
sub tag_double
{
	my( $self, $needs_name ) = @_;

	my $v = bless {}, "Minecraft::NBT::Double";
	$v->{_name} = $self->string if( $needs_name );
	$v->{_value} = unpack('d', $self->gete(8) );
	return $v;
}
#7
sub tag_byte_array
{
	my( $self, $needs_name ) = @_;

	my $v = bless {}, "Minecraft::NBT::ByteArray";
	$v->{_name} = $self->string if( $needs_name );
	my $length = unpack('l', $self->gete(4) );
	$v->{_value} = $self->get( $length );
	return $v;
}
#8
sub tag_string
{
	my( $self, $needs_name ) = @_;

	my $v = bless {}, "Minecraft::NBT::String";
	$v->{_name} = $self->string if( $needs_name );
	$v->{_value} = $self->string;
	return $v;
}
#9
sub tag_list
{
	my( $self, $needs_name ) = @_;

	my $v = bless {}, "Minecraft::NBT::TagList";
	$v->{_name} = $self->string if( $needs_name );
	$v->{_type} = $self->byte;
	my $length = unpack('l', $self->gete(4) );
	$v->{_value} = [];
	for( my $i=0; $i<$length; ++$i )
	{
		push @{$v->{_value}}, $self->typed_tag( $v->{_type},0 );
	}
	return $v;
}
#10
sub tag_compound
{
	my( $self, $needs_name ) = @_;

	my $v = bless {}, "Minecraft::NBT::Compound";
	$v->{_name} = $self->string if( $needs_name );
	# print "COMPOUND TAG: ".$v->{_name}."\n";
	while(1)
	{
		my $child = $self->tag;
		if( $child->isa( "Minecraft::NBT::End" ) )
		{
			# print "END COMPOUND TAG: ".$v->{_name}."\n";
			return $v;
		}
		$v->{ $child->{_name} } = $child;
	}
}
#11
sub tag_int_array
{
	my( $self, $needs_name ) = @_;

	my $v = bless {}, "Minecraft::NBT::IntArray";
	$v->{_name} = $self->string if( $needs_name );
	my $length = unpack('l', $self->gete(4) );
	$v->{_value} = [];
	for( my $i=0; $i<$length; ++$i )
	{
		push @{$v->{_value}}, unpack('l', $self->gete(4) );
	}
	return $v;
}

1;

#######################################################################
#######################################################################
#######################################################################

package Minecraft::NBT::Compound;
use strict;
use warnings;

sub to_file
{
	my( $self, $filename ) = @_;

	my $out = $self->to_string();
	open( my $fh, ">:bytes", $filename ) || die "failed to write $filename: $!";
  	binmode $fh;
	syswrite( $fh, $out );
  	close $fh;
}


sub to_string
{
	my( $self ) = @_;

	$self->{_output} = [];
	$self->put_tag( $self, 1 );
	
	return join( "", @{$self->{_output}} );

}

sub hexdump 
{
	my( $data ) = @_;

	for( my $i=0;$i<length($data);$i+=16 )
	{
		for( my $j=0;$j<16;++$j )
		{
			print sprintf( "%02X ", ord( substr( $data,$i+$j,1)));
		}
		print "\n";
	}
}


# get basic values from stream
sub put
{
	my( $self, $chars ) = @_;

        if( utf8::is_utf8($chars) ) { utf8::encode($chars); }

	push @{$self->{_output}}, $chars;

	#print "PUT: "; foreach my $char ( split //, $chars ) { print sprintf( " %02X", ord($char) ); } print "\n";

}
# put values to stream and reverse them IF the system is littlendian
sub pute
{
	my( $self, $chars ) = @_;

	# assume little endian
	$chars = reverse $chars;

	$self->put( $chars );
}

sub put_byte
{
	my( $self, $byte ) = @_;
	
	$self->put( chr( $byte ));
}
sub put_string
{
	my( $self, $string ) = @_;

	# unsigned int
	$self->put( pack( 'n', length($string) ) );
	$self->put( $string );
}
sub put_tag
{
	my( $self, $tag, $needs_name ) = @_;

	if( ref($tag) eq "Minecraft::NBT::End" ) { die "unexpected END"; }
	elsif( ref($tag) eq "Minecraft::NBT::Byte" ) { $self->put_tag_byte( $tag, $needs_name ); }
	elsif( ref($tag) eq "Minecraft::NBT::Short" ) { $self->put_tag_short( $tag, $needs_name ); }
	elsif( ref($tag) eq "Minecraft::NBT::Int" ) { $self->put_tag_int( $tag, $needs_name ); }
	elsif( ref($tag) eq "Minecraft::NBT::Long" ) { $self->put_tag_long( $tag, $needs_name ); }
	elsif( ref($tag) eq "Minecraft::NBT::Float" ) { $self->put_tag_float( $tag, $needs_name ); }
	elsif( ref($tag) eq "Minecraft::NBT::Double" ) { $self->put_tag_double( $tag, $needs_name ); }
	elsif( ref($tag) eq "Minecraft::NBT::ByteArray" ) { $self->put_tag_byte_array( $tag, $needs_name ); }
	elsif( ref($tag) eq "Minecraft::NBT::String" ) { $self->put_tag_string( $tag, $needs_name ); }
	elsif( ref($tag) eq "Minecraft::NBT::TagList" ) { $self->put_tag_list( $tag, $needs_name ); }
	elsif( ref($tag) eq "Minecraft::NBT::Compound" ) { $self->put_tag_compound( $tag, $needs_name ); }
	elsif( ref($tag) eq "Minecraft::NBT::IntArray" ) { $self->put_tag_int_array( $tag, $needs_name ); }
	else { Carp::confess "Unknown tag type: ".ref($tag); }
}
#1
sub put_tag_byte
{
	my( $self, $tag, $needs_name ) = @_;
#print "PUTTING TAG BYTE: ".$tag->{_name}." -- ".$tag->{_value}."\n";
	$self->put_byte(1) if( $needs_name );
	$self->put_string( $tag->{_name} ) if( $needs_name );
	$self->put_byte($tag->{_value});
}
#2
sub put_tag_short
{
	my( $self, $tag, $needs_name ) = @_;

	$self->put_byte(2) if( $needs_name );
	$self->put_string( $tag->{_name} ) if( $needs_name );

	$self->pute( pack( 's', $tag->{_value} ) );
}
#3
sub put_tag_int
{
	my( $self, $tag, $needs_name ) = @_;

	$self->put_byte(3) if( $needs_name );
	$self->put_string( $tag->{_name} ) if( $needs_name );

	$self->pute( pack( 'l', $tag->{_value} ) );
}
#4
sub put_tag_long
{
	my( $self, $tag, $needs_name ) = @_;

	$self->put_byte(4) if( $needs_name );
	$self->put_string( $tag->{_name} ) if( $needs_name );

	$self->pute( pack( 'j', $tag->{_value} ) );
}
#5
sub put_tag_float
{
	my( $self, $tag, $needs_name ) = @_;

	$self->put_byte(5) if( $needs_name );
	$self->put_string( $tag->{_name} ) if( $needs_name );

	$self->pute( pack( 'f', $tag->{_value} ) );
}
#6
sub put_tag_double
{
	my( $self, $tag, $needs_name ) = @_;

	$self->put_byte(6) if( $needs_name );
	$self->put_string( $tag->{_name} ) if( $needs_name );

	$self->pute( pack( 'd', $tag->{_value} ) );
}
#7
sub put_tag_byte_array
{
	my( $self, $tag, $needs_name ) = @_;

	$self->put_byte(7) if( $needs_name );
	$self->put_string( $tag->{_name} ) if( $needs_name );

	$self->pute( pack( 'l', length($tag->{_value}) ) );
	$self->put( $tag->{_value} );
}
#8
sub put_tag_string
{
	my( $self, $tag, $needs_name ) = @_;

	$self->put_byte(8) if( $needs_name );
	$self->put_string( $tag->{_name} ) if( $needs_name );

	$self->put_string( $tag->{_value} );
}
#9
sub put_tag_list
{
	my( $self, $tag, $needs_name ) = @_;

	$self->put_byte(9) if( $needs_name );
	$self->put_string( $tag->{_name} ) if( $needs_name );

	$self->put_byte( $tag->{_type} );
	$self->pute( pack( 'l', scalar(@{$tag->{_value}}) ) );
	foreach my $tag_i ( @{$tag->{_value}} )
	{
		$self->put_tag( $tag_i, 0 );
	}
}
#10
sub put_tag_compound
{
	my( $self, $tag, $needs_name ) = @_;

#print "TAG COMPOUND: ".$tag->{_name}."\n";
	$self->put_byte(10) if( $needs_name );
	$self->put_string( $tag->{_name} ) if( $needs_name );

	foreach my $key ( keys %{$tag} )
	{
		next if $key =~ m/^_/;
		$self->put_tag( $tag->{$key}, 1 );
	}
	$self->put_byte(0); # End tag.
#print "ENDTAG COMPOUND: ".$tag->{_name}."\n";
}
#11
sub put_tag_int_array
{
	my( $self, $tag, $needs_name ) = @_;

	$self->put_byte(11) if( $needs_name );
	$self->put_string( $tag->{_name} ) if( $needs_name );

	$self->pute( pack( 'l', scalar(@{$tag->{_value}}) ) );
	foreach my $value ( @{$tag->{_value}} )
	{
		$self->pute( pack( 'l', $value ));
	}
}

1;

