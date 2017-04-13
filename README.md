# Geocraft Minecraft Map Generator

Generate minecraft maps of real locations using UK LIDAR data (laser scans of 
terrain) and information from OpenStreetMap.

## Installation

This software uses Perl and is dependent on the following module:

* Archive::Zip

You'll need to ensure those are installed before using the software. To check you can use:

perl -MArchive::ZIP -e 'print "OK\n";'

Which will say "OK" if it's installed, and otherwise will report an error.

## Generating a World

The `generate-world` command is used to create your minecraft world. It provides 
a number of options for customising the location of the world and how it is 
generated.

Internet access is essential at all times whilst generating a world as it 
will be downloading lots of data.

The following generates a minecraft world called "Highfield" which will be stored 
in the `/saves/subdirectory`. It's centred on 
a postcode in Southampton and will be 1km square (1000 blocks wide, 500 blocks either side 
of the central point)

```
./generate-world --postcode SO171BJ --size 1000 Highfield
```

It's recommended that while you are testing that you generate smaller worlds. Obviously 
the larger the map, the longer it will take to generate.

You may find it handy to symlink the /saves/ directory to your minecraft saves location. 
You can also generate the map in a different location using the ``--saves`` option:

```
./generate-world --saves /path/to/.minecraft/saves --postcode SO171BJ --size 1000 Highfield
```

If a world of the given name already exists then the script will refuse to overwrite it. 
Use the ``--replace`` option to force overwriting of an existing world. Again, useful 
whilst testing your configuration:

```
./generate-world --replace --postcode SO171BJ --size 1000 Highfield
```

Instead of a postcode you can specify the central point of the map using a specific 
location. You can use either an easting and northing, or a latitude and longitude. 
By default the script assumes you're providing easting and northing, but the 
`--ll` allows you to switch:

```
./generate-world --centre 375046,164145 --size 1000 Highfield
./generate-world --ll --centre 51.375801,-2.3599039 --size 1000 Highfield
```

The generation of the world can be customised by tweaking the configuration 
given in the `config` directory. It's possible to override these to use different 
configuration files using the ``--blocks`` and ``--colours`` parameters. 

For example in Bath you may want to use sandstone instead of brick for generating 
buildings. The ``blocks.winter`` and ``blocks.nether`` configure allow you to 
generate worlds winter biome or as part of the nether.

The ``blocks.hollow`` config generates hollow buildings. It's worth using but 
takes much longer to generate a world.

## Options

You must use either postcode with size, centre with size or specify a from & to. You must always specify the name of the world to save.

* --saves `mc-saves-dir`  :: Optional. Specify location of Minecraft /saves/ directory.
* --ll :: Option to indicate that the cordinates are in lat,long (rather than UK easting/northing).
* --postcode `postcode` :: the UK postcode to centre on.
* --centre `x`,`y` :: the centre of the map to create (instead of using a postcode)
* --size `n` :: size of a square map.
* --size `w`,`h` :: size of a rectangular map.
* --replace :: delete the existing minecraft world and replace it.
* --yshift `n` :: move the world vertically up or down. Useful for districts very high above sealevel.
* --flood `n` :: air blocks between this height and sealevel will be made into water instead, simulating sea-level rise.
* --elevation `plugin` :: use an alternate elevation plugin. Default is UKDefra. Alternate is Flat (for no LIDAR data).
* --blocks `file` :: use an alternate file to decide how to render blocks. --blocks config/blocks.hollow makes hollow buildings, at a cost of speed.
* --colours `file` :: use an alternate file to interpret colours in open streetmap tiles.
* --rotate `degrees` :: rotate the map (90 degrees is a one-quarter rotation. This option is a bit messy still and the origin of rotation is something weird. 
* --scale `factor` :: make the world larger or smaller. By default one Minecraft block is one real-world block. If you use --scale 0.1 then every Minecraft block will represent 10 real world metres.
* --mapzoom `zoom` :: use a different level of detail from open streetmap. Outside cities this should be lowered to avoid forcing open street map to generate high resultion tiles of empty space. Be a good citizen!
* --tiles `tile-pattern` :: use an alternate map tile server.
* --grid `projection` :: use an alternate map projection. Default is OSGB36 for UK stuff. For anywhere else, use --grid MERC (combined with --elevation Flat)


## Attribution & Copyright

This software is provided under the GPLv3. Please feel free to alter and share it.

This version was written by Christopher Gutteridge at the University of Southampton.
(c) 2015-2017 Christopher Gutteridge

LIDAR data (c) Defra under the Open Government License.
Map data (c) Open Streetmap Contributors under Creative Commons Attribution ShareAlike License.

## Contact Details

Github: https://github.com/cgutteridge/geocraft
Facebook: https://www.facebook.com/magic.minecraft.map.maker/

Author contact info:
Email: cjg@ecs.soton.ac.uk
Twitter: cgutteridge

## Similar Projects

* http://www.chunkmapper.com/ Chunkmapper builds 1:30 scale maps with buildings and rail
* https://www.ordnancesurvey.co.uk/blog/tag/minecraft/ The UK Ordnace Survey has made a scale map of the whole country
