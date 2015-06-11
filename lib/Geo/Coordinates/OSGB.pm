package Geo::Coordinates::OSGB;
use base qw(Exporter);
use strict;
use warnings;
use Carp;

our $VERSION = '2.06';
our %EXPORT_TAGS = (
    all => [ qw( ll_to_grid grid_to_ll
                 shift_ll_into_WGS84 shift_ll_from_WGS84
                 parse_ISO_ll format_ll_trad format_ll_ISO
                 parse_grid parse_trad_grid parse_GPS_grid parse_landranger_grid
                 format_grid_trad format_grid_GPS format_grid_landranger
           )]
    );
our @EXPORT_OK = ( @{ $EXPORT_TAGS{all} } );

use Math::Trig qw(tan sec);

use constant PI  => 4 * atan2 1, 1;
use constant RAD => PI / 180;
use constant DAR => 180 / PI;

use constant WGS84_MAJOR_AXIS => 6_378_137.000;
use constant WGS84_MINOR_AXIS => 6_356_752.314_25;
use constant WGS84_FLATTENING => 1 / 298.257223563;

use constant OSGB_MAJOR_AXIS  => 6_377_563.396;
use constant OSGB_MINOR_AXIS  => 6_356_256.910;

# set defaults for Britain
my %ellipsoid_shapes = (
    WGS84  => [ WGS84_MAJOR_AXIS, WGS84_MINOR_AXIS ],
    ETRS89 => [ WGS84_MAJOR_AXIS, WGS84_MINOR_AXIS ],
    ETRN89 => [ WGS84_MAJOR_AXIS, WGS84_MINOR_AXIS ],
    GRS80  => [ WGS84_MAJOR_AXIS, WGS84_MINOR_AXIS ],
    OSGB36 => [ OSGB_MAJOR_AXIS,  OSGB_MINOR_AXIS  ],
    OSGM02 => [ OSGB_MAJOR_AXIS,  OSGB_MINOR_AXIS  ],
); # yes lots of synonyms

# constants for OSGB mercator projection
use constant ORIGIN_LONGITUDE    => RAD * -2;
use constant ORIGIN_LATITUDE     => RAD * 49;
use constant ORIGIN_EASTING      => 400_000;
use constant ORIGIN_NORTHING     => -100_000;
use constant CONVERGENCE_FACTOR  => 0.9996012717;

# size of LR sheets
use constant LR_SHEET_SIZE => 40_000;

# Pattern to recognise ISO long/lat strings
my $ISO_LL_PATTERN  = qr{\A
                        ([-+])(    \d{2,6})(?:\.(\d+))?
                        ([-+])([01]\d{2,6})(?:\.(\d+))?
                        ([-+][\.\d]+)?
                        \/
                        \Z}smxo;

sub ll_to_grid {

    my ($lat, $lon, $alt, $shape, @junk) = @_;

    return if !defined wantarray;

    if ( $alt && defined $ellipsoid_shapes{$alt} ) {
        $shape = $alt;
        $alt = undef;
    }

    if ( ! ($shape && defined $ellipsoid_shapes{$shape}) ) {
        $shape = 'OSGB36';
    }

    if ($lat =~ $ISO_LL_PATTERN ) {
        ($lat, $lon, $alt) = parse_ISO_ll($lat);
    }

    my ($a,$b) = @{$ellipsoid_shapes{$shape}};

    my $e2 = ($a**2-$b**2)/$a**2;
    my $n = ($a-$b)/($a+$b);

    my $phi = RAD * $lat;
    my $lam = RAD * $lon;

    my $sp2  = sin($phi)**2;
    my $nu   = $a * CONVERGENCE_FACTOR * (1 - $e2 * $sp2 ) ** -0.5;
    my $rho  = $a * CONVERGENCE_FACTOR * (1 - $e2) * (1 - $e2 * $sp2 ) ** -1.5;
    my $eta2 = $nu/$rho - 1;

    my $M = _compute_big_m($phi, $b, $n);

    my $cp = cos $phi ; my $sp = sin $phi; my $tp = tan($phi);
    my $tp2 = $tp*$tp ; my $tp4 = $tp2*$tp2 ;

    my $I    = $M + ORIGIN_NORTHING;
    my $II   = $nu/2  * $sp * $cp;
    my $III  = $nu/24 * $sp * $cp**3 * (5-$tp2+9*$eta2);
    my $IIIA = $nu/720* $sp * $cp**5 *(61-58*$tp2+$tp4);

    my $IV   = $nu*$cp;
    my $V    = $nu/6   * $cp**3 * ($nu/$rho-$tp2);
    my $VI   = $nu/120 * $cp**5 * (5-18*$tp2+$tp4+14*$eta2-58*$tp2*$eta2);

    my $l = $lam - ORIGIN_LONGITUDE;
    my $north = $I  + $II*$l**2 + $III*$l**4 + $IIIA*$l**6;
    my $east  = ORIGIN_EASTING + $IV*$l    +   $V*$l**3 +   $VI*$l**5;

    # round to 3dp (mm)
    ($east, $north) = map { sprintf '%.3f', $_ } ($east, $north);

    return ($east,$north) if wantarray;
    return format_grid_trad($east, $north);
}

sub grid_to_ll {

    my ($E, $N, $shape, @junk) = @_;

    return if !defined wantarray;

    if ( ! ($shape && defined $ellipsoid_shapes{$shape}) ) {
        $shape = 'OSGB36';
    }

    if ( ! defined $N ) {
        ($E, $N) = parse_grid($E);
    }

    my ($a,$b) = @{$ellipsoid_shapes{$shape}};

    my $e2 = ($a**2-$b**2)/$a**2;
    my $n = ($a-$b)/($a+$b);

    my $dn = $N - ORIGIN_NORTHING;

    my ($phi, $lam);
    $phi = ORIGIN_LATITUDE + $dn/($a * CONVERGENCE_FACTOR);

    my $M = _compute_big_m($phi, $b, $n);
    while ($dn-$M >= 0.001) {
       $phi = $phi + ($dn-$M)/($a * CONVERGENCE_FACTOR);
       $M = _compute_big_m($phi, $b, $n);
    }

    my $sp2  = sin($phi)**2;
    my $nu   = $a * CONVERGENCE_FACTOR *             (1 - $e2 * $sp2 ) ** -0.5;
    my $rho  = $a * CONVERGENCE_FACTOR * (1 - $e2) * (1 - $e2 * $sp2 ) ** -1.5;
    my $eta2 = $nu/$rho - 1;

    my $tp = tan($phi); my $tp2 = $tp*$tp ; my $tp4 = $tp2*$tp2 ;

    my $VII  = $tp /   (2*$rho*$nu);
    my $VIII = $tp /  (24*$rho*$nu**3) *  (5 +  3*$tp2 + $eta2 - 9*$tp2*$eta2);
    my $IX   = $tp / (720*$rho*$nu**5) * (61 + 90*$tp2 + 45*$tp4);

    my $sp = sec($phi); my $tp6 = $tp4*$tp2 ;

    my $X    = $sp/$nu;
    my $XI   = $sp/(   6*$nu**3)*($nu/$rho + 2*$tp2);
    my $XII  = $sp/( 120*$nu**5)*(      5 + 28*$tp2 +   24*$tp4);
    my $XIIA = $sp/(5040*$nu**7)*(    61 + 662*$tp2 + 1320*$tp4 + 720*$tp6);

    my $e = $E - ORIGIN_EASTING;

    $phi = $phi - $VII*$e**2 + $VIII*$e**4 - $IX*$e**6;
    $lam = ORIGIN_LONGITUDE + $X*$e - $XI*$e**3 + $XII*$e**5 - $XIIA*$e**7;

    # now put into degrees & return
    my $lat = $phi * DAR;
    my $lon = $lam * DAR;

    return ($lat, $lon) if wantarray;
    return format_ll_ISO($lat,$lon);
}

sub _compute_big_m {
    my ($phi, $b, $n) = @_;
    my $p_plus  = $phi + ORIGIN_LATITUDE;
    my $p_minus = $phi - ORIGIN_LATITUDE;
    return $b * CONVERGENCE_FACTOR * (
           (1 + $n * (1 + 5/4*$n*(1 + $n)))*$p_minus
         - 3*$n*(1+$n*(1+7/8*$n))  * sin(  $p_minus) * cos(  $p_plus)
         + (15/8*$n * ($n*(1+$n))) * sin(2*$p_minus) * cos(2*$p_plus)
         - 35/24*$n**3             * sin(3*$p_minus) * cos(3*$p_plus)
           );
}



