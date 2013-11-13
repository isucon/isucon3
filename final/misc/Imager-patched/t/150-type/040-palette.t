#!perl -w
# some of this is tested in t01introvert.t too
use strict;
use Test::More tests => 226;
BEGIN { use_ok("Imager", ':handy'); }

use Imager::Test qw(image_bounds_checks test_image is_color3 isnt_image is_color4 is_fcolor3);

Imager->open_log(log => "testout/t023palette.log");

sub isbin($$$);

my $img = Imager->new(xsize=>50, ysize=>50, type=>'paletted');

ok($img, "paletted image created");

is($img->type, 'paletted', "got a paletted image");

my $black = Imager::Color->new(0,0,0);
my $red = Imager::Color->new(255,0,0);
my $green = Imager::Color->new(0,255,0);
my $blue = Imager::Color->new(0,0,255);

my $white = Imager::Color->new(255,255,255);

# add some color
my $blacki = $img->addcolors(colors=>[ $black, $red, $green, $blue ]);

print "# blacki $blacki\n";
ok(defined $blacki && $blacki == 0, "we got the first color");

is($img->colorcount(), 4, "should have 4 colors");
is($img->maxcolors, 256, "maxcolors always 256");

my ($redi, $greeni, $bluei) = 1..3;

my @all = $img->getcolors;
ok(@all == 4, "all colors is 4");
coloreq($all[0], $black, "first black");
coloreq($all[1], $red, "then red");
coloreq($all[2], $green, "then green");
coloreq($all[3], $blue, "and finally blue");

# keep this as an assignment, checking for scalar context
# we don't want the last color, otherwise if the behaviour changes to
# get all up to the last (count defaulting to size-index) we'd get a
# false positive
my $one_color = $img->getcolors(start=>$redi);
ok($one_color->isa('Imager::Color'), "check scalar context");
coloreq($one_color, $red, "and that it's what we want");

# make sure we can find colors
ok(!defined($img->findcolor(color=>$white)), 
    "shouldn't be able to find white");
ok($img->findcolor(color=>$black) == $blacki, "find black");
ok($img->findcolor(color=>$red) == $redi, "find red");
ok($img->findcolor(color=>$green) == $greeni, "find green");
ok($img->findcolor(color=>$blue) == $bluei, "find blue");

# various failure tests for setcolors
ok(!defined($img->setcolors(start=>-1, colors=>[$white])),
    "expect failure: low index");
ok(!defined($img->setcolors(start=>1, colors=>[])),
    "expect failure: no colors");
ok(!defined($img->setcolors(start=>5, colors=>[$white])),
    "expect failure: high index");

# set the green index to white
ok($img->setcolors(start => $greeni, colors => [$white]),
    "set a color");
# and check it
coloreq(scalar($img->getcolors(start=>$greeni)), $white,
	"make sure it was set");
ok($img->findcolor(color=>$white) == $greeni, "and that we can find it");
ok(!defined($img->findcolor(color=>$green)), "and can't find the old color");

# write a few colors
ok(scalar($img->setcolors(start=>$redi, colors=>[ $green, $red])),
	   "save multiple");
coloreq(scalar($img->getcolors(start=>$redi)), $green, "first of multiple");
coloreq(scalar($img->getcolors(start=>$greeni)), $red, "second of multiple");

# put it back
$img->setcolors(start=>$red, colors=>[$red, $green]);

# draw on the image, make sure it stays paletted when it should
ok($img->box(color=>$red, filled=>1), "fill with red");
is($img->type, 'paletted', "paletted after fill");
ok($img->box(color=>$green, filled=>1, xmin=>10, ymin=>10,
	      xmax=>40, ymax=>40), "green box");
is($img->type, 'paletted', 'still paletted after box');
# an AA line will almost certainly convert the image to RGB, don't use
# an AA line here
ok($img->line(color=>$blue, x1=>10, y1=>10, x2=>40, y2=>40),
    "draw a line");
is($img->type, 'paletted', 'still paletted after line');

