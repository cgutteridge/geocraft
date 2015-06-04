package Minecraft::NBT::Tag;

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
@Minecraft::NBT::End::ISA = ( "Minecraft::NBT::Tag" );
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

1;

