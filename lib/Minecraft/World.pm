
package Minecraft::World;

use IO::Uncompress::Gunzip qw(gunzip $GunzipError) ;
use IO::Compress::Gzip qw(gzip $GzipError) ;
use Data::Dumper;
use POSIX;

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

	$self->{regions} = {};

	return $self;
}

sub c
{
	my( $x,$y,$z ) = @_;
	
	my $rx = abs($x)%512;
	my $rz = abs($z)%512;

	$rx = 512-$rx if $x<0;
	$rz = 512-$rz if $z<0;

	return ($rx,$y,$rz);
}
sub get_block
{
	my( $self,   $x,$y,$z ) = @_;


	return $self->block_region( $x,$y,$z )->get_block( c($x,$y,$z) );
}
sub set_block
{
	my( $self,   $x,$y,$z, $id ) = @_;

	return $self->block_region( $x,$y,$z )->set_block( c($x,$y,$z), $id );
}

sub block_region
{
	my( $self,   $x,$y,$z ) = @_;
	return $self->region( POSIX::floor($x/512),POSIX::floor($z/512) );
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
	
	foreach my $r_z ( sort keys %{$self->{regions}} )
	{
		foreach my $r_x ( sort keys %{$self->{regions}->{$r_z}} )
		{
			if( $self->{regions}->{$r_z}->{$r_x}->{_changed} )
			{
				my $filename = "r.$r_x.$r_z.mca";
				print "SAVING REGION $filename .. ";
				$self->{regions}->{$r_z}->{$r_x}->to_file( $self->{dir}."/region/$filename" ); 
				$self->{regions}->{$r_z}->{$r_x}->{_changed} = 0;
				$acted = 1;
				print "done\n";
			}
		}
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
	$self->{level}->{_changed} = 0;
	$self->{level} = Minecraft::NBT->from_string( $buffer );
}


sub region
{
	my( $self, $r_x, $r_z ) = @_;

	if( !defined $self->{regions}->{$r_z}->{$r_x} )
	{
		my $file = $self->{dir}."/region/r.$r_x.$r_z.mca";
		if( -e $file )
		{
			print "LOADING REGION $r_x,$r_z .. ";
			$self->{regions}->{$r_z}->{$r_x} = Minecraft::Region->from_file( $file );
			$self->{regions}->{$r_z}->{$r_x}->{_changed} = 0;
			print "done\n";
		}
		else
		{
			$self->init_region( $r_x,$r_z );
		}
		$self->{regions}->{$r_z}->{$r_x}->{invert_z} = $r_z<0;
		$self->{regions}->{$r_z}->{$r_x}->{invert_x} = $r_x<0;
	}
	return $self->{regions}->{$r_z}->{$r_x};
}

sub init_region
{
	my( $self, $r_x, $r_z ) = @_;

	print "INIT REGION $r_x,$r_z .. ";
	$self->{regions}->{$r_z}->{$r_x} = new Minecraft::Region();	
	$self->{regions}->{$r_z}->{$r_x}->add_layer( 0, 7 ); # add bedrock
	$self->{regions}->{$r_z}->{$r_x}->{_changed} = 1;
	print "done\n";
}

1;