# draw with white - should convert to direct
ok($img->box(color=>$white, filled=>1, xmin=>20, ymin=>20, 
	      xmax=>30, ymax=>30), "white box");
is($img->type, 'direct', "now it should be direct");

# various attempted to make a paletted image from our now direct image
my $palimg = $img->to_paletted;
ok($palimg, "we got an image");
# they should be the same pixel for pixel
ok(Imager::i_img_diff($img->{IMG}, $palimg->{IMG}) == 0, "same pixels");

# strange case: no color picking, and no colors
# this was causing a segmentation fault
$palimg = $img->to_paletted(colors=>[ ], make_colors=>'none');
ok(!defined $palimg, "to paletted with an empty palette is an error");
print "# ",$img->errstr,"\n";
ok(scalar($img->errstr =~ /no colors available for translation/),
    "and got the correct msg");

ok(!Imager->new(xsize=>1, ysize=>-1, type=>'paletted'), 
    "fail on -ve height");
cmp_ok(Imager->errstr, '=~', qr/Image sizes must be positive/,
       "and correct error message");
ok(!Imager->new(xsize=>-1, ysize=>1, type=>'paletted'), 
    "fail on -ve width");
cmp_ok(Imager->errstr, '=~', qr/Image sizes must be positive/,
       "and correct error message");
ok(!Imager->new(xsize=>-1, ysize=>-1, type=>'paletted'), 
    "fail on -ve width/height");
cmp_ok(Imager->errstr, '=~', qr/Image sizes must be positive/,
       "and correct error message");

ok(!Imager->new(xsize=>1, ysize=>1, type=>'paletted', channels=>0),
    "fail on 0 channels");
cmp_ok(Imager->errstr, '=~', qr/Channels must be positive and <= 4/,
       "and correct error message");
ok(!Imager->new(xsize=>1, ysize=>1, type=>'paletted', channels=>5),
    "fail on 5 channels");
cmp_ok(Imager->errstr, '=~', qr/Channels must be positive and <= 4/,
       "and correct error message");

{
  # https://rt.cpan.org/Ticket/Display.html?id=8213
  # check for handling of memory allocation of very large images
  # only test this on 32-bit machines - on a 64-bit machine it may
  # result in trying to allocate 4Gb of memory, which is unfriendly at
  # least and may result in running out of memory, causing a different
  # type of exit
  use Config;
 SKIP:
  {
    skip("don't want to allocate 4Gb", 10)
      unless $Config{ptrsize} == 4;

    my $uint_range = 256 ** $Config{intsize};
    my $dim1 = int(sqrt($uint_range))+1;
    
    my $im_b = Imager->new(xsize=>$dim1, ysize=>$dim1, channels=>1, type=>'paletted');
    is($im_b, undef, "integer overflow check - 1 channel");
    
    $im_b = Imager->new(xisze=>$dim1, ysize=>1, channels=>1, type=>'paletted');
    ok($im_b, "but same width ok");
    $im_b = Imager->new(xisze=>1, ysize=>$dim1, channels=>1, type=>'paletted');
    ok($im_b, "but same height ok");
    cmp_ok(Imager->errstr, '=~', qr/integer overflow/,
           "check the error message");

    # do a similar test with a 3 channel image, so we're sure we catch
    # the same case where the third dimension causes the overflow
    # for paletted images the third dimension can't cause an overflow
    # but make sure we didn't anything too dumb in the checks
    my $dim3 = $dim1;
    
    $im_b = Imager->new(xsize=>$dim3, ysize=>$dim3, channels=>3, type=>'paletted');
    is($im_b, undef, "integer overflow check - 3 channel");
    
    $im_b = Imager->new(xsize=>$dim3, ysize=>1, channels=>3, type=>'paletted');
    ok($im_b, "but same width ok");
    $im_b = Imager->new(xsize=>1, ysize=>$dim3, channels=>3, type=>'paletted');
    ok($im_b, "but same height ok");

    cmp_ok(Imager->errstr, '=~', qr/integer overflow/,
           "check the error message");

    # test the scanline allocation check
    # divide by 2 to get int range, by 3 so that the image (one byte/pixel)
    # doesn't integer overflow, but the scanline of i_color (4/pixel) does
    my $dim4 = $uint_range / 3;
    my $im_o = Imager->new(xsize=>$dim4, ysize=>1, channels=>3, type=>'paletted');
    is($im_o, undef, "integer overflow check - scanline size");
    cmp_ok(Imager->errstr, '=~', 
           qr/integer overflow calculating scanline allocation/,
           "check error message");
  }
}

