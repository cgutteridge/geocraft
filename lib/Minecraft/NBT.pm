package Minecraft::NBT;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError) ;
use strict;
use warnings;
use Data::Dumper;

sub new_from_file
{
	my( $class, $filename ) = @_;

	local $/ = undef;
	open( my $fh, "<:bytes", $filename ) || die "failed to open $filename: $!";
  	binmode $fh;
  	my $bindata = <$fh>;
  	close $fh;

	return $class->new_from_bindata( $bindata );
}
sub new_from_gzip_file
{
	my( $class, $filename ) = @_;

	local $/ = undef;
	open( my $fh, "<:bytes", $filename ) || die "failed to open $filename: $!";
  	binmode $fh;
  	my $data = <$fh>;
  	close $fh;
	my $bindata;	
	gunzip \$data => \$bindata;

	return $class->new_from_bindata( $bindata );
}

sub new_from_bindata
{
	my( $class, $bindata ) = @_;

	my $self = bless {}, $class;
	$self->{data} = $bindata;
	$self->{offset} = 0;
	$self->{length} = length($bindata);

	$self->{debug} = 0;

	print "STARTING NBT PARSE (".$self->{length}.")\n" if $self->{debug};
	my $tag = $self->next_tag;
	if( $self->{offset} < $self->{length} ) 
	{
		die "Warning, reached end of initial compound with data left\n";
	}
	print "ENDED NBT PARSE (".$self->{length}.")\n" if $self->{debug};

	# save RAM
	delete $self->{data};
	delete $self->{offset};
	delete $self->{length};

	return $tag;
}

# get basic values from stream
sub next_data
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
sub next_data_sort_endian
{
	my( $self, $n ) = @_;

	my $chars = $self->next_data( $n );

	# assume little endian
	return reverse $chars;
}

	
sub next_byte
{
	my( $self ) = @_;
	
	return ord( $self->next_data(1) );
}
sub next_string
{
	my( $self ) = @_;

	# unsigned int
	my $length = unpack('n', $self->next_data(2) );
	my $str =  $self->next_data($length);
	# print "#'$str'\n";
	return $str;
}
sub next_tag	
{
	my( $self ) = @_;

	my $type = $self->next_byte;
	my $v = $self->next_typed_tag( $type,1 );
	return $v;
}
sub next_typed_tag
{
	my( $self, $type, $needs_name ) = @_;
	print "TAG: $type\n" if $self->{debug};
	if( $type == 0 ) { return bless {}, "Minecraft::NBT::End"; }
	if( $type == 1 ) { return $self->next_tag_byte( $needs_name ); }
	if( $type == 2 ) { return $self->next_tag_short( $needs_name ); }
	if( $type == 3 ) { return $self->next_tag_int( $needs_name ); }
	if( $type == 4 ) { return $self->next_tag_long( $needs_name ); }
	if( $type == 5 ) { return $self->next_tag_float( $needs_name ); }
	if( $type == 6 ) { return $self->next_tag_double( $needs_name ); }
	if( $type == 7 ) { return $self->next_tag_byte_array( $needs_name ); }
	if( $type == 8 ) { return $self->next_tag_string( $needs_name ); }
	if( $type == 9 ) { return $self->next_tag_list( $needs_name ); }
	if( $type == 10 ) { return $self->next_tag_compound( $needs_name ); }
	if( $type == 11 ) { return $self->next_tag_int_array( $needs_name ); }
	if( $type == 12 ) { return $self->next_tag_long_array( $needs_name ); }
	die "Unknown tag type: $type at offset ".($self->{offset}-1)."\n";
}
#1
sub next_tag_byte
{
	my( $self, $needs_name ) = @_;

	my $v = bless {}, "Minecraft::NBT::Byte";
	$v->{_name} = $self->next_string if( $needs_name );
	$v->{_value} = ord( $self->next_data(1) );
	return $v;
}
#2
sub next_tag_short
{
	my( $self, $needs_name ) = @_;

	my $v = bless {}, "Minecraft::NBT::Short";
	$v->{_name} = $self->next_string if( $needs_name );
	$v->{_value} = unpack('s', $self->next_data_sort_endian(2) );
	return $v;
}
#3
sub next_tag_int
{
	my( $self, $needs_name ) = @_;

	my $v = bless {}, "Minecraft::NBT::Int";
	$v->{_name} = $self->next_string if( $needs_name );
	$v->{_value} = unpack('l', $self->next_data_sort_endian(4) );
	return $v;
}
#4
sub next_tag_long
{
	my( $self, $needs_name ) = @_;

	my $v = bless {}, "Minecraft::NBT::Long";
	$v->{_name} = $self->next_string if( $needs_name );
	$v->{_value} = unpack('q', $self->next_data_sort_endian(8) ); 
	return $v;
}
#5
sub next_tag_float
{
	my( $self, $needs_name ) = @_;

	my $v = bless {}, "Minecraft::NBT::Float";
	$v->{_name} = $self->next_string if( $needs_name );
	$v->{_value} = unpack('f', $self->next_data_sort_endian(4) );
	return $v;
}
#6
sub next_tag_double
{
	my( $self, $needs_name ) = @_;

	my $v = bless {}, "Minecraft::NBT::Double";
	$v->{_name} = $self->next_string if( $needs_name );
	$v->{_value} = unpack('d', $self->next_data_sort_endian(8) );
	return $v;
}
#7
sub next_tag_byte_array
{
	my( $self, $needs_name ) = @_;

	my $v = bless {}, "Minecraft::NBT::ByteArray";
	$v->{_name} = $self->next_string if( $needs_name );
	my $length = unpack('l', $self->next_data_sort_endian(4) );
	$v->{_value} = $self->next_data( $length );
	return $v;
}
#8
sub next_tag_string
{
	my( $self, $needs_name ) = @_;

	my $v = bless {}, "Minecraft::NBT::String";
	$v->{_name} = $self->next_string if( $needs_name );
	$v->{_value} = $self->next_string;
	return $v;
}
#9
sub next_tag_list
{
	my( $self, $needs_name ) = @_;

	my $v = bless {}, "Minecraft::NBT::TagList";
	$v->{_name} = $self->next_string if( $needs_name );
	$v->{_type} = $self->next_byte;
	my $length = unpack('l', $self->next_data_sort_endian(4) );
	$v->{_value} = [];
	for( my $i=0; $i<$length; ++$i )
	{
		push @{$v->{_value}}, $self->next_typed_tag( $v->{_type},0 );
	}
	return $v;
}
#10
sub next_tag_compound
{
	my( $self, $needs_name ) = @_;

	my $v = bless {}, "Minecraft::NBT::Compound";
	$v->{_name} = $self->next_string if( $needs_name );
        if( $self->{debug} ) {
		if( $needs_name ) {
			print "COMPOUND TAG: ".$v->{_name}."\n";
		} else {
			print "ANONYMOUS COMPOUND TAG\n";
		}
	}
	while(1)
	{
		my $child = $self->next_tag;
		if( $child->isa( "Minecraft::NBT::End" ) )
		{
        		if( $self->{debug} ) {
				if( $needs_name ) {
					print "END COMPOUND TAG: ".$v->{_name}."\n";
				} else {
					print "END ANONYMOUS COMPOUND TAG\n";
				}
			}
			return $v;
		}
		$v->{ $child->{_name} } = $child;
	}
}
#11
sub next_tag_int_array
{
	my( $self, $needs_name ) = @_;

	my $v = bless {}, "Minecraft::NBT::IntArray";
	$v->{_name} = $self->next_string if( $needs_name );
	my $length = unpack('l', $self->next_data_sort_endian(4) );
	$v->{_value} = [];
	for( my $i=0; $i<$length; ++$i )
	{
		push @{$v->{_value}}, unpack('l', $self->next_data_sort_endian(4) );
	}
	return $v;
}
#12
sub next_tag_long_array
{
	my( $self, $needs_name ) = @_;

	my $v = bless {}, "Minecraft::NBT::LongArray";
	$v->{_name} = $self->next_string if( $needs_name );
	my $length = unpack('l', $self->next_data_sort_endian(4) );
	$v->{_value} = [];
	for( my $i=0; $i<$length; ++$i )
	{
		push @{$v->{_value}}, unpack('q', $self->next_data_sort_endian(8) );
	}
	return $v;
}
1;