my %BIG_OFF = (
              G => { E => -1, N => 2 },
              H => { E =>  0, N => 2 },
              J => { E =>  1, N => 2 },
              M => { E => -1, N => 1 },
              N => { E =>  0, N => 1 },
              O => { E =>  1, N => 1 },
              R => { E => -1, N => 0 },
              S => { E =>  0, N => 0 },
              T => { E =>  1, N => 0 },
           );

my %SMALL_OFF = (
                 A => { E =>  0, N => 4 },
                 B => { E =>  1, N => 4 },
                 C => { E =>  2, N => 4 },
                 D => { E =>  3, N => 4 },
                 E => { E =>  4, N => 4 },

                 F => { E =>  0, N => 3 },
                 G => { E =>  1, N => 3 },
                 H => { E =>  2, N => 3 },
                 J => { E =>  3, N => 3 },
                 K => { E =>  4, N => 3 },

                 L => { E =>  0, N => 2 },
                 M => { E =>  1, N => 2 },
                 N => { E =>  2, N => 2 },
                 O => { E =>  3, N => 2 },
                 P => { E =>  4, N => 2 },

                 Q => { E =>  0, N => 1 },
                 R => { E =>  1, N => 1 },
                 S => { E =>  2, N => 1 },
                 T => { E =>  3, N => 1 },
                 U => { E =>  4, N => 1 },

                 V => { E =>  0, N => 0 },
                 W => { E =>  1, N => 0 },
                 X => { E =>  2, N => 0 },
                 Y => { E =>  3, N => 0 },
                 Z => { E =>  4, N => 0 },
           );

use constant BIG_SQUARE => 500_000;
use constant SQUARE     => 100_000;

# Landranger sheet data
# These are the full GRs (as metres from Newlyn) of the SW corner of each sheet.
my %LR = (
      1 => [ 429_000, 1_179_000 ] ,
      2 => [ 433_000, 1_156_000 ] ,
      3 => [ 414_000, 1_147_000 ] ,
      4 => [ 420_000, 1_107_000 ] ,
      5 => [ 340_000, 1_020_000 ] ,
      6 => [ 321_000,   996_000 ] ,
      7 => [ 315_000,   970_000 ] ,
      8 => [ 117_000,   926_000 ] ,
      9 => [ 212_000,   940_000 ] ,
     10 => [ 252_000,   940_000 ] ,
     11 => [ 292_000,   929_000 ] ,
     12 => [ 300_000,   939_000 ] ,
     13 => [  95_000,   903_000 ] ,
     14 => [ 105_000,   886_000 ] ,
     15 => [ 196_000,   900_000 ] ,
     16 => [ 236_000,   900_000 ] ,
     17 => [ 276_000,   900_000 ] ,
     18 => [  69_000,   863_000 ] ,
     19 => [ 174_000,   860_000 ] ,
     20 => [ 214_000,   860_000 ] ,
     21 => [ 254_000,   860_000 ] ,
     22 => [  57_000,   823_000 ] ,
     23 => [ 113_000,   836_000 ] ,
     24 => [ 150_000,   830_000 ] ,
     25 => [ 190_000,   820_000 ] ,
     26 => [ 230_000,   820_000 ] ,
     27 => [ 270_000,   830_000 ] ,
     28 => [ 310_000,   833_000 ] ,
     29 => [ 345_000,   830_000 ] ,
     30 => [ 377_000,   830_000 ] ,
     31 => [  50_000,   783_000 ] ,
     32 => [ 130_000,   800_000 ] ,
     33 => [ 170_000,   790_000 ] ,
     34 => [ 210_000,   780_000 ] ,
     35 => [ 250_000,   790_000 ] ,
     36 => [ 285_000,   793_000 ] ,
     37 => [ 325_000,   793_000 ] ,
     38 => [ 365_000,   790_000 ] ,
     39 => [ 120_000,   770_000 ] ,
     40 => [ 160_000,   760_000 ] ,
     41 => [ 200_000,   750_000 ] ,
     42 => [ 240_000,   750_000 ] ,
     43 => [ 280_000,   760_000 ] ,
     44 => [ 320_000,   760_000 ] ,
     45 => [ 360_000,   760_000 ] ,
     46 => [  92_000,   733_000 ] ,
     47 => [ 120_000,   733_000 ] ,
     48 => [ 120_000,   710_000 ] ,
     49 => [ 160_000,   720_000 ] ,
     50 => [ 200_000,   710_000 ] ,
     51 => [ 240_000,   720_000 ] ,
     52 => [ 270_000,   720_000 ] ,
     53 => [ 294_000,   720_000 ] ,
     54 => [ 334_000,   720_000 ] ,
     55 => [ 164_000,   680_000 ] ,
     56 => [ 204_000,   682_000 ] ,
     57 => [ 244_000,   682_000 ] ,
     58 => [ 284_000,   690_000 ] ,
     59 => [ 324_000,   690_000 ] ,
     60 => [ 110_000,   640_000 ] ,
     61 => [ 131_000,   662_000 ] ,
     62 => [ 160_000,   640_000 ] ,
     63 => [ 200_000,   642_000 ] ,
     64 => [ 240_000,   645_000 ] ,
     65 => [ 280_000,   650_000 ] ,
     66 => [ 316_000,   650_000 ] ,
     67 => [ 356_000,   650_000 ] ,
     68 => [ 157_000,   600_000 ] ,
     69 => [ 175_000,   613_000 ] ,
     70 => [ 215_000,   605_000 ] ,
     71 => [ 255_000,   605_000 ] ,
     72 => [ 280_000,   620_000 ] ,
     73 => [ 320_000,   620_000 ] ,
     74 => [ 357_000,   620_000 ] ,
     75 => [ 390_000,   620_000 ] ,
     76 => [ 195_000,   570_000 ] ,
     77 => [ 235_000,   570_000 ] ,
     78 => [ 275_000,   580_000 ] ,
     79 => [ 315_000,   580_000 ] ,
     80 => [ 355_000,   580_000 ] ,
     81 => [ 395_000,   580_000 ] ,
     82 => [ 195_000,   530_000 ] ,
     83 => [ 235_000,   530_000 ] ,
     84 => [ 265_000,   540_000 ] ,
     85 => [ 305_000,   540_000 ] ,
     86 => [ 345_000,   540_000 ] ,
     87 => [ 367_000,   540_000 ] ,
     88 => [ 407_000,   540_000 ] ,
     89 => [ 290_000,   500_000 ] ,
     90 => [ 317_000,   500_000 ] ,
     91 => [ 357_000,   500_000 ] ,
     92 => [ 380_000,   500_000 ] ,
     93 => [ 420_000,   500_000 ] ,
     94 => [ 460_000,   485_000 ] ,
     95 => [ 213_000,   465_000 ] ,
     96 => [ 303_000,   460_000 ] ,
     97 => [ 326_000,   460_000 ] ,
     98 => [ 366_000,   460_000 ] ,
     99 => [ 406_000,   460_000 ] ,
    100 => [ 446_000,   460_000 ] ,
    101 => [ 486_000,   460_000 ] ,
    102 => [ 326_000,   420_000 ] ,
    103 => [ 360_000,   420_000 ] ,
    104 => [ 400_000,   420_000 ] ,
    105 => [ 440_000,   420_000 ] ,
    106 => [ 463_000,   420_000 ] ,
    107 => [ 500_000,   420_000 ] ,
    108 => [ 320_000,   380_000 ] ,
    109 => [ 360_000,   380_000 ] ,
    110 => [ 400_000,   380_000 ] ,
    111 => [ 430_000,   380_000 ] ,
    112 => [ 470_000,   385_000 ] ,
    113 => [ 510_000,   386_000 ] ,
    114 => [ 220_000,   360_000 ] ,
    115 => [ 240_000,   345_000 ] ,
    116 => [ 280_000,   345_000 ] ,
    117 => [ 320_000,   340_000 ] ,
    118 => [ 360_000,   340_000 ] ,
    119 => [ 400_000,   340_000 ] ,
    120 => [ 440_000,   350_000 ] ,
    121 => [ 478_000,   350_000 ] ,
    122 => [ 518_000,   350_000 ] ,
    123 => [ 210_000,   320_000 ] ,
    124 => [ 250_000,   305_000 ] ,
    125 => [ 280_000,   305_000 ] ,
    126 => [ 320_000,   300_000 ] ,
    127 => [ 360_000,   300_000 ] ,
    128 => [ 400_000,   308_000 ] ,
    129 => [ 440_000,   310_000 ] ,
    130 => [ 480_000,   310_000 ] ,
    131 => [ 520_000,   310_000 ] ,
    132 => [ 560_000,   310_000 ] ,
    133 => [ 600_000,   310_000 ] ,
    134 => [ 617_000,   290_000 ] ,
    135 => [ 250_000,   265_000 ] ,
    136 => [ 280_000,   265_000 ] ,
    137 => [ 320_000,   260_000 ] ,
    138 => [ 345_000,   260_000 ] ,
    139 => [ 385_000,   268_000 ] ,
    140 => [ 425_000,   270_000 ] ,
    141 => [ 465_000,   270_000 ] ,
    142 => [ 504_000,   274_000 ] ,
    143 => [ 537_000,   274_000 ] ,
    144 => [ 577_000,   270_000 ] ,
    145 => [ 200_000,   220_000 ] ,
    146 => [ 240_000,   225_000 ] ,
    147 => [ 270_000,   240_000 ] ,
    148 => [ 310_000,   240_000 ] ,
    149 => [ 333_000,   228_000 ] ,
    150 => [ 373_000,   228_000 ] ,
    151 => [ 413_000,   230_000 ] ,
    152 => [ 453_000,   230_000 ] ,
    153 => [ 493_000,   234_000 ] ,
    154 => [ 533_000,   234_000 ] ,
    155 => [ 573_000,   234_000 ] ,
    156 => [ 613_000,   250_000 ] ,
    157 => [ 165_000,   201_000 ] ,
    158 => [ 189_000,   190_000 ] ,
    159 => [ 229_000,   185_000 ] ,
    160 => [ 269_000,   205_000 ] ,
    161 => [ 309_000,   205_000 ] ,
    162 => [ 349_000,   188_000 ] ,
    163 => [ 389_000,   190_000 ] ,
    164 => [ 429_000,   190_000 ] ,
    165 => [ 460_000,   195_000 ] ,
    166 => [ 500_000,   194_000 ] ,
    167 => [ 540_000,   194_000 ] ,
    168 => [ 580_000,   194_000 ] ,
    169 => [ 607_000,   210_000 ] ,
    170 => [ 269_000,   165_000 ] ,
    171 => [ 309_000,   165_000 ] ,
    172 => [ 340_000,   155_000 ] ,
    173 => [ 380_000,   155_000 ] ,
    174 => [ 420_000,   155_000 ] ,
    175 => [ 460_000,   155_000 ] ,
    176 => [ 495_000,   160_000 ] ,
    177 => [ 530_000,   160_000 ] ,
    178 => [ 565_000,   155_000 ] ,
    179 => [ 603_000,   133_000 ] ,
    180 => [ 240_000,   112_000 ] ,
    181 => [ 280_000,   112_000 ] ,
    182 => [ 320_000,   130_000 ] ,
    183 => [ 349_000,   115_000 ] ,
    184 => [ 389_000,   115_000 ] ,
    185 => [ 429_000,   116_000 ] ,
    186 => [ 465_000,   125_000 ] ,
    187 => [ 505_000,   125_000 ] ,
    188 => [ 545_000,   125_000 ] ,
    189 => [ 585_000,   115_000 ] ,
    190 => [ 207_000,    87_000 ] ,
    191 => [ 247_000,    72_000 ] ,
    192 => [ 287_000,    72_000 ] ,
    193 => [ 310_000,    90_000 ] ,
    194 => [ 349_000,    75_000 ] ,
    195 => [ 389_000,    75_000 ] ,
    196 => [ 429_000,    76_000 ] ,
    197 => [ 469_000,    90_000 ] ,
    198 => [ 509_000,    97_000 ] ,
    199 => [ 549_000,    94_000 ] ,
    200 => [ 175_000,    50_000 ] ,
    201 => [ 215_000,    47_000 ] ,
    202 => [ 255_000,    32_000 ] ,
    203 => [ 132_000,    11_000 ] ,
    204 => [ 172_000,    14_000 ] ,
);