{ # http://rt.cpan.org/NoAuth/Bug.html?id=9672
  my $warning;
  local $SIG{__WARN__} = 
    sub { 
      $warning = "@_";
      my $printed = $warning;
      $printed =~ s/\n$//;
      $printed =~ s/\n/\n\#/g; 
      print "# ",$printed, "\n";
    };
  my $img = Imager->new(xsize=>10, ysize=>10);
  $img->to_paletted();
  cmp_ok($warning, '=~', 'void', "correct warning");
  cmp_ok($warning, '=~', 'palette\\.t', "correct file");
}

{ # http://rt.cpan.org/NoAuth/Bug.html?id=12676
  # setcolors() has a fencepost error
  my $img = Imager->new(xsize=>10, ysize=>10, type=>'paletted');

  is($img->addcolors(colors=>[ $black, $red ]), "0 but true",
     "add test colors");
  ok($img->setcolors(start=>1, colors=>[ $green ]), "set the last color");
  ok(!$img->setcolors(start=>2, colors=>[ $black ]), 
     "set after the last color");
}

{ # https://rt.cpan.org/Ticket/Display.html?id=20056
  # added named color support to addcolor/setcolor
  my $img = Imager->new(xsize => 10, ysize => 10, type => 'paletted');
  is($img->addcolors(colors => [ qw/000000 FF0000/ ]), "0 but true",
     "add colors as strings instead of objects");
  my @colors = $img->getcolors;
  iscolor($colors[0], $black, "check first color");
  iscolor($colors[1], $red, "check second color");
  ok($img->setcolors(colors => [ qw/00FF00 0000FF/ ]),
     "setcolors as strings instead of objects");
  @colors = $img->getcolors;
  iscolor($colors[0], $green, "check first color");
  iscolor($colors[1], $blue, "check second color");

  # make sure we handle bad colors correctly
  is($img->colorcount, 2, "start from a known state");
  is($img->addcolors(colors => [ 'XXFGXFXGXFX' ]), undef,
     "fail to add unknown color");
  is($img->errstr, 'No color named XXFGXFXGXFX found', 'check error message');
  is($img->setcolors(colors => [ 'XXFGXFXGXFXZ' ]), undef,
     "fail to set to unknown color");
  is($img->errstr, 'No color named XXFGXFXGXFXZ found', 'check error message');
}

{ # https://rt.cpan.org/Ticket/Display.html?id=20338
  # OO interface to i_glin/i_plin
  my $im = Imager->new(xsize => 10, ysize => 10, type => 'paletted');
  is($im->addcolors(colors => [ "#000", "#F00", "#0F0", "#00F" ]), "0 but true",
     "add some test colors")
    or print "# ", $im->errstr, "\n";
  # set a pixel to check
  $im->setpixel(x => 1, 'y' => 0, color => "#0F0");
  is_deeply([ $im->getscanline('y' => 0, type=>'index') ],
            [ 0, 2, (0) x 8 ], "getscanline index in list context");
  isbin($im->getscanline('y' => 0, type=>'index'),
        "\x00\x02" . "\x00" x 8,
        "getscanline index in scalar context");
  is($im->setscanline('y' => 0, pixels => [ 1, 2, 0, 3 ], type => 'index'),
     4, "setscanline with list");
  is($im->setscanline('y' => 0, x => 4, pixels => pack("C*", 3, 2, 1, 0, 3),
                      type => 'index'),
     5, "setscanline with pv");
  is_deeply([ $im->getscanline(type => 'index', 'y' => 0) ],
            [ 1, 2, 0, 3, 3, 2, 1, 0, 3, 0 ],
            "check values set");
  eval { # should croak on OOR index
    $im->setscanline('y' => 1, pixels => [ 255 ], type=>'index');
  };
  ok($@, "croak on setscanline() to invalid index");
  eval { # same again with pv
    $im->setscanline('y' => 1, pixels => "\xFF", type => 'index');
  };
  ok($@, "croak on setscanline() with pv to invalid index");
}