#######################################################################
#######################################################################
#######################################################################

package Minecraft::NBT::Compound;
use IO::Compress::Gzip qw(gzip $GzipError) ;
use strict;
use warnings;

sub to_file
{
	my( $self, $filename ) = @_;

	my $out = $self->to_bindata();
	open( my $fh, ">:bytes", $filename ) || die "failed to write $filename: $!";
  	binmode $fh;
	syswrite( $fh, $out );
  	close $fh;
}
sub to_gzip_file
{
	my( $self, $filename ) = @_;

	my $out = $self->to_bindata();
	my $zipped;
	gzip \$out=>\$zipped;

	open( my $fh, ">:bytes", $filename ) || die "failed to write $filename: $!";
  	binmode $fh;
	syswrite( $fh, $zipped );
  	close $fh;
}


sub to_bindata
{
	my( $self ) = @_;

	$self->{_output} = [];
	$self->put_tag( $self, 1 );
	
	return join( "", @{$self->{_output}} );

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

	# unsigned int of strlen
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
	elsif( ref($tag) eq "Minecraft::NBT::LongArray" ) { $self->put_tag_long_array( $tag, $needs_name ); }
	else { Carp::confess "Unknown tag type: ".ref($tag)." '$tag'"; }
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
print "($key)\n";
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
#12
sub put_tag_long_array
{
	my( $self, $tag, $needs_name ) = @_;

	$self->put_byte(11) if( $needs_name );
	$self->put_string( $tag->{_name} ) if( $needs_name );

	$self->pute( pack( 'l', scalar(@{$tag->{_value}}) ) );
	foreach my $value ( @{$tag->{_value}} )
	{
		$self->pute( pack( 'q', $value ));
	}
}
1;