sub format_grid_trad {
    my $e = shift;
    my $n = shift;
    my $sq;

    ($sq, $e, $n) = format_grid_GPS($e, $n);

    use integer;
    ($e,$n) = ($e/100,$n/100);
    return ($sq, $e, $n) if wantarray;
    return sprintf '%s %03d %03d', $sq, $e, $n;
}

sub format_grid_GPS {
    my $e = shift;
    my $n = shift;

    croak 'Easting must not be negative' if $e<0;
    croak 'Northing must not be negative' if $n<0;

    # round to nearest metre
    ($e,$n) = map { $_+0.5 } ($e, $n);
    my $sq;

    my $great_square_index_east  = 2 + int $e/BIG_SQUARE;
    my $great_square_index_north = 1 + int $n/BIG_SQUARE;
    my $small_square_index_east  = int ($e%BIG_SQUARE)/SQUARE;
    my $small_square_index_north = int ($n%BIG_SQUARE)/SQUARE;

    my @grid = ( [ qw( V W X Y Z ) ],
                 [ qw( Q R S T U ) ],
                 [ qw( L M N O P ) ],
                 [ qw( F G H J K ) ],
                 [ qw( A B C D E ) ],
               );

    $sq = $grid[$great_square_index_north][$great_square_index_east]
        . $grid[$small_square_index_north][$small_square_index_east];

    ($e,$n) = map { $_ % SQUARE } ($e, $n);

    return ($sq, $e, $n) if wantarray;
    return sprintf '%s %05d %05d', $sq, $e, $n;
}