{
  print "# make_colors => mono\n";
  # test mono make_colors
  my $imrgb = Imager->new(xsize => 10, ysize => 10);
  $imrgb->setpixel(x => 0, 'y' => 0, color => '#FFF');
  $imrgb->setpixel(x => 1, 'y' => 0, color => '#FF0');
  $imrgb->setpixel(x => 2, 'y' => 0, color => '#000');
  my $mono = $imrgb->to_paletted(make_colors => 'mono',
				   translate => 'closest');
  is($mono->type, 'paletted', "check we get right image type");
  is($mono->colorcount, 2, "only 2 colors");
  my ($is_mono, $ziw) = $mono->is_bilevel;
  ok($is_mono, "check monochrome check true");
  is($ziw, 0, "check ziw false");
  my @colors = $mono->getcolors;
  iscolor($colors[0], $black, "check first entry");
  iscolor($colors[1], $white, "check second entry");
  my @pixels = $mono->getscanline(x => 0, 'y' => 0, width => 3, type=>'index');
  is($pixels[0], 1, "check white pixel");
  is($pixels[1], 1, "check yellow pixel");
  is($pixels[2], 0, "check black pixel");
}

{ # check for the various mono images we accept
  my $mono_8_bw_3 = Imager->new(xsize => 2, ysize => 2, channels => 3, 
			      type => 'paletted');
  ok($mono_8_bw_3->addcolors(colors => [ qw/000000 FFFFFF/ ]), 
     "mono8bw3 - add colors");
  ok($mono_8_bw_3->is_bilevel, "it's mono");
  is(($mono_8_bw_3->is_bilevel)[1], 0, 'zero not white');
  
  my $mono_8_wb_3 = Imager->new(xsize => 2, ysize => 2, channels => 3, 
			      type => 'paletted');
  ok($mono_8_wb_3->addcolors(colors => [ qw/FFFFFF 000000/ ]), 
     "mono8wb3 - add colors");
  ok($mono_8_wb_3->is_bilevel, "it's mono");
  is(($mono_8_wb_3->is_bilevel)[1], 1, 'zero is white');
  
  my $mono_8_bw_1 = Imager->new(xsize => 2, ysize => 2, channels => 1, 
			      type => 'paletted');
  ok($mono_8_bw_1->addcolors(colors => [ qw/000000 FFFFFF/ ]), 
     "mono8bw - add colors");
  ok($mono_8_bw_1->is_bilevel, "it's mono");
  is(($mono_8_bw_1->is_bilevel)[1], 0, 'zero not white');
  
  my $mono_8_wb_1 = Imager->new(xsize => 2, ysize => 2, channels => 1, 
			      type => 'paletted');
  ok($mono_8_wb_1->addcolors(colors => [ qw/FFFFFF 000000/ ]), 
     "mono8wb - add colors");
  ok($mono_8_wb_1->is_bilevel, "it's mono");
  is(($mono_8_wb_1->is_bilevel)[1], 1, 'zero is white');
}

{ # check bounds checking
  my $im = Imager->new(xsize => 10, ysize => 10, type=>'paletted');
  ok($im->addcolors(colors => [ $black ]), "add color of pixel bounds check writes");

  image_bounds_checks($im);
}

{ # test colors array returns colors
  my $data;
  my $im = test_image();
  my @colors;
  my $imp = $im->to_paletted(colors => \@colors, 
			     make_colors => 'webmap', 
			     translate => 'closest');
  ok($imp, "made paletted");
  is(@colors, 216, "should be 216 colors in the webmap");
  is_color3($colors[0], 0, 0, 0, "first should be 000000");
  is_color3($colors[1], 0, 0, 0x33, "second should be 000033");
  is_color3($colors[8], 0, 0x33, 0x66, "9th should be 003366");
}

