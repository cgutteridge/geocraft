
package Minecraft::Chunk;

# A vertical 16x16 shaft

use Data::Dumper;
use strict;
use warnings;

sub new {
	my( $class, $c_x,$c_z, $opts ) = @_;

	my $level = bless { _name=>"Level" }, "Minecraft::NBT::Compound";	
	my $self = bless {
		opts => $opts, 
		timestamp => time(),
	},$class;

	$level->{Biomes} = bless { _name=>"Biomes", _value=>chr(0)x256 }, 'Minecraft::NBT::ByteArray';
	$level->{xPos} = bless { _name=>"xPos", _value=>$self->{opts}->{r_x}*32+$c_x }, 'Minecraft::NBT::Int';
	$level->{zPos} = bless { _name=>"zPos", _value=>$self->{opts}->{r_z}*32+$c_z }, 'Minecraft::NBT::Int';
	#$level->{Entities} = bless { _name=>"Entities", _value=>[], _type=>10 }, 'Minecraft::NBT::TagList';
	#$level->{TileEntities} = bless { _name=>"TileEntities", _value=>[], _type=>10 }, 'Minecraft::NBT::TagList';
	#$level->{LastUpdate} = bless { _name=>"LastUpdate", _value=>0 }, 'Minecraft::NBT::Long';
	#$level->{TerrainPopulated} = bless { _name=>"TerrainPopulated", _value=>1 }, 'Minecraft::NBT::Byte';
	#$level->{LightPopulated} = bless { _name=>"LightPopulated", _value=>1 }, 'Minecraft::NBT::Byte';
	#$level->{HeightMap} = bless { _name=>"HeightMap", _value=>[] }, 'Minecraft::NBT::IntArray';
	#for( 0..255 ) { push @{$level->{HeightMap}->{_value}},0; }

	my $version = bless { _name=>"DataVersion", _value=>1631 }, 'Minecraft::NBT::Int';
	$self->{nbt} = bless {
		DataVersion => $version,
		Level => $level,
	}, "Minecraft::NBT::Compound";	

	$self->{sections} = [];
	if( defined $self->{opts}->{init_chunk} )
	{
		&{$self->{opts}->{init_chunk}}( $self, $c_x, $c_z );
	}

	return $self;	
}

# STATIC
sub new_from_nbt {
	my( $class, $nbt ) = @_;

	my $self = bless {}, $class;
	$self->{time} = 0;
	$self->{nbt} = $nbt;
	$self->{sections} = [];
	foreach my $nbt_section ( @{$self->{nbt}->{Level}->{Sections}->{_value}} ) {
		my $section = Minecraft::Section->new_from_nbt($nbt_section);
		push @{$self->{sections}}, $section;
	}
	# don't waste RAM by storing two copies
	delete $self->{nbt}->{Level}->{Sections};

	return $self;
}

sub to_bindata {
	my( $self ) = @_;

	# recreate sections NBT to save
	$self->{nbt}->{Level}->{Sections} = bless { _name=>"Entities", _value=>[], _type=>10 }, 'Minecraft::NBT::TagList';

	foreach my $section ( @{$self->{sections}} ) {
		push @{$self->{nbt}->{Level}->{Sections}->{_value}}, $section->to_nbt;
	}

	my $bindata = $self->{nbt}->to_bindata;
	delete $self->{nbt}->{Level}->{Sections};
	return $bindata
}


sub debug {
	my( $self ) = @_;

	print "**CHUNK**\n";
	$self->{nbt}->debug(1);
}

# get or set timestamp
sub time {
	my( $self, $time ) = @_;

	if( defined $time ) {
		$self->{time} = $time;
	} else {
		return $self->{time};
	}
}
	
# return the section containing the height $y or undef
# if region is set, new sections will be created and _changed set on reigion if needed
sub block_section {
	my( $self, $y, $region ) = @_;

	my $section_y = POSIX::floor($y/16);
	if( defined $region && !defined $self->{sections}->[$section_y] ) 
	{
		for( my $section_y_i=0; $section_y_i<=$section_y; ++$section_y_i )
		{
			next if( defined $self->{sections}->[$section_y_i] );
			$self->{sections}->[$section_y_i] = Minecraft::Section->new( $section_y_i );
			$region->{_changed} = 1;
		}
	}
	my $section = $self->{sections}->[$section_y];
	return $section;
}


1;
