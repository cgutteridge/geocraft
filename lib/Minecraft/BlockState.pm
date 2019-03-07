
package Minecraft::BlockState;

use Data::Dumper;
use strict;
use warnings;

sub new {
	my( $class, $name, $properties ) = @_;

	$name = "minecraft:$name" unless $name =~ m/:/;
	$properties = {} unless defined $properties;
	my $self = bless {
		name=>$name,
		properties=>$properties,
	}, $class;
	return $self;
}

sub new_from_nbt {
	my( $class, $nbt ) = @_;

	my $self = bless {}, $class;
	$self->{name} =  $nbt->{Name}->v;
	$self->{properties} = {};
	if( $nbt->{Properies} ) {
		foreach my $k ( keys %{$nbt->{Properties}} ) {
			$self->{properties}->{$k} = $nbt->{Properties}->{$k}->v;
		}
	}
	return $self;
}

sub code {
	my( $self ) = @_;

	if( !defined $self->{code} ) {
		my @a = ($self->{name});
		foreach my $k ( sort keys %{$self->{properties}} ) {
			push @a,$k,$self->{properties}->{$k};
		}
		$self->{code} = join( ";", @a );
	}
	return $self->{code};
}

1;
