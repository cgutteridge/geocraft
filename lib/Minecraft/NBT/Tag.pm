package Minecraft::NBT::Tag;

use Data::Dumper;

@Minecraft::NBT::End::ISA = ( "Minecraft::NBT::Tag" );
@Minecraft::NBT::Byte::ISA = ( "Minecraft::NBT::Tag" );
@Minecraft::NBT::Short::ISA = ( "Minecraft::NBT::Tag" );
@Minecraft::NBT::Int::ISA = ( "Minecraft::NBT::Tag" );
@Minecraft::NBT::Long::ISA = ( "Minecraft::NBT::Tag" );
@Minecraft::NBT::Float::ISA = ( "Minecraft::NBT::Tag" );
@Minecraft::NBT::Double::ISA = ( "Minecraft::NBT::Tag" );
@Minecraft::NBT::ByteArray::ISA = ( "Minecraft::NBT::Tag" );
@Minecraft::NBT::String::ISA = ( "Minecraft::NBT::Tag" );
@Minecraft::NBT::TagList::ISA = ( "Minecraft::NBT::Tag" );
@Minecraft::NBT::Compound::ISA = ( "Minecraft::NBT::Tag" );
@Minecraft::NBT::IntArray::ISA = ( "Minecraft::NBT::Tag" );

sub v
{
	my ( $self, $v ) = @_;
	if( defined $v )
	{
		$self->{_value} = $v;
		return;
	}
	return $self->{_value};
}

sub debug
{
	my( $self, $depth, $path ) = @_;
	$depth=0 if !defined $depth;
	print "  "x$depth;
	print $self->{_value}."\n";
}

package Minecraft::NBT::Compound;

sub debug
{
	my( $self, $depth, $path ) = @_;

	foreach my $key ( keys %$self )
	{	
		next if $key eq "_name";
		print "  "x$depth;
		print "$path/$key:\n";
		$self->{$key}->debug( $depth + 1, "$path/$key" );
	}
}
package Minecraft::NBT::TagList;
use Data::Dumper;

sub debug
{
	my( $self, $depth, $path ) = @_;
	for( my $i=0; $i<scalar @{$self->{_value}};++$i )
	{	
		print "  "x$depth;
		print "$path/#".$i.":\n";
		$self->{_value}->[$i]->debug( $depth + 1, "$path/#$i" );
	}
}

package Minecraft::NBT::IntArray;

sub debug
{
	my( $self, $depth, $path ) = @_;

	print "  "x$depth;
	print join(" ",@{$self->{_value}} )."\n";
}

package Minecraft::NBT::ByteArray;

sub debug
{
	my( $self, $depth, $path ) = @_;

	if( length( $self->{_value} ) == 2048 )
	{
		my $row = 0;
		for( my $i=0;$i<length($self->{_value});$i+=8 )
		{
			if( ($i%128)==0 ){ 
				print "  "x$depth;
				print "$path/$row\n";
				++$row;
			}
			print "  "x$depth;
			for( my $j=0;$j<8;++$j )
			{
				print sprintf( "%02X ", ord( substr( $self->{_value},$i+$j,1)));
			}
			print "\n";
		}
	}
	else
	{
		my $row = 0;
		for( my $i=0;$i<length($self->{_value});$i+=16 )
		{
			if( ($i%256)==0 ){ 
				print "  "x$depth;
				print "$path/$row\n";
				++$row;
			}
			print "  "x$depth;
			for( my $j=0;$j<16;++$j )
			{
				print sprintf( "%02X ", ord( substr( $self->{_value},$i+$j,1)));
			}
			print "\n";
		}
	}
}


1;

