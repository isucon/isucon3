#!perl -w
use strict;
use Test::More tests => 9;
use Imager;
use Imager::Test qw(test_image);

-d "testout" or mkdir "testout";

Imager->open_log(log => "testout/t30fixed.log");

{
  # RT 67912
  # previously, if you tried to write a paletted image to GIF:
  #  - specified a fixed palette with make_colors => "mono", "web" or "none"
  #  - there was room for the colors in the image in the rest of the
  #  palette (or they were found in the generated palette)
  # the GIF would be written with essentially it's original palette
  # instead of the specified palette
  #
  # This was confusing, especially if you specified a restricted
  # palette such as mono or a small greyscale ramp

  my $src = test_image();
  ok($src, "make source image");
  my $pal = $src->to_paletted(max_colors => 250);
  ok($pal, "make paletted version");
  cmp_ok($pal->colorcount, "<=", 250, "make sure not too many colors");

  my $mono = $src->to_paletted(make_colors => "mono", translate => "errdiff");
  ok($mono, "make mono image directly");
  ok($mono->write(file => "testout/t30monodirect.gif", type => "gif"),
     "save mono direct image");

  Imager->log("Save manually paletted version\n");
  ok($pal->write(file => "testout/t30color.gif"),
     "save generated palette version");
  Imager->log("Save mono version\n");
  ok($pal->write(file => "testout/t30monoind.gif", type => "gif",
		 make_colors => "mono", translate => "errdiff"),
     "write paletted with mono colormap");

  my $rd = Imager->new(file => "testout/t30monoind.gif", type => "gif");
  ok($rd, "read it back in");
  is($rd->colorcount, 2, "should only have 2 colors");
}

Imager->close_log;
