package Minecraft::WikiPoints;

use JSON::PP;
use Data::Dumper;
use POSIX;

use strict;
use warnings;

sub get {
	my( $lat1,$long1, $lat2,$long2 ) = @_;

	if( $lat1 > $lat2 ) { my $a=$lat1; $lat1=$lat2; $lat2=$a; }
	if( $long1 > $long2 ) { my $a=$long1; $long1=$long2; $long2=$a; }
	#$lat1 = floor( $lat1*1000 )/1000;
	#$long1 = floor( $long1*1000 )/1000;
	#$lat2 = ceil( $lat2*1000 )/1000;
	#$long2 = ceil( $long2*1000 )/1000;
	
	my $sparql=<<END;
select distinct * where {
?thing geo:lat ?lat .
?thing geo:long ?long .
?thing rdfs:label ?label .
FILTER( LANG(?label) = 'en' )
FILTER( ?long > $long1 && ?long < $long2 )
FILTER( ?lat > $lat1 && ?lat < $lat2 )
}
END
print $sparql;
	my $url = "http://dbpedia.org/sparql?default-graph-uri=http%3A%2F%2Fdbpedia.org&query=".urlencode($sparql)."&format=application%2Fsparql-results%2Bjson&CXML_redir_for_subjs=121&CXML_redir_for_hrefs=&timeout=30000&debug=on&run=+Run+Query+";
	print "Getting URL: $url\n";
	my $json = `curl -L -s '$url' `;
	my $info = decode_json $json;

	my $points = [];

	foreach my $result ( @{ $info->{results}->{bindings} } )
	{
		push @{$points}, [
			$result->{lat}->{value},
			$result->{long}->{value},
			$result->{label}->{value},
		];
	}
	return $points;
}

sub urlencode {
	my $s = shift;
	$s =~ s/ /+/g;
	$s =~ s/([^A-Za-z0-9\+-])/sprintf("%%%02X", ord($1))/seg;
	return $s;
}

1;
