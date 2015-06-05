#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Minecraft;

use Data::Dumper;

my $mc = new Minecraft( "$FindBin::Bin/saves" );
my $world = $mc->world( "Test23" );

if(0){
for( my $x=-50;$x<50;++$x ) {
	for( my $z=-50;$z<50;++$z ) {
		for( my$y=90;$y<110;++$y ) {
			$world->set_block($x,$y,$z, ($x+$z) % 6 );
		}
	}
}
}


if(1){
for( my $x=-128;$x<=128;$x+=16 ) {
	for( my $z=-128;$z<=128;$z+=16 ) {
		for( my $i=0;$i<16;++$i) { 
			$world->set_block($x+$i,80,$z, 1 );
			$world->set_block($x,80,$z+$i, 1 );
		}
		$world->set_block($x+1,80,$z, 2 );
		$world->set_block($x+2,80,$z, 2 );
		$world->set_block($x,80,$z+1, 4 );
		$world->set_block($x,80,$z+2, 4 );
	}
}
}


for(my $i=0;$i<4;++$i )
{
	$world->set_block($i,   82,   $i*2, 5);
	$world->set_block(-1-$i,82,   $i*2, 5);
	$world->set_block($i,   82,-1-$i*2, 5);
	$world->set_block(-1-$i,82,-1-$i*2, 5);
}
for( my $i=-1;$i>-40;--$i ) { $world->set_block($i,83,0, 43); }
for( my $i=-1;$i>-40;--$i ) { $world->set_block($i,83,2, 43); }
for( my $i=-1;$i>-40;--$i ) { $world->set_block($i,83,4, 43); }

my $y = 81;

p($world,-15,$y++,-31);
p($world,-15,$y++,-15);
p($world,1,$y++,-15);
p($world,17,$y++,-15);
p($world,1,$y++,1);
p($world,1,$y++,17);
p($world,-15,$y++,1);
p($world,-31,$y++,1);


sub p
{
	my( $world,$x,$y,$z) =@_;

	$world->set_block($x+0,$y,$z+0,  2);  
	$world->set_block($x+0,$y,$z+1,  2);  
	$world->set_block($x+1,$y,$z+1,  2);  
	$world->set_block($x+2,$y,$z+1,  2);  
	$world->set_block($x+0,$y,$z+2,  2);  
	$world->set_block($x+2,$y,$z+2,  2);  
	$world->set_block($x+0,$y,$z+3,  2);  
	$world->set_block($x+1,$y,$z+3,  2);  
	$world->set_block($x+2,$y,$z+3,  2);  
}
	
if(0){
my $x = 0;
my $z = 0;
my $len=0;
my $y = 140;
while( $len < 100 )
{
	$len +=3;
	for( my $j=0;$j<$len;$j++ ) { $world->set_block($x+$j,$y,$z,  1); } 
	$x+=$len;

	$len +=3;
	for( my $j=0;$j<$len;$j++ ) { $world->set_block($x,$y,$z+$j,  1); } 
	$z+=$len;
		
	$len +=3;
	for( my $j=0;$j<$len;$j++ ) { $world->set_block($x-$j,$y,$z,  1); } 
	$x-=$len;
		
	$len +=3;
	for( my $j=0;$j<$len;$j++ ) { $world->set_block($x,$y,$z-$j,  1); } 
	$z-=$len;
}
}		


$world->save;
exit;