{ # RT 68508
  my $im = Imager->new(xsize => 10, ysize => 10);
  $im->box(filled => 1, color => Imager::Color->new(255, 0, 0));
  my $palim = $im->to_paletted(make_colors => "mono", translate => "errdiff");
  ok($palim, "convert to mono with error diffusion");
  my $blank = Imager->new(xsize => 10, ysize => 10);
  isnt_image($palim, $blank, "make sure paletted isn't all black");
}

{ # check validation of palette entries
  my $im = Imager->new(xsize => 10, ysize => 10, type => 'paletted');
  $im->addcolors(colors => [ $black, $red ]);
  {
    my $no_croak = eval {
      $im->setscanline(y => 0, type => 'index', pixels => [ 0, 1 ]);
      1;
    };
    ok($no_croak, "valid values don't croak");
  }
  {
    my $no_croak = eval {
      $im->setscanline(y => 0, type => 'index', pixels => pack("C*", 0, 1));
      1;
    };
    ok($no_croak, "valid values don't croak (packed)");
  }
  {
    my $no_croak = eval {
      $im->setscanline(y => 0, type => 'index', pixels => [ 2, 255 ]);
      1;
    };
    ok(!$no_croak, "invalid values do croak");
  }
  {
    my $no_croak = eval {
      $im->setscanline(y => 0, type => 'index', pixels => pack("C*", 2, 255));
      1;
    };
    ok(!$no_croak, "invalid values do croak (packed)");
  }
}

{
  my $im = Imager->new(xsize => 1, ysize => 1);
  my $im_bad = Imager->new;
  {
    my @map = Imager->make_palette({});
    ok(!@map, "make_palette should fail with no images");
    is(Imager->errstr, "make_palette: supply at least one image",
       "check error message");
  }
  {
    my @map = Imager->make_palette({}, $im, $im_bad, $im);
    ok(!@map, "make_palette should fail with an empty image");
    is(Imager->errstr, "make_palette: image 2 is empty",
       "check error message");
  }
  {
    my @map = Imager->make_palette({ make_colors => "mono" }, $im);
    is(@map, 2, "mono should make 2 color palette")
      or skip("unexpected color count", 2);
    is_color4($map[0], 0, 0, 0, 255, "check map[0]");
    is_color4($map[1], 255, 255, 255, 255, "check map[1]");
  }
  {
    my @map = Imager->make_palette({ make_colors => "gray4" }, $im);
    is(@map, 4, "gray4 should make 4 color palette")
      or skip("unexpected color count", 4);
    is_color4($map[0], 0, 0, 0, 255, "check map[0]");
    is_color4($map[1], 85, 85, 85, 255, "check map[1]");
    is_color4($map[2], 170, 170, 170, 255, "check map[2]");
    is_color4($map[3], 255, 255, 255, 255, "check map[3]");
  }
  {
    my @map = Imager->make_palette({ make_colors => "gray16" }, $im);
    is(@map, 16, "gray16 should make 16 color palette")
      or skip("unexpected color count", 4);
    is_color4($map[0], 0, 0, 0, 255, "check map[0]");
    is_color4($map[1], 17, 17, 17, 255, "check map[1]");
    is_color4($map[2], 34, 34, 34, 255, "check map[2]");
    is_color4($map[15], 255, 255, 255, 255, "check map[15]");
  }
  {
    my @map = Imager->make_palette({ make_colors => "gray" }, $im);
    is(@map, 256, "gray16 should make 256 color palette")
      or skip("unexpected color count", 4);
    is_color4($map[0], 0, 0, 0, 255, "check map[0]");
    is_color4($map[1], 1, 1, 1, 255, "check map[1]");
    is_color4($map[33], 33, 33, 33, 255, "check map[2]");
    is_color4($map[255], 255, 255, 255, 255, "check map[15]");
  }
}

