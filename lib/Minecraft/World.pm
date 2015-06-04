
package Minecraft::World;

use IO::Uncompress::Gunzip qw(gunzip $GunzipError) ;
use IO::Compress::Gzip qw(gzip $GzipError) ;
use Data::Dumper;

use strict;
use warnings;

sub new
{
	my( $class, $dir ) = @_;

	if( !-d $dir )
	{
		die "no world directory $dir";
	}
	
	my $self = bless { dir=>$dir },$class;	

	$self->read_level;

	$self->{level}->{_changed} = 1;
	$self->{level}->{Data}->{raining}->v(1);
	$self->save;
}

sub save
{
	my( $self ) = @_;

	my $acted = 0;
	
	if( $self->{level}->{_changed} )
	{
		print "SAVING LEVEL.DAT\n";
		$self->save_level;
		$acted = 1;
	}

	if( !$acted )
	{
		print "Did not save anything!\n";
	}
}

sub save_level
{
	my( $self ) = @_;

	my $level_file = $self->{dir}."/level.dat";
	my $buffer = $self->{level}->to_string();
	gzip \$buffer => $level_file;
	$self->{level}->{_changed} = 0;
}

sub read_level
{
	my( $self ) = @_;

	my $level_file = $self->{dir}."/level.dat";
	my $buffer;
	gunzip $level_file => \$buffer;
	print length($buffer);
	$self->{level}->{_changed} = 0;
	$self->{level} = Minecraft::NBT->from_string( $buffer );
}

1;
