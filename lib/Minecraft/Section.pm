
package Minecraft::Section;

# a 16x16x16 cube

use Data::Dumper;
use strict;
use warnings;

sub new {
	my( $class, $y ) = @_;

	my $self = bless {}, $class;

	$self->{nbt} = bless( {}, "Minecraft::NBT::Compound"  );
	$self->{nbt}->{Y} = bless { _name=>"Y", _value=>$y }, "Minecraft::NBT::Byte";
	$self->{nbt}->{BlockLight} = bless { _name=>"BlockLight", _value=>chr(0)x2048 }, "Minecraft::NBT::ByteArray";
	$self->{nbt}->{SkyLight} = bless { _name=>"SkyLight", _value=>chr(255)x2048 }, "Minecraft::NBT::ByteArray";
	$self->{blocks} = [];
	$self->{palette} = {};
	my $blockstate = Minecraft::BlockState->new( "air" );
	$self->{palette}->{$blockstate->code} = $blockstate;
	for my $i ( 0..4095 ) {
		$self->{blocks}->[$i] = $blockstate;
	}
	return $self;
}

sub new_from_nbt {
	my( $class, $nbt ) = @_;

	my $self = bless {}, $class;
	$self->{nbt} = $nbt;
	$self->{blocks} = [];
	$self->{palette} = {};

	my @load_palette = ();
	foreach my $p ( @{$self->{nbt}->{Palette}->{_value}} ) {
		my $blockstate = Minecraft::BlockState->new_from_nbt( $p );
		if( !defined $self->{palette}->{$blockstate->code} ) {
			$self->{palette}->{$blockstate->code} = $blockstate;
		}
		push @load_palette, $blockstate;
	}	
	my $n = scalar @load_palette;
	my $bits = 4;
	if( $n > 16 ) {
		$bits = int( 1+log($n-1)/log(2) );
	}
	my $states = "";
	foreach my $state ( @{ $self->{nbt}->{BlockStates}->{_value} } ) {
		$states .= pack("Q",$state);
	}
	for my $i ( 0..4095 ) {
		my $index = 0;	
		my @ba = ();
		for my $bit ( 0..$bits-1 ) {
#print "(".($i*$bits+$bit).")\n";
			if( vec( $states, $i*$bits+$bit, 1 ) ) {
				push @ba,1;
				$index |= 1<<($bit);
			} else {
				push @ba,0;
			}
		}

		if( !defined  $load_palette[$index] ) { 
			die "i=$i, index=$index, max=$n, bits=$bits, array=".join("",@ba);
		}
#print "=$index\n";
		$self->{blocks}->[$i] = $load_palette[$index];
	}
	# no point in remembering stuff twice
	delete $self->{nbt}->{BlockStates};
	delete $self->{nbt}->{Palette};

	return $self;	
}

sub to_nbt {
	my( $self ) = @_;

	# clone basic NBT stuff
	my $nbt = bless( {}, "Minecraft::NBT::Compound"  );
	foreach my $key ( keys %{$self->{nbt}} ) {
		$nbt->{$key} = $self->{nbt}->{$key};
	}
	$nbt->{Palette} = bless( { _name=>"Palette", _value=>[], _type=>9 }, "Minecraft::NBT::TagList" );
	$nbt->{BlockStates} = bless( { _name=>"BlockStates", _value=>[], _type=>12 }, "Minecraft::NBT::LongArray" );

	# add palette and sections
	my $palette = {};
	for my $i ( 0..4095 ) {
		next if defined $palette->{$self->{blocks}->[$i]->code};
		$palette->{$self->{blocks}->[$i]->code} = $self->{blocks}->[$i];
	}
	my @codes = sort keys %$palette;
	my $n = scalar @codes;
	my $codemap = {};
	foreach my $i ( 0..$n-1 ) {
		$codemap->{$codes[$i]} = $i;
	}
	my $bits = 4;
	if( $n > 16 ) {
		$bits = int( 1+log($n-1)/log(2) );
	}

		#$states .= pack("Q",$state);
	my $states = "";
	for my $i ( 0..4095 ) {
		my $index = $codemap->{$self->{blocks}->[$i]->code};
		for my $bit ( 0..$bits-1 ) {
			my $v = ($index & 1<<$bit)?1:0;
			vec( $states, $i*$bits+$bit, 1 ) = $v;
		}
	}
	for( my $offset=0; $offset<length($states); $offset+=8 ) {
		push @{ $nbt->{BlockStates}->{_value} }, unpack( "Q", substr($states,$offset,8));
	}
$nbt->debug;
	return $nbt;
}

sub set_block {
	my( $self, $rel_x,$rel_y,$rel_z, $blockstate ) = @_;

	if( !defined $self->{palette}->{$blockstate->code} ) {
		$self->{palette}->{$blockstate->code} = $blockstate;
	}
	return $self->{blocks}->[$rel_y*256+$rel_z*16+$rel_x] = $blockstate;
}
	

sub debug {
	my( $self ) = @_;

	print "**SECTION**\n";
	$self->{nbt}->debug(1);
	print "****SECTION BLOCKS**\n";
	foreach my $y ( 0..15 ) {
		foreach my $z ( 0..15 ) {
			foreach my $x ( 0..15 ) {
				my $blockstate = $self->{blocks}->[$y*256+$z*16+$x];
				if( !defined $blockstate ) {
					die "no blockstate in section, rel pos ($x,$y,$z)";
				}
				print sprintf( "%2d,%2d,%2d : %s\n",$x,$y,$z,$self->{blocks}->[$y*256+$z*16+$x]->code );
			}
		}
	}
}

1;