my $psamp_outside_error = "Image position outside of image";
{ # psamp
  print "# psamp\n";
  my $imraw = Imager::i_img_pal_new(10, 10, 3, 255);
  my @colors =
    (
     NC(0, 0, 0), NC(255, 128, 64), NC(64, 128, 192),
     NC(64, 0, 192), NC(255, 128, 0), NC(64, 32, 0),
     NC(128, 63, 32), NC(255, 128, 32), NC(64, 32, 16),
    );
  is(Imager::i_addcolors($imraw, @colors), "0 but true",
     "add colors needed for testing");
  {
    is(Imager::i_psamp($imraw, 0, 2, undef, [ 255, 128, 64 ]), 3,
       "i_psamp def channels, 3 samples");
    is_color3(Imager::i_get_pixel($imraw, 0, 2), 255, 128, 64,
	      "check color written");
    Imager::i_img_setmask($imraw, 5);
    is(Imager::i_psamp($imraw, 1, 3, undef, [ 64, 128, 192 ]), 3,
       "i_psamp def channels, 3 samples, masked");
    is_color3(Imager::i_get_pixel($imraw, 1, 3), 64, 0, 192,
	      "check color written");
    is(Imager::i_psamp($imraw, 1, 7, [ 0, 1, 2 ], [ 64, 128, 192 ]), 3,
       "i_psamp channels listed, 3 samples, masked");
    is_color3(Imager::i_get_pixel($imraw, 1, 7), 64, 0, 192,
	      "check color written");
    Imager::i_img_setmask($imraw, ~0);
    is(Imager::i_psamp($imraw, 2, 4, [ 0, 1 ], [ 255, 128, 64, 32 ]), 4,
       "i_psamp channels [0, 1], 4 samples");
    is_color3(Imager::i_get_pixel($imraw, 2, 4), 255, 128, 0,
	      "check first color written");
    is_color3(Imager::i_get_pixel($imraw, 3, 4), 64, 32, 0,
	      "check second color written");
    is(Imager::i_psamp($imraw, 0, 5, [ 0, 1, 2 ], [ (128, 63, 32) x 10 ]), 30,
       "write a full row");
    is_deeply([ Imager::i_gsamp($imraw, 0, 10, 5, [ 0, 1, 2 ]) ],
	      [ (128, 63, 32) x 10 ],
	      "check full row");
    is(Imager::i_psamp($imraw, 8, 8, [ 0, 1, 2 ],
		       [ 255, 128, 32, 64, 32, 16, 32, 16, 8 ]),
       6, "i_psamp channels [0, 1, 2], 9 samples, but room for 6");
  }
  { # errors we catch
    is(Imager::i_psamp($imraw, 6, 8, [ 0, 1, 3 ], [ 255, 128, 32 ]),
       undef, "i_psamp channels [0, 1, 3], 3 samples (invalid channel number)");
    is(_get_error(), "No channel 3 in this image",
       "check error message");
    is(Imager::i_psamp($imraw, 6, 8, [ 0, 1, -1 ], [ 255, 128, 32 ]),
       undef, "i_psamp channels [0, 1, -1], 3 samples (invalid channel number)");
    is(_get_error(), "No channel -1 in this image",
       "check error message");
    is(Imager::i_psamp($imraw, 0, -1, undef, [ 0, 0, 0 ]), undef,
       "negative y");
    is(_get_error(), $psamp_outside_error, "check message");
    is(Imager::i_psamp($imraw, 0, 10, undef, [ 0, 0, 0 ]), undef,
       "y overflow");
    is(_get_error(), $psamp_outside_error, "check message");
    is(Imager::i_psamp($imraw, -1, 0, undef, [ 0, 0, 0 ]), undef,
       "negative x");
    is(_get_error(), $psamp_outside_error, "check message");
    is(Imager::i_psamp($imraw, 10, 0, undef, [ 0, 0, 0 ]), undef,
       "x overflow");
    is(_get_error(), $psamp_outside_error, "check message");
  }
  ok(Imager::i_img_type($imraw), "still paletted");
  print "# end psamp tests\n";
}

