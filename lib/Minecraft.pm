package Minecraft;

use strict;
use warnings;
use Minecraft::NBT;
use Minecraft::NBT::Tag;
use Minecraft::Chunk;
use Minecraft::Section;
use Minecraft::Region;
use Minecraft::World;
use Minecraft::BlockTypes;
use Minecraft::BlockState;

sub new
{
	my( $class, $dir ) = @_;

	if( !-d $dir )
	{
		die "no such saves dir: $dir";
	}
	
	my $self = bless { dir=>$dir }, $class;

	return $self;
}

sub world
{
	my( $self, $world_name, %opts ) = @_;

	return Minecraft::World->new( $self->{dir}."/$world_name", \%opts );
}

1;