sub format_grid_landranger {
    my ($e,$n) = @_;
    my @sheets = ();
    for my $sheet (1..204) {
        my $e_difference = $e - $LR{$sheet}->[0];
        my $n_difference = $n - $LR{$sheet}->[1];
        if ( 0 <= $e_difference && $e_difference < LR_SHEET_SIZE
          && 0 <= $n_difference && $n_difference < LR_SHEET_SIZE ) {
            push @sheets, $sheet
        }
    }
    my $sq;
    ($sq, $e, $n) = format_grid_trad($e,$n);

    return ($sq, $e, $n, @sheets) if wantarray;

    if (!@sheets )    { return sprintf '%s %03d %03d is not on any OS Sheet', $sq, $e, $n }
    if ( @sheets==1 ) { return sprintf '%s %03d %03d on OS Sheet %d'        , $sq, $e, $n, $sheets[0] }
    if ( @sheets==2 ) { return sprintf '%s %03d %03d on OS Sheets %d and %d', $sq, $e, $n, @sheets }

    my $phrase = join ', ', @sheets[0..($#sheets-1)], "and $sheets[-1]";
    return sprintf '%s %03d %03d on OS Sheets %s', $sq, $e, $n, $phrase;

}

my $SHORT_GRID_REF = qr{ \A ([GHJMNORST][A-Z]) \s? (\d{1,3}) \D? (\d{1,3}) \Z }smiox;
my $LONG_GRID_REF  = qr{ \A ([GHJMNORST][A-Z]) \s? (\d{4,5}) \D? (\d{4,5}) \Z }smiox;

sub parse_grid {
    my $s = "@_";
    if ( $s =~ $SHORT_GRID_REF ) {
        return _parse_grid($1, $2*100, $3*100)
    }
    if ( $s =~ $LONG_GRID_REF ) {
        return _parse_grid($1, $2, $3)
    }
    if ( $s =~ m{\A (\d{1,3}) \D+ (\d{3}) \D? (\d{3}) \Z}xsm ) { # sheet/eee/nnn etc
        return parse_landranger_grid($1, $2, $3)
    }
    if ( $s =~ m{\A \d{1,3} \Z}xsm && $s < 205 ) {  # just a landranger sheet
        return parse_landranger_grid($s)
    }
    croak "$s <-- this does not match my grid ref patterns";
}

sub parse_trad_grid {
    my $gr = "@_";
    if ( $gr =~ $SHORT_GRID_REF  ) { return _parse_grid($1, $2*100, $3*100) }

    croak "Cannot parse @_ as a traditional grid reference";
}

sub parse_GPS_grid {
    my $gr = "@_";
    if ( $gr =~ $LONG_GRID_REF  ) { return _parse_grid($1, $2, $3) }

    croak "Cannot parse @_ as a GPS grid reference";
}

sub _parse_grid {
    my ($letters, $e, $n) = @_;

    return if !defined wantarray;

    $letters = uc $letters;

    my $c = substr $letters,0,1;
    $e += $BIG_OFF{$c}->{E}*BIG_SQUARE;
    $n += $BIG_OFF{$c}->{N}*BIG_SQUARE;

    my $d = substr $letters,1,1;
    $e += $SMALL_OFF{$d}->{E}*SQUARE;
    $n += $SMALL_OFF{$d}->{N}*SQUARE;

    return ($e,$n);
}


sub parse_landranger_grid {
    my ($sheet, $e, $n) = @_;

    return if !defined wantarray;

    if ( !defined $sheet )      { croak 'Missing OS Sheet number'  }
    if ( !defined $LR{$sheet} ) { croak "Unknown OS Sheet number ($sheet)" }
    if ( !defined $e )          { return wantarray ? @{$LR{$sheet}} : format_grid_trad(@{$LR{$sheet}}) }
    if ( !defined $n )          { $n = -1 }

    use integer;

    SWITCH: {
        if ( $e =~ m{\A (\d{3}) (\d{3}) \Z}x && $n == -1 ) { ($e, $n) = ($1*100, $2*100) ; last SWITCH }
        if ( $e =~ m{\A\d{3}\Z}x && $n =~ m{\A\d{3}\Z}x )  { ($e, $n) = ($e*100, $n*100) ; last SWITCH }
        if ( $e =~ m{\A\d{5}\Z}x && $n =~ m{\A\d{5}\Z}x )  { ($e, $n) = ($e*1,   $n*1  ) ; last SWITCH }
        croak "I was expecting a grid reference, not this: @_";
    }

    my $full_easting  = _lr_to_full_grid($LR{$sheet}->[0], $e);
    my $full_northing = _lr_to_full_grid($LR{$sheet}->[1], $n);

    return ($full_easting, $full_northing)
}

sub _lr_to_full_grid {
    my ($lower_left_offset, $in_square_offset) = @_;

    my $lower_left_in_square = $lower_left_offset % 100_000;

    my $distance_from_lower_left = $in_square_offset - $lower_left_in_square;
    if ( $distance_from_lower_left < 0 ) {
        $distance_from_lower_left += 100_000;
    }

    if ( $distance_from_lower_left < 0 || $distance_from_lower_left >= LR_SHEET_SIZE ) {
        croak 'Grid reference not on sheet';
    }

    return $lower_left_offset + $distance_from_lower_left;
}

sub parse_ISO_ll {
    my $iso_string = shift;
    return if !defined wantarray;

    my ($lat_sign, $lat_ip, $lat_fp,
        $lon_sign, $lon_ip, $lon_fp, $alt ) = $iso_string =~ $ISO_LL_PATTERN;

    if (! defined $lat_ip ) { croak "I can't parse an ISO 6709 lat/lon string from your input ($iso_string)" }

    # now check the integer parts are sensible lengths
    my $l_lat = length $lat_ip;
    my $l_lon = length $lon_ip;
    if ( $l_lat%2==1)       { croak "Bad latitude in ISO 6709 string: $iso_string" }   # must be even
    if ( $l_lon%2==0)       { croak "Bad longitude in ISO 6709 string: $iso_string" }  # must be odd
    if ( $l_lon-$l_lat!=1 ) { croak "Latitude and longitude values don't match: $iso_string" } # must differ by 1

    my ($lat, $lon) = (0,0);
    $lat_fp = (defined $lat_fp) ? ".$lat_fp" : q{};
    $lon_fp = (defined $lon_fp) ? ".$lon_fp" : q{};
    if ( $l_lat == 2 ) {
        $lat = $lat_ip.$lat_fp;
        $lon = $lon_ip.$lon_fp;
    }
    elsif ( $l_lat == 4 ) {
        $lat = substr($lat_ip,0,2) + ( substr($lat_ip,2,2) . $lat_fp ) / 60;
        $lon = substr($lon_ip,0,3) + ( substr($lon_ip,3,2) . $lon_fp ) / 60;
    }
    else {
        $lat = substr($lat_ip,0,2) + substr($lat_ip,2,2)/60 + ( substr($lat_ip,4,2) . $lat_fp )/3600;
        $lon = substr($lon_ip,0,3) + substr($lon_ip,3,2)/60 + ( substr($lon_ip,5,2) . $lon_fp )/3600;
    }

    croak 'Latitude cannot exceed 90 degrees'   if $lat > 90;
    croak 'Longitude cannot exceed 180 degrees' if $lon > 180;

    $lat = $lat_sign . $lat;
    $lon = $lon_sign . $lon;

    return ($lat, $lon, $alt) if wantarray;
    return format_ll_ISO($lat,$lon);
}

#     Latitude and Longitude in Degrees:
#         sDD.DDDDsDDD.DDDD/         (eg +12.345-098.765/)
#      Latitude and Longitude in Degrees and Minutes:
#         sDDMM.MMMMsDDDMM.MMMM/     (eg +1234.56-09854.321/)
#      Latitude and Longitude in Degrees, Minutes and Seconds:
#         sDDMMSS.SSSSsDDDMMSS.SSSS/ (eg +123456.7-0985432.1/)
#
#   where:
#
#        sDD   = three-digit integer degrees part of latitude (through -90 ~ -00 ~ +90)
#        sDDD  = four-digit integer degrees part of longitude (through -180 ~ -000 ~ +180)
#        MM    = two-digit integer minutes part (00 through 59)
#        SS    = two-digit integer seconds part (00 through 59)
#        .DDDD = variable-length fraction part in degrees
#        .MMMM = variable-length fraction part in minutes
#        .SSSS = variable-length fraction part in seconds
#
#        * Latitude is written in the first, and longitude is second.
#        * The sign is always necessary for each value.
#          Latitude : North="+" South="-"
#          Longitude: East ="+" West ="-"
#        * The integer part is a fixed length respectively.
#          And padding character is "0".
#          (Note: Therefor, it is shown explicitly that the first is latitude and the second is
#                 longitude, from the number of figures of the integer part.)
#        * It is variable-length below the decimal point.
#        * "/"is a terminator.
#
#   Altitude can be added optionally.
#      Latitude, Longitude (in Degrees) and Altitude:
#         sDD.DDDDsDDD.DDDDsAAA.AAA/         (eg +12.345-098.765+15.9/)
#      Latitude, Longitude (in Degrees and Minutes) and Altitude:
#         sDDMM.MMMMsDDDMM.MMMMsAAA.AAA/     (eg +1234.56-09854.321+15.9/)
#      Latitude, Longitude (in Degrees, Minutes and Seconds) and Altitude:
#         sDDMMSS.SSSSsDDDMMSS.SSSSsAAA.AAA/ (eg +123456.7-0985432.1+15.9/)
#
#   where:
#
#        sAAA.AAA = variable-length altitude in meters [m].
#
#        * The unit of altitude is meter [m].
#        * The integer part and the fraction part of altitude are both variable-length.
#


sub format_ll_trad {
    my ($lat, $lon) = @_;
    my ($lad, $lam, $las, $is_north) = _dms($lat); my $lah = $is_north ? 'N' : 'S';
    my ($lod, $lom, $los, $is_east ) = _dms($lon); my $loh = $is_east  ? 'E' : 'W';

    if (! defined wantarray ) { return }
    if ( wantarray )          { return ($lah, $lad, $lam, $las, $loh, $lod, $lom, $los) }
    return sprintf '%s%d:%02d:%02d %s%d:%02d:%02d', $lah, $lad, $lam, $las, $loh, $lod, $lom, $los;
}

sub _dms {
    my $dd = shift;
    my $is_positive = ($dd>=0);
    $dd = abs $dd;
    my $d = int $dd;     $dd = $dd-$d;
    my $m = int $dd*60;  $dd = $dd-$m/60;
    my $s = $dd*3600;
    return $d, $m, $s, $is_positive;
}

sub format_ll_ISO {
    my ($lat, $lon, $option) = @_;
    return if !defined wantarray;

    my ($lasign, $lad, $lam, $las) = _get_sdms($lat);
    my ($losign, $lod, $lom, $los) = _get_sdms($lon);

    # return d m and s if specifically requested with "SECONDS" option
    if (defined $option && (uc($option) eq 'SECONDS')) {
        if (wantarray) {                        return ($lasign, $lad, $lam, $las, $losign, $lod, $lom, $los) }
        return sprintf '%s%02d%02d%02d%s%03d%02d%02d/', $lasign, $lad, $lam, $las, $losign, $lod, $lom, $los;
    }

    # otherwise round up to nearest minute
    ($lad, $lam) = _round_up($lad, $lam, $las);
    ($lod, $lom) = _round_up($lod, $lom, $los);

    if (wantarray) {                return ($lasign ,$lad, $lam, $losign, $lod, $lom) }
    return sprintf '%s%02d%02d%s%03d%02d/', $lasign, $lad, $lam, $losign, $lod, $lom;
}

sub _round_up {
    my ($d, $m, $s) = @_;
    return ($d, $m) if $s<30;

    $m++;
    if ($m==60) {
        $m = 0;
        $d = $d+1;
    }
    return ($d, $m);
}

sub _get_sdms {
    my $r = shift;
    return if !defined wantarray;

    my $sign = $r>=0 ? q{+} : q{-};
    $r = abs $r;
    my $deg = int $r;
    my $exact_minutes = 60*($r-$deg);
    my $whole_minutes = int $exact_minutes;
    my $exact_seconds = 60 * ($exact_minutes-$whole_minutes);
    my $whole_seconds = int 0.5+$exact_seconds;
    if ( $whole_seconds > 59) {
        $whole_minutes++;
        $whole_seconds=0;
        if ($whole_minutes > 59 ) {
            $deg++;
            $whole_minutes = 0;
        }
    }
    return ($sign, $deg, $whole_minutes, $whole_seconds);
}

my %parameters_for_datum = (

    'OSGB36' => [ 573.604, 0.119600236/10000, 375, -111, 431 ],
    'OSGM02' => [ 573.604, 0.119600236/10000, 375, -111, 431 ],

    );

sub shift_ll_from_WGS84 {

    my ($lat, $lon, $elevation) = @_;
    if ( ! defined $elevation ) { $elevation = 0 }

    my $parameter_ref = $parameters_for_datum{'OSGM02'};
    my $target_da = -1 * $parameter_ref->[0];
    my $target_df = -1 * $parameter_ref->[1];
    my $target_dx = -1 * $parameter_ref->[2];
    my $target_dy = -1 * $parameter_ref->[3];
    my $target_dz = -1 * $parameter_ref->[4];

    my $reference_major_axis = WGS84_MAJOR_AXIS;
    my $reference_flattening = WGS84_FLATTENING;

    return _transform($lat, $lon, $elevation,
                      $reference_major_axis, $reference_flattening,
                      $target_da, $target_df,
                      $target_dx, $target_dy, $target_dz);
}

sub shift_ll_into_WGS84 {
    my ($lat, $lon, $elevation) = @_;
    if ( ! defined $elevation ) { $elevation = 0 }

    my $parameter_ref = $parameters_for_datum{'OSGM02'};
    my $target_da = $parameter_ref->[0];
    my $target_df = $parameter_ref->[1];
    my $target_dx = $parameter_ref->[2];
    my $target_dy = $parameter_ref->[3];
    my $target_dz = $parameter_ref->[4];

    my $reference_major_axis = WGS84_MAJOR_AXIS - $target_da;
    my $reference_flattening = WGS84_FLATTENING - $target_df;

    return _transform($lat, $lon, $elevation,
                      $reference_major_axis, $reference_flattening,
                      $target_da, $target_df,
                      $target_dx, $target_dy, $target_dz);
}

sub _transform {
    return if !defined wantarray;

    my $lat = shift;
    my $lon = shift;
    my $elev = shift || 0; # in case $elevation was passed as undef

    my $from_a = shift;
    my $from_f = shift;

    my $da = shift;
    my $df = shift;
    my $dx = shift;
    my $dy = shift;
    my $dz = shift;

    my $sin_lat = sin( $lat * RAD );
    my $cos_lat = cos( $lat * RAD );
    my $sin_lon = sin( $lon * RAD );
    my $cos_lon = cos( $lon * RAD );

    my $b_a      = 1 - $from_f;
    my $e_sq     = $from_f*(2-$from_f);
    my $ecc      = 1 - $e_sq*$sin_lat*$sin_lat;
    my $secc     = sqrt $ecc;

    my $rn       = $from_a / $secc;
    my $rm       = $from_a * (1-$e_sq) / ($ecc*$secc);

    my $d_lat = ( - $dx*$sin_lat*$cos_lon
                  - $dy*$sin_lat*$sin_lon
                  + $dz*$cos_lat
                  + $da*($rn*$e_sq*$sin_lat*$cos_lat)/$from_a
                  + $df*($rm/$b_a + $rn*$b_a)*$sin_lat*$cos_lat
                ) / ($rm + $elev);


    my $d_lon = ( - $dx*$sin_lon
                  + $dy*$cos_lon
                ) / (($rn+$elev)*$cos_lat);

    my $d_elev = + $dx*$cos_lat*$cos_lon
                 + $dy*$cos_lat*$sin_lon
                 + $dz*$sin_lat
                 - $da*$from_a/$rn
                 + $df*$b_a*$rn*$sin_lat*$sin_lat;

    my ($new_lat, $new_lon, $new_elev) = (
         $lat + $d_lat * DAR,
         $lon + $d_lon * DAR,
         $elev + $d_elev,
       );

    return ($new_lat, $new_lon, $new_elev) if wantarray;
    return sprintf '%s, (%s m)', format_ll_ISO($new_lat, $new_lon), $new_elev;

}

1;

__END__

=head1 NAME

Geo::Coordinates::OSGB - Convert coordinates between Lat/Lon and the British National Grid

An implementation of co-ordinate conversion for England, Wales, and Scotland
based on formulae published by the Ordnance Survey of Great Britain.

These modules will convert accurately between an OSGB national grid reference
and lat/lon coordinates based on the OSGB geoid model.  (For an explanation of
what a geoid model is and why you should care, read the Theory section
below.) The OSGB geoid model fits mainland Britain very well, but is rather
different from the international WGS84 model that has rapidly become the de
facto universal standard model thanks to the popularity of GPS devices and maps
on the Internet.  So, if you are trying to translate from an OSGB grid
reference to lat/lon coordinates that can be used in Google Earth, Wikipedia,
or some other Internet based tool, you will need to do two transformations:
first translate your grid ref into OSGB lat/lon; then nudge the result into
WGS84.  Routines are provided to do both of these operations, but they are only
approximate.  The inaccuracy of the approximation varies according to where you
are in the country but may be as much as several metres in some areas.

To get more accurate results you need to combine this module with its companion
L<Geo::Coordinates::OSTN02> which implements the transformation that now
defines the relationship between GPS survey data based on WGS84 and the British
National Grid.  Using this module you should be able to get results that are
accurate to within a few centimetres, but it is slightly slower and requires
more memory to run.

Note that the OSGB (and therefore this module) does not cover the whole of the
British Isles, nor even the whole of the UK, in particular it covers neither
the Channel Islands nor Northern Ireland.  The coverage that is included is
essentially the same as the coverage provided by the OSGB "Landranger" 1:50000
series maps.

=head1 VERSION

Examine $Geo::Coordinates::OSGB::VERSION for details.

=head1 SYNOPSIS

  use Geo::Coordinates::OSGB qw(ll_to_grid grid_to_ll);

  # Basic conversion routines
  ($easting,$northing) = ll_to_grid($lat,$lon);
  ($lat,$lon) = grid_to_ll($easting,$northing);

=head1 DESCRIPTION

These modules provide a collection of routines to convert between coordinates
expressed as latitude & longtitude and map grid references, using the formulae
given in the British Ordnance Survey's excellent information leaflet,
referenced below in the Theory section.  There are some key concepts explained in that
section that you need to know in order to use these modules successfully, so
you are recommended to at least skim through it now.

The module is implemented purely in Perl, and should run on any Perl platform.

In this description `OS' means `the Ordnance Survey of Great Britain': the
British government agency that produces the standard maps of England, Wales,
and Scotland.  Any mention of `sheets' or `maps' refers to one or more of the
204 sheets in the 1:50,000 scale `Landranger' series of OS maps.

This code is fine tuned to the British national grid system.  You could use it
elsewhere but you would need to adapt it.  Some starting points for doing this
are explained in the L<Theory> section below.


=head1 SUBROUTINES/METHODS

The following functions can be exported from the C<Geo::Coordinates::OSGB>
module:

    grid_to_ll                  ll_to_grid

    shift_ll_into_WGS84         shift_ll_from_WGS84

    parse_grid
    parse_trad_grid             format_grid_trad
    parse_GPS_grid              format_grid_GPS
    parse_landranger_grid       format_grid_landranger

    parse_ISO_ll                format_ll_trad
                                format_ll_ISO

None of these is exported by default, so pick the ones you want or use an C<:all> tag to import them all at once.

  use Geo::Coordinates::OSGB ':all';

=over 4

=item ll_to_grid(lat,lon)

When called in a void context, or with no arguments C<ll_to_grid> does nothing.

When called in a list context, C<ll_to_grid> returns two numbers that represent
the easting and the northing corresponding to the latitude and longitude
supplied.

The parameters can be supplied as real numbers representing decimal degrees, like this

    my ($e,$n) = ll_to_grid(51.5, 2.1);

Following the normal convention, positive numbers mean North or East, negative South or West.
If you have data with degrees, minutes and seconds, you can convert them to decimals like this:

    my ($e,$n) = ll_to_grid(51+25/60, 0-5/60-2/3600);

Or you can use a single string in ISO 6709 form, like this:

    my ($e,$n) = ll_to_grid('+5130-00005/');

To learn exactly what is matched by this last option, read the source of the
module and look for the definition of C<$ISO_LL_PATTERN>.  Note that the
neither the C<+> or C<-> signs at the beginning and in the middle, nor the
trailing C</> may be omitted.

If you have trouble remembering the order of the arguments, or the returned
values, note that latitude comes before longitude in the alphabet too, as
easting comes before northing.

The easting and northing will be returned as a whole number of metres from the
point of origin of the British Grid (which is a point a little way to the
south-west of the Scilly Isles).

If you want the result presented in a more traditional grid reference format
you should pass the results to one of the grid formatting routines, which are
described below.  Like this.

    $gridref = format_grid_trad(ll_to_grid(51.5,-0.0833));
    $gridref = format_grid_GPS(ll_to_grid(51.5,-0.0833));
    $gridref = format_grid_landranger(ll_to_grid(51.5,-0.0833));

However if you call C<ll_to_grid> in a scalar context, it will
automatically call C<format_grid_trad> for you.

It is not needed for any normal work, but C<ll_to_grid()> also takes an
optional argument that sets the ellipsoid model to use.  This normally
defaults to `OSGB36', the name of the normal model for working with British
maps.  If you are working with the highly accurate OSTN02 conversions
supplied in the companion module in this distribution, then you will need to
produce pseudo-grid references as input to those routines.  For these
purposes you should call C<ll_to_grid()> like this:

    my $pseudo_gridref = ll_to_grid(51.2, -0.4, 'WGS84');

and then transform this to a real grid reference using C<ETRS89_to_OSGB36()>
from the companion module.  This is explained in more detail below.

=item format_grid_trad(e,n)

Formats an (easting, northing) pair into traditional `full national grid
reference' with two letters and two sets of three numbers, like this
`TQ 102 606'.  If you want to remove the spaces, just apply C<s/\s//g> to it.

    $gridref = format_grid_trad(533000, 180000); # TQ 330 800
    $gridref =~ s/\s//g;                         # TQ330800

If you want the individual components call it in a list context.

    ($sq, $e, $n) = format_grid_trad(533000, 180000); # (TQ,330,800)

Note the easting and northing are truncated to hectometers (as the OS system
demands), so the grid reference refers to the lower left corner of the
relevant 100m square.

=item format_grid_GPS(e,n)

Users who have bought a GPS receiver may initially have been puzzled by the
unfamiliar format used to present coordinates in the British national grid format.
On my Garmin Legend C it shows this sort of thing in the display.

    TQ 23918
   bng 00972

and in the track logs the references look like this C<TQ 23918 00972>.

These are just the same as the references described on the OS sheets, except
that the units are metres rather than hectometres, so you get five digits in
each of the easting and northings instead of three.  So in a scalar context
C<format_grid_GPS()> returns a string like this:

    $gridref = format_grid_GPS(533000, 180000); # TQ 33000 80000

If you call it in a list context, you will get a list of square, easting, and
northing, with the easting and northing as metres within the grid square.

    ($sq, $e, $n) = format_grid_GPS(533000, 180000); # (TQ,33000,80000)

Note that, at least until WAAS is working in Europe, the results from your
GPS are unlikely to be more accurate than plus or minus 5m even with perfect
reception.  Most GPS devices can display the accuracy of the current fix you
are getting, but you should be aware that all normal consumer-level GPS
devices can only ever produce an approximation of an OS grid reference, no
matter what level of accuracy they may display.  The reasons for this are
discussed below in the section on L<Theory>.

=item format_grid_landranger(e,n)

This routine does the same as C<format_grid_trad>, but it appends the number of
the relevant OS Landranger 1:50,000 scale map to the traditional grid
reference.  Note that there may be several or no sheets returned.  This is
because many (most) of the Landranger sheets overlap, and many other valid grid
references are not on any of the sheets (because they are in the sea or a
remote island.  This module does not yet cope with the detached insets on some
sheets.

In a list context you will get back a list like this:  (square, easting,
northing, sheet) or (square, easting, northing, sheet1, sheet2) etc.  There
are a few places where three sheets overlap, and one corner of Herefordshire
which appears on four maps (sheets 137, 138, 148, and 149).  If the GR is not
on any sheet, then the list of sheets will be empty.

In a scalar context you will get back the same information in a helpful
string form like this "NN 241 738 on OS Sheet 44".  Note that the easting and
northing will have been truncated to the normal hectometre three
digit form.  The idea is that you'll use this form for people who might actually
want to look up the grid reference on the given map sheet, and the traditional
GR form is quite enough accuracy for that purpose.

=item parse_trad_grid(grid_ref)

Turns a traditional grid reference into a full easting and northing pair in
metres from the point of origin.  The I<grid_ref> can be a string like
C<'TQ203604'> or C<'SW 452 004'>, or a list like this C<('TV', '435904')> or a list
like this C<('NN', '345', '208')>.


=item parse_GPS_grid(grid_ref)

Does the same as C<parse_trad_grid> but is looking for five digit numbers
like C<'SW 45202 00421'>, or a list like this C<('NN', '34592', '20804')>.

=item parse_landranger_grid(sheet, e, n)

This converts an OS Landranger sheet number and a local grid reference
into a full easting and northing pair in metres from the point of origin.

The OS Landranger sheet number should be between 1 and 204 inclusive (but
I may extend this when I support insets).  You can supply C<(e,n)> as 3-digit
hectometre numbers or 5-digit metre numbers.  In either case if you supply
any leading zeros you should 'quote' the numbers to stop Perl thinking that
they are octal constants.

This module will croak at you if you give it an undefined sheet number, or
if the grid reference that you supply does not exist on the sheet.

In order to get just the coordinates of the SW corner of the sheet, just call
it with the sheet number.  It is easy to work out the coordinates of the
other corners, because all OS Landranger maps cover a 40km square (if you
don't count insets or the occasional sheet that includes extra details
outside the formal margin).

=item parse_grid(grid_ref)

Attempts to match a grid reference some form or other in the input string
and will then call the appropriate grid parsing routine from those defined
above.  In particular it will parse strings in the form C<'176-345210'>
meaning grid ref 345 210 on sheet 176, as well as C<'TQ345210'> and C<'TQ
34500 21000'> etc.  You can in fact always use "parse_grid" instead of the more
specific routines unless you need to be picky about the input.

=item grid_to_ll(e,n) or grid_to_ll(grid_ref)

When called in list context C<grid_to_ll()> returns a pair of numbers
representing longitude and latitude coordinates, as real numbers.  Following
convention, positive numbers are North and East, negative numbers are South
and West.  The fractional parts of the results represent fractions of
degrees.

When called in scalar context it returns a string in ISO longitude and latitude
form, such as C<'+5025-00403/'> with the result rounded to the nearest minute (the
formulae are not much more accurate than this).  In a void context it does
nothing.

The arguments must be an (easting, northing) pair representing the absolute
grid reference in metres from the point of origin.  You can get these from a
grid reference string by calling C<parse_grid()> first.

An optional last argument defines the geoid model to use just as it does for
C<ll_to_grid()>.  This is only necessary is you are working with the
pseudo-grid references produced by the OSTN02 routines.  See L<Theory> for more
discussion.

=item format_ll_trad(lat, lon)

Takes latitude and longitude in decimal degrees as arguments and returns a string like this

    N52:12:34 W002:30:27

In a list context it returns all 8 elements (hemisphere, degrees, minutes,
seconds for each of lat and lon) in a list.  In a void context it does nothing.

=item format_ll_ISO(lat, lon)

Takes latitude and longitude in decimal degrees as arguments and returns a
string like this

    +5212-00230/

In a list context it returns all 6 elements (sign, degrees, minutes for each of
lat and lon) in a list.  In a void context it does nothing.


=item parse_ISO_ll(ISO_string)

Reads an ISO 6709 formatted location identifier string such as '+5212-00230/'.
To learn exactly what is matched by this last option, read the source of the
module and look for the definition of C<$ISO_LL_PATTERN>.  Note that the
neither the C<+> or C<-> signs at the beginning and in the middle, nor the
trailing C</> may be omitted.  These strings can also include the altitude of a
point, in metres, like this: '+5212-00230+140/'.  If you omit the altitude, 0
is assumed.

In a list context it returns ($lat, $lon, $altitude).  So if you don't want or
don't need the altitude, you should just drop it, for example like this:

   my ($lat, $lon) = parse_ISO_ll('+5212-00230/')

In normal use you won't notice this.  In particular you don't need to worry
about it when passing the results on to C<ll_to_grid>, as that routine looks
for an optional altitude after the lat/lon.

=item shift_ll_from_WGS84(lat, lon, altitude)

Takes latitude and longitude in decimal degrees (plus an optional altitude in
metres) from a WGS84 source (such as your GPS handset or Google Earth) and
returns an approximate equivalent latitude and longitude according to the
OSGM02 model.  To determine the OSGB grid reference for given WGS84 lat/lon
coordinates, you should call this before you call C<ll_to_grid>.  Like so:

  ($lat, $lon, $alt) = shift_ll_from_WGS84($lat, $lon, $alt);
  ($e, $n) = ll_to_grid($lat,$lon);

You don't need to call this to determine a grid reference from lat/lon
coordinates printed on OSGB maps (the so called "graticule intersections"
marked in pale blue on the Landranger series).

This routine provide a fast approximation; for a slower, more accurate
approximation use the companion L<Geo::Coordinates::OSTN02> modules.

=item shift_ll_into_WGS84(lat, lon, altitude)

Takes latitude and longitude in decimal degrees (plus an optional altitude in
metres) from an OSGB source (such as coordinates you read from a Landranger
map, or more likely coordinates returned from C<grid_to_ll()>) and adjusts them
to fit the WGS84 model.

To determine WGS84 lat/lon coordinates (for use in Wikipedia, or Google Earth
etc) for a given OSGB grid reference, you should call this after you call
C<grid_to_ll()>.  Like so:

  ($lat, $lon) = grid_to_ll($e, $n);
  ($lat, $lon, $alt) = shift_ll_into_WGS84($lat, $lon, $alt);

This routine provide a fast approximation; for a slower, more accurate
approximation use the companion L<Geo::Coordinates::OSTN02> modules.

=back


=head1 THEORY

The algorithms and theory for these conversion routines are all from
I<A Guide to Coordinate Systems in Great Britain>
published by the OSGB, April 1999 (Revised Dec 2010) and available at
http://www.ordnancesurvey.co.uk/.

You may also like to read some of the other introductory material there.
Should you be hoping to adapt this code to your own custom Mercator
projection, you will find the paper called I<Surveying with the
National GPS Network>, especially useful.

The routines are intended for use in Britain with the Ordnance Survey's
National Grid, however they are written in an entirely generic way, so that
you could adapt them to any other ellipsoid model that is suitable for your
local area of the earth.   There are other modules that already do this that
may be more suitable (which are referenced in the L<See Also> section), but
the key parameters are all defined at the top of the module.

    $ellipsoid_shapes{OSGB36} = [ 6377563.396,  6356256.910  ];
    use constant ORIGIN_LONGITUDE   => RAD * -2;  # lon of grid origin
    use constant ORIGIN_LATITUDE    => RAD * 49;  # lat of grid origin
    use constant ORIGIN_EASTING     =>  400000;   # Easting for origin
    use constant ORIGIN_NORTHING    => -100000;   # Northing for origin
    use constant CONVERGENCE_FACTOR => 0.9996012717; # Convergence factor

The ellipsoid model is defined by two numbers that represent the major and
minor radius measured in metres.  The Mercator grid projection is then
defined by the other five parameters.  The general idea is that you pick a
suitable point to start the grid that minimizes the inevitable distortion
that is involved in a Mercator projection from spherical to Euclidean
coordinates.  Such a point should be on a meridian that bisects the area of
interest and is nearer to the equator than the whole area.  So for Britain
the point of origin is 2W and 49N (in the OSGB geoid model) which is near
the Channel Islands.  This point should be set as the C<ORIGIN_LONGITUDE>
and C<ORIGIN_LATITUDE> parameters (as above) measured in radians.  Having
this True Point of Origin in the middle and below (or above if you are
antipodean) minimizes distortion but means that some of the grid values
would be negative unless you then also adjust the grid to make sure you do
not get any negative values in normal use.  This is done by defining the
grid coordinates of the True Point of Origin to be such that all the
coordinates in the area of interest will be positive.  These are the
parameters C<ORIGIN_EASTING> and C<ORIGIN_NORTHING>.  For Britain the
coordinates are set as 400000 and -100000, so the that point (0,0) in the
grid is just to the south west of the Scilly Isles.  This (0,0) point is
called the False Point of Origin.  The fifth parameter affects the
convergence of the Mercator projection as you get nearer the pole; this is
another feature designed to minimize distortion, and if in doubt set it to 1
(which means it has no effect).  For Britain, being so northerly it is set
to slightly less than 1.

=head2 The British National Grid

One consequence of the True Point of Origin of the British Grid being set to
C<+4900-00200/> is that all the vertical grid lines are parallel to the 2W
meridian; you can see this on the appropriate OS maps (for example
Landranger sheet 184), or on the C<plotmaps.pdf> picture supplied with this
package.  The effect of moving the False Point of Origin to the far south
west is that all grid references always positive.

Strictly grid references are given as whole numbers of metres from this
point, with the easting always given before the northing.  For everyday use
however, the OSGB suggest that grid references need only to be given within
the local 100km square as this makes the numbers smaller.  For this purpose
they divide Britain into a series of 100km squares identified in pair of
letters:  TQ, SU, ND, etc.  The grid of the big squares actually used is
something like this:

                               HP
                               HU
                            HY
                   NA NB NC ND
                   NF NG NH NJ NK
                   NL NM NN NO NP
                      NR NS NT NU
                      NW NX NY NZ
                         SC SD SE TA
                         SH SJ SK TF TG
                      SM SN SO SP TL TM
                      SR SS ST SU TQ TR
                   SV SW SX SY SZ TV

SW covers most of Cornwall, TQ London, and HU the Shetlands.  Note that it
has the neat feature that N and S are directly above each other, so that
most Sx squares are in the south and most Nx squares are in the north.

Within each of these large squares, we only need five digit coordinates ---
from (0,0) to (99999,99999) --- to refer to a given square metre.  For daily
use however we don't generally need such precision, so the normal
recommended usage is to use units of 100m (hectometres) so that we only need
three digits for each easting and northing --- 000,000 to 999,999.  If we
combine the easting and northing we get the familiar traditional six figure
grid reference.  Each of these grid references is repeated in each of the
large 100km squares but for local use with a particular map, this does not
usually matter.  Where it does matter, the OS suggest that the six figure
reference is prefixed with the identifier of the large grid square to give a
`full national grid reference', such as TQ330800.  This system is described
in the notes of in the corner of every Landranger 1:50,000 scale map.

Modern GPS receivers can all display coordinates in the OS grid system.  You
just need to set the display units to be `British National Grid' or whatever
similar name is used on your unit.  Most units display the coordinates as two
groups of five digits and a grid square identifier.  The units are metres within
the grid square (although beware that the GPS fix is unlikely to be accurate down
to the last metre).


=head2 Geoid models

This section explains the fundamental problems of mapping a spherical earth
onto a flat piece of paper (or computer screen).  A basic understanding of
this material will help you use these routines more effectively.  It will
also provide you with a good store of ammunition if you ever get into an
argument with someone from the Flat Earth Society.

It is a direct consequence of Newton's law of universal gravitation (and in
particular the bit that states that the gravitational attraction between two
objects varies inversely as the square of the distance between them) that all
planets are roughly spherical.  (If they were any other shape gravity would
tend to pull them into a sphere).  On the other hand, most useful surfaces
for displaying large scale maps (such as pieces of paper or screens) are
flat.  There is therefore a fundamental problem in making any maps of the
earth that its curved surface being mapped must be distorted at least
slightly in order to get it to fit onto the flat map.

This module sets out to solve the corresponding problem of converting
latitude and longitude coordinates (designed for a spherical surface) to and
from a rectangular grid (for a flat surface).  This projection is in itself
is a fairly lengthy bit of maths, but what makes it extra complicated is
that the earth is not quite a sphere.  Because our planet spins about a
vertical axis, it tends to bulge out slightly in the middle, so it is more
of an oblate spheroid than a sphere.  This makes the maths even longer, but
the real problem is that the earth is not a regular oblate spheroid either,
but an irregular lump that closely resembles an oblate spheroid and which is
constantly (if slowly) being rearranged by plate tectonics.  So the best we
can do is to pick an imaginary regular oblate spheroid that provides a good
fit for the region of the earth that we are interested in mapping.  The
British Ordnance Survey did this back in 1830 and have used it ever since as
the base on which the National Grid for Great Britain is constructed.  You
can also call an oblate spheroid an ellipsoid if you like.  The general term
for an ellipsoid model of the earth is a "geoid".

The first standard OSGB geoid is known as "Airy 1830" after the year of its
first development.  It was revised in 1936, and that version, generally
known as OSGB36, is the basis of all current OSGB mapping.  In 2002 the
model was redefined (but not functionally changed) as a transformation from
the international geoid model WGS84.  This redefinition is called OSGM02.
For the purposes of these modules (and most other purposes) OSGB36 and
OSGM02 may be treated as synonyms.

The general idea is that you can establish your latitude and longitude by
careful observation of the sun, the moon, the planets, or your GPS handset,
and that you then do some clever maths to work out the corresponding grid
reference using a suitable geoid.  These modules let you do the clever
maths, and the geoid they use is the OSGM02 one.  This model provides a good
match to the local shape of the Earth in the British Isles, but is not
designed for use in the rest of the world; there are many other models in
use in other countries.

In the mid-1980s a new standard geoid model was defined to use with the
fledgling global positioning system (GPS).  This model is known as WGS84, and
is designed to be a compromise model that works equally well for all parts of
the globe (or equally poorly depending on your point of view --- for one
thing WGS84 defines the Greenwich observatory in London to be not quite on
the zero meridian).  Nevertheless WGS84 has grown in importance as GPS systems
have become consumer items and useful global mapping tools (such as Google
Earth) have become freely available through the Internet.  Most latitude and
longitude coordinates quoted on the Internet (for example in Wikipedia) are
WGS84 coordinates.

One thing that should be clear from the theory is that there is no such
thing as a single definitive set of coordinates for every unique spot on
earth.  There are only approximations based on one or other of the accepted
geoid models, however for most practical purposes good approximations are
all you need.  In Europe the official definition of WGS84 is sometime
referred to as ETRS89.  For all practical purposes in Western Europe the OS
advise that one can regard ETRS89 as identical to WGS84 (unless you need to
worry about tectonic plate movements).

=head2 Practical implications

If you are working exclusively with British OS maps and you merely want
to convert from the grid to the latitude and longitude coordinates printed (as
faint blue crosses) on those maps, then all you need from these modules are
the plain C<grid_to_ll()> and C<ll_to_grid()> routines.  On the other hand if
you want to produce latitude and longitude coordinates suitable for Google
Earth or Wikipedia from a British grid reference, then you need an extra
step.  Convert your grid reference using C<grid_to_ll()> and then shift it
from the OSGB model to the WGS84 model using C<shift_ll_into_WGS84()>.  To
go the other way round, shift your WGS84 lat/lon coordinated into OSGB,
using C<shift_ll_from_WGS84()>, before you convert them using
C<ll_to_grid()>.

If you have a requirement for really accurate work (say to within a
millimetre or two) then you need to use the OS's transformation matrix
called OSTN02.  This monumental work published in 2002 re-defined the
British grid in terms of offsets from WGS84 to allow really accurate grid
references to be determined from really accurate GPS readings (the sort you
get from professional fixed base stations, not from your car's sat nav or
your hand-held device).  The problem with it is that it defines the grid in
terms of a deviation in three dimensions from a pseudo-grid based on WGS84
and it does this separately for every square km of the country, so the data
set is huge and takes a second or two to load even on a fast machine.
Nevertheless a Perl version of OSTN02 is included as a separate module in
this distribution just in case you really need it (but you don't need it for
any "normal" work).  Because of the way OSTN02 is defined, the sequence of
conversion and shifting works differently from the approximate routines
described above.

Starting with a really accurate lat/lon reading in WGS84 terms, you need to
transform it into a pseudo-grid reference using C<ll_to_grid()> using an
optional argument to tell it to use the WGS84 geoid parameters instead of
the default OSGB parameters.  The L<Geo::Coordinates::OSTN02> package
provides a routine called C<ETRS89_to_OSGB36()> which will shift this pseudo-grid
reference into an accurate OSGB grid reference.  To go back the other way,
you use C<OSGB36_to_ETRS89()> to make a pseudo-grid reference, and then call
C<grid_to_ll()> with the WGS84 parameter to get WGS84 lat/long coordinates.


   ($lat, $lon, $height) = (51.5, -1, 10);
   ($x, $y) = ll_to_grid($lat, $lon, 'WGS84');
   ($e, $n, $elevation) = ETRS89_to_OSGB36($x, $y, $height);

   ($x, $y, $z) = OSGB36_to_ETRS89($e, $n, $elevation);
   ($lat, $lon) = grid_to_ll($x, $y, 'WGS84');


=head1 EXAMPLES

  # to import everything try...
  use Geo::Coordinates::OSGB ':all';

  # Get full coordinates in metres from GR
  ($e,$n) = parse_trad_grid('TQ 234 098');

  # Latitude and longitude according to the OSGB geoid (as
  # printed on OS maps), if you want them to work in Google
  # Earth or some other tool that uses WGS84 then adjust results
  ($lat, $lon) = grid_to_ll($e, $n);
  ($lat, $lon, $alt) = shift_ll_into_WGS84($lat, $lon, $alt);
  # and to go the other way
  ($lat, $lon, $alt) = shift_ll_from_WGS84($lat, $lon, $alt);
  ($e, $n) = ll_to_grid($lat,$lon);
  # In both cases the elevation is in metres (default=0m)

  # Reading and writing grid references
  # Format full easting and northing into traditional formats
  $gr1 = format_grid_trad($e, $n);      # "TQ 234 098"
  $gr1 =~ s/\s//g;                      # "TQ234098"
  $gr2 = format_grid_GPS($e, $n);       # "TQ 23451 09893"
  $gr3 = format_grid_landranger($e, $n);# "TQ 234 098 on Sheet 176"
  # or call in list context to get the individual parts
  ($sq, $e, $n) = format_grid_trad($e, $n); # ('TQ', 234, 98)

  # parse routines to convert from these formats to full e,n
  ($e,$n) = parse_grid('TQ 234 098');
  ($e,$n) = parse_grid('TQ234098'); # spaces optional
  ($e,$n) = parse_grid('TQ',234,98); # or even as a list
  ($e,$n) = parse_grid('TQ 23451 09893'); # as above..

  # You can also get grid refs from individual maps.
  # Sheet between 1..204; gre & grn must be 3 or 5 digits long
  ($e,$n) = parse_grid(176,123,994);

  # With just the sheet number you get GR for SW corner
  ($e,$n) = parse_grid(184);

  # Reading and writing lat/lon coordinates
  ($lat, $lon) = parse_ISO_ll("+52-002/");
  $iso = format_ll_ISO($lat,$lon);    # "+520000-0020000/"
  $str = format_ll_trad($lat,$lon);   # "N52:00:00 W002:00:00"


=head1 BUGS AND LIMITATIONS

The conversions are only approximate.   So after

  ($a1,$b1) = grid_to_ll(ll_to_grid($a,$b));

neither C<$a==$a1> nor C<$b==$b1>. However C<abs($a-$a1)> and C<abs($b-$b1)>
should be less than C<0.00001> which will give you accuracy to within a
metre. In the middle of the grid 0.00001 degrees is approximately 1 metre.
Note that the error increases the further away you are from the
central meridian of the grid system.

The C<format_grid_landranger()> does not take account of inset areas on the
sheets.  So if you feed it a reference for the Scilly Isles, it will tell you
that the reference is not on any Landranger sheet, whereas in fact the
Scilly Isles are on an inset in the SW corner of Sheet 203.  There is
nothing in the design that prevents me adding the insets, they just need to
be added as extra sheets with names like "Sheet 2003 Inset 1" with their own
reference points and special sheet sizes.  Collecting the data is another
matter.

Not enough testing has been done.  I am always grateful for the feedback I
get from users, but especially for problem reports that help me to make this
a better module.

=head1 DIAGNOSTICS

Should this software not do what you expect, then please first read this documentation,
secondly verify that you have installed it correctly and that it passes all the installation tests on your set up,
thirdly study the source code to see what it's supposed to be doing, fourthly get in touch to ask me about it.

=head1 CONFIGURATION AND ENVIRONMENT

There is no configuration required either of these modules or your environment. It should work on any recent version of
perl, on any platform.

=head1 DEPENDENCIES

None.

=head1 INCOMPATIBILITIES

None known.

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2002-2013 Toby Thurston

OSTN02 transformation data is freely available but remains Crown Copyright (C) 2002

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Toby Thurston -- 04 Oct 2013 

toby@cpan.org

=head1 SEE ALSO

The UK Ordnance Survey's theory paper referenced above.

See L<Geo::Coordinates::Convert> for a general approach (not based on the above paper).

See L<Geo::Coordinates::Lambert> for a French approach.

=cut