{ # psampf
  print "# psampf\n";
  my $imraw = Imager::i_img_pal_new(10, 10, 3, 255);
  my @colors =
    (
     NC(0, 0, 0), NC(255, 128, 64), NC(64, 128, 192),
     NC(64, 0, 191), NC(255, 128, 0), NC(64, 32, 0),
     NC(128, 64, 32), NC(255, 128, 32), NC(64, 32, 16),
    );
  is(Imager::i_addcolors($imraw, @colors), "0 but true",
     "add colors needed for testing");
  {
    is(Imager::i_psampf($imraw, 0, 2, undef, [ 1, 0.5, 0.25 ]), 3,
       "i_psampf def channels, 3 samples");
    is_color3(Imager::i_get_pixel($imraw, 0, 2), 255, 128, 64,
	      "check color written");
    Imager::i_img_setmask($imraw, 5);
    is(Imager::i_psampf($imraw, 1, 3, undef, [ 0.25, 0.5, 0.75 ]), 3,
       "i_psampf def channels, 3 samples, masked");
    is_color3(Imager::i_get_pixel($imraw, 1, 3), 64, 0, 191,
	      "check color written");
    is(Imager::i_psampf($imraw, 1, 7, [ 0, 1, 2 ], [ 0.25, 0.5, 0.75 ]), 3,
       "i_psampf channels listed, 3 samples, masked");
    is_color3(Imager::i_get_pixel($imraw, 1, 7), 64, 0, 191,
	      "check color written");
    Imager::i_img_setmask($imraw, ~0);
    is(Imager::i_psampf($imraw, 2, 4, [ 0, 1 ], [ 1, 0.5, 0.25, 0.125 ]), 4,
       "i_psampf channels [0, 1], 4 samples");
    is_color3(Imager::i_get_pixel($imraw, 2, 4), 255, 128, 0,
	      "check first color written");
    is_color3(Imager::i_get_pixel($imraw, 3, 4), 64, 32, 0,
	      "check second color written");
    is(Imager::i_psampf($imraw, 0, 5, [ 0, 1, 2 ], [ (0.5, 0.25, 0.125) x 10 ]), 30,
       "write a full row");
    is_deeply([ Imager::i_gsamp($imraw, 0, 10, 5, [ 0, 1, 2 ]) ],
	      [ (128, 64, 32) x 10 ],
	      "check full row");
    is(Imager::i_psampf($imraw, 8, 8, [ 0, 1, 2 ],
			[ 1.0, 0.5, 0.125, 0.25, 0.125, 0.0625, 0.125, 0, 1 ]),
       6, "i_psampf channels [0, 1, 2], 9 samples, but room for 6");
  }
  { # errors we catch
    is(Imager::i_psampf($imraw, 6, 8, [ 0, 1, 3 ], [ 1, 0.5, 0.125 ]),
       undef, "i_psampf channels [0, 1, 3], 3 samples (invalid channel number)");
    is(_get_error(), "No channel 3 in this image",
       "check error message");
    is(Imager::i_psampf($imraw, 6, 8, [ 0, 1, -1 ], [ 1, 0.5, 0.125 ]),
       undef, "i_psampf channels [0, 1, -1], 3 samples (invalid channel number)");
    is(_get_error(), "No channel -1 in this image",
       "check error message");
    is(Imager::i_psampf($imraw, 0, -1, undef, [ 0, 0, 0 ]), undef,
       "negative y");
    is(_get_error(), $psamp_outside_error, "check message");
    is(Imager::i_psampf($imraw, 0, 10, undef, [ 0, 0, 0 ]), undef,
       "y overflow");
    is(_get_error(), $psamp_outside_error, "check message");
    is(Imager::i_psampf($imraw, -1, 0, undef, [ 0, 0, 0 ]), undef,
       "negative x");
    is(_get_error(), $psamp_outside_error, "check message");
    is(Imager::i_psampf($imraw, 10, 0, undef, [ 0, 0, 0 ]), undef,
       "x overflow");
    is(_get_error(), $psamp_outside_error, "check message");
  }
  ok(Imager::i_img_type($imraw), "still paletted");
  print "# end psampf tests\n";
}

{ # 75258 - gpixf() broken for paletted images
  my $im = Imager->new(xsize => 10, ysize => 10, type => "paletted");
  ok($im, "make a test image");
  my @colors = ( $black, $red, $green, $blue );
  is($im->addcolors(colors => \@colors), "0 but true",
     "add some colors");
  $im->setpixel(x => 0, y => 0, color => $red);
  $im->setpixel(x => 1, y => 0, color => $green);
  $im->setpixel(x => 2, y => 0, color => $blue);
  is_fcolor3($im->getpixel(x => 0, y => 0, type => "float"),
	     1.0, 0, 0, "get a pixel in float form, make sure it's red");
  is_fcolor3($im->getpixel(x => 1, y => 0, type => "float"),
	     0, 1.0, 0, "get a pixel in float form, make sure it's green");
  is_fcolor3($im->getpixel(x => 2, y => 0, type => "float"),
	     0, 0, 1.0, "get a pixel in float form, make sure it's blue");
}

{
  my $empty = Imager->new;
  ok(!$empty->to_paletted, "can't convert an empty image");
  is($empty->errstr, "to_paletted: empty input image",
    "check error message");

  is($empty->addcolors(colors => [ $black ]), -1,
     "can't addcolors() to an empty image");
  is($empty->errstr, "addcolors: empty input image",
     "check error message");

  ok(!$empty->setcolors(colors => [ $black ]),
     "can't setcolors() to an empty image");
  is($empty->errstr, "setcolors: empty input image",
     "check error message");

  ok(!$empty->getcolors(),
     "can't getcolors() from an empty image");
  is($empty->errstr, "getcolors: empty input image",
     "check error message");

  is($empty->colorcount, -1, "can't colorcount() an empty image");
  is($empty->errstr, "colorcount: empty input image",
     "check error message");

  is($empty->maxcolors, -1, "can't maxcolors() an empty image");
  is($empty->errstr, "maxcolors: empty input image",
     "check error message");

  is($empty->findcolor(color => $blue), undef,
     "can't findcolor an empty image");
  is($empty->errstr, "findcolor: empty input image",
     "check error message");
}

Imager->close_log;

unless ($ENV{IMAGER_KEEP_FILES}) {
  unlink "testout/t023palette.log"
}

sub iscolor {
  my ($c1, $c2, $msg) = @_;

  my $builder = Test::Builder->new;
  my @c1 = $c1->rgba;
  my @c2 = $c2->rgba;
  if (!$builder->ok($c1[0] == $c2[0] && $c1[1] == $c2[1] && $c1[2] == $c2[2],
                    $msg)) {
    $builder->diag(<<DIAG);
      got color: [ @c1 ]
 expected color: [ @c2 ]
DIAG
  }
}

sub isbin ($$$) {
  my ($got, $expected, $msg) = @_;

  my $builder = Test::Builder->new;
  if (!$builder->ok($got eq $expected, $msg)) {
    (my $got_dec = $got) =~ s/([^ -~])/sprintf("\\x%02x", ord $1)/ge;
    (my $exp_dec = $expected)  =~ s/([^ -~])/sprintf("\\x%02x", ord $1)/ge;
    $builder->diag(<<DIAG);
      got: "$got_dec"
 expected: "$exp_dec"
DIAG
  }
}

sub coloreq {
  my ($left, $right, $comment) = @_;

  my ($rl, $gl, $bl, $al) = $left->rgba;
  my ($rr, $gr, $br, $ar) = $right->rgba;

  print "# comparing color($rl,$gl,$bl,$al) with ($rr,$gr,$br,$ar)\n";
  ok($rl == $rr && $gl == $gr && $bl == $br && $al == $ar,
      $comment);
}

sub _get_error {
  my @errors = Imager::i_errors();
  return join(": ", map $_->[0], @errors);
}
