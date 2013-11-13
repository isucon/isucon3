#!perl -w
use strict;
use Test::More tests => 244;
use Imager qw(:all :handy);
use Imager::Test qw(is_color3 is_fcolor3);

-d "testout" or mkdir "testout";

Imager->open_log(log => "testout/t020masked.log");

my $base_rgb = Imager::ImgRaw::new(100, 100, 3);
# put something in there
my $black = NC(0, 0, 0);
my $red = NC(255, 0, 0);
my $green = NC(0, 255, 0);
my $blue = NC(0, 0, 255);
my $white = NC(255, 255, 255);
my $grey = NC(128, 128, 128);
use Imager::Color::Float;
my $redf = Imager::Color::Float->new(1, 0, 0);
my $greenf = Imager::Color::Float->new(0, 1, 0);
my $bluef = Imager::Color::Float->new(0, 0, 1);
my $greyf = Imager::Color::Float->new(0.5, 0.5, 0.5);
my @cols = ($red, $green, $blue);
for my $y (0..99) {
  Imager::i_plin($base_rgb, 0, $y, ($cols[$y % 3] ) x 100);
}

# first a simple subset image
my $s_rgb = Imager::i_img_masked_new($base_rgb, undef, 25, 25, 50, 50);

is(Imager::i_img_getchannels($s_rgb), 3,
   "1 channel image channel count match");
ok(Imager::i_img_getmask($s_rgb) & 1,
   "1 channel image mask");
ok(Imager::i_img_virtual($s_rgb),
   "1 channel image thinks it isn't virtual");
is(Imager::i_img_bits($s_rgb), 8,
   "1 channel image has bits == 8");
is(Imager::i_img_type($s_rgb), 0, # direct
   "1 channel image is direct");

my @ginfo = i_img_info($s_rgb);
is($ginfo[0], 50, "check width");
is($ginfo[1], 50, "check height");

# sample some pixels through the subset
my $c = Imager::i_get_pixel($s_rgb, 0, 0);
is_color3($c, 0, 255, 0, "check (0,0)");
$c = Imager::i_get_pixel($s_rgb, 49, 49);
# (25+49)%3 = 2
is_color3($c, 0, 0, 255, "check (49,49)");

# try writing to it
for my $y (0..49) {
  Imager::i_plin($s_rgb, 0, $y, ($cols[$y % 3]) x 50);
}
pass("managed to write to it");
# and checking the target image
$c = Imager::i_get_pixel($base_rgb, 25, 25);
is_color3($c, 255, 0, 0, "check (25,25)");
$c = Imager::i_get_pixel($base_rgb, 29, 29);
is_color3($c, 0, 255, 0, "check (29,29)");

undef $s_rgb;

# a basic background
for my $y (0..99) {
  Imager::i_plin($base_rgb, 0, $y, ($red ) x 100);
}
my $mask = Imager::ImgRaw::new(50, 50, 1);
# some venetian blinds
for my $y (4..20) {
  Imager::i_plin($mask, 5, $y*2, ($white) x 40);
}
# with a strip down the middle
for my $y (0..49) {
  Imager::i_plin($mask, 20, $y, ($white) x 8);
}
my $m_rgb = Imager::i_img_masked_new($base_rgb, $mask, 25, 25, 50, 50);
ok($m_rgb, "make masked with mask");
for my $y (0..49) {
  Imager::i_plin($m_rgb, 0, $y, ($green) x 50);
}
my @color_tests =
  (
   [ 25+0,  25+0,  $red ],
   [ 25+19, 25+0,  $red ],
   [ 25+20, 25+0,  $green ],
   [ 25+27, 25+0,  $green ],
   [ 25+28, 25+0,  $red ],
   [ 25+49, 25+0,  $red ],
   [ 25+19, 25+7,  $red ],
   [ 25+19, 25+8,  $green ],
   [ 25+19, 25+9,  $red ],
   [ 25+0,  25+8,  $red ],
   [ 25+4,  25+8,  $red ],
   [ 25+5,  25+8,  $green ],
   [ 25+44, 25+8,  $green ],
   [ 25+45, 25+8,  $red ],
   [ 25+49, 25+49, $red ],
  );
my $test_num = 15;
for my $test (@color_tests) {
  my ($x, $y, $testc) = @$test;
  my ($r, $g, $b) = $testc->rgba;
  my $c = Imager::i_get_pixel($base_rgb, $x, $y);
  is_color3($c, $r, $g, $b, "at ($x, $y)");
}

{
  # tests for the OO versions, fairly simple, since the basic functionality
  # is covered by the low-level interface tests
   
  my $base = Imager->new(xsize=>100, ysize=>100);
  ok($base, "make base OO image");
  $base->box(color=>$blue, filled=>1); # fill it all
  my $mask = Imager->new(xsize=>80, ysize=>80, channels=>1);
  $mask->box(color=>$white, filled=>1, xmin=>5, xmax=>75, ymin=>5, ymax=>75);
  my $m_img = $base->masked(mask=>$mask, left=>5, top=>5);
  ok($m_img, "make masked OO image");
  is($m_img->getwidth, 80, "check width");
  $m_img->box(color=>$green, filled=>1);
  my $c = $m_img->getpixel(x=>0, y=>0);
  is_color3($c, 0, 0, 255, "check (0,0)");
  $c = $m_img->getpixel(x => 5, y => 5);
  is_color3($c, 0, 255, 0, "check (5,5)");

  # older versions destroyed the Imager::ImgRaw object manually in 
  # Imager::DESTROY rather than letting Imager::ImgRaw::DESTROY 
  # destroy the object
  # so we test here by destroying the base and mask objects and trying 
  # to draw to the masked wrapper
  # you may need to test with ElectricFence to trigger the problem
  undef $mask;
  undef $base;
  $m_img->box(color=>$blue, filled=>1);
  pass("didn't crash unreffing base or mask for masked image");
}

# 35.7% cover on maskimg.c up to here

{ # error handling:
  my $base = Imager->new(xsize => 100, ysize => 100);
  ok($base, "make base");
  { #  make masked image subset outside of the base image
    my $masked = $base->masked(left => 100);
    ok (!$masked, "fail to make empty masked");
    is($base->errstr, "subset outside of target image", "check message");
  }
}

{ # size limiting
  my $base = Imager->new(xsize => 10, ysize => 10);
  ok($base, "make base for size limit tests");
  {
    my $masked = $base->masked(left => 5, right => 15);
    ok($masked, "make masked");
    is($masked->getwidth, 5, "check width truncated");
  }
  {
    my $masked = $base->masked(top => 5, bottom => 15);
    ok($masked, "make masked");
    is($masked->getheight, 5, "check height truncated");
  }
}
# 36.7% up to here

$mask = Imager->new(xsize => 80, ysize => 80, channels => 1);
$mask->box(filled => 1, color => $white, xmax => 39, ymax => 39);
$mask->box(fill => { hatch => "check1x1" }, ymin => 40, xmax => 39);

{
  my $base = Imager->new(xsize => 100, ysize => 100, bits => "double");
  ok($base, "base for single pixel tests");
  is($base->type, "direct", "check type");
  my $masked = $base->masked(mask => $mask, left => 1, top => 2);
  my $limited = $base->masked(left => 1, top => 2);

  is($masked->type, "direct", "check masked is same type as base");
  is($limited->type, "direct", "check limited is same type as base");

  {
    # single pixel writes, masked
    {
      ok($masked->setpixel(x => 1, y => 3, color => $green),
	 "set (1,3) in masked (2, 5) in based");
      my $c = $base->getpixel(x => 2, y => 5);
      is_color3($c, 0, 255, 0, "check it wrote through");
      ok($masked->setpixel(x => 45, y => 2, color => $red),
	 "set (45,2) in masked (46,4) in base (no mask)");
    $c = $base->getpixel(x => 46, y => 4);
      is_color3($c, 0, 0, 0, "shouldn't have written through");
    }
    {
      ok($masked->setpixel(x => 2, y => 3, color => $redf),
	 "write float red to (2,3) base(3,5)");
      my $c = $base->getpixel(x => 3, y => 5);
      is_color3($c, 255, 0, 0, "check it wrote through");
      ok($masked->setpixel(x => 45, y => 3, color => $greenf),
	 "set float (45,3) in masked (46,5) in base (no mask)");
      $c = $base->getpixel(x => 46, y => 5);
      is_color3($c, 0, 0, 0, "check it didn't write");
    }
    {
      # write out of range should fail
      ok(!$masked->setpixel(x => 80, y => 0, color => $green),
	 "write 8-bit color out of range");
      ok(!$masked->setpixel(x => 0, y => 80, color => $greenf),
	 "write float color out of range");
    }
  }

  # 46.9

  {
    print "# plin coverage\n";
    {
      $base->box(filled => 1, color => $black);
      # plin masked
      # simple path
      is($masked->setscanline(x => 76, y => 1, pixels => [ ($red, $green) x 3 ]),
	 4, "try to write 6 pixels, but only write 4");
      is_deeply([ $base->getsamples(x => 77, y => 3, width => 4) ],
		[ ( 0 ) x 12 ],
		"check not written through");
      # !simple path
      is($masked->setscanline(x => 4, y => 2, pixels => [ ($red, $green, $blue, $grey) x (72/4) ]),
	 72, "write many pixels (masked)");
      is_deeply([ $base->getsamples(x => 5, y => 4, width => 72) ],
		[ ( (255, 0, 0), (0, 255, 0), (0, 0, 255), (128, 128, 128)) x 9,
		  ( 0, 0, 0 ) x 36 ],
		"check written through to base");
      
      # simple path, due to number of transitions
      is($masked->setscanline(x => 0, y => 40, pixels => [ ($red, $green, $blue, $grey) x 5 ]),
	 20, "try to write 20 pixels, with alternating write through");
      is_deeply([ $base->getsamples(x => 1, y => 42, width => 20) ],
		[ ( (0, 0, 0), (0,255,0), (0,0,0), (128,128,128) ) x 5 ],
		"check correct pixels written through");
    }
    
    {
      $base->box(filled => 1, color => $black);
      # plin, non-masked path
      is($limited->setscanline(x => 4, y => 2, pixels => [ ($red, $green, $blue, $grey) x (72/4) ]),
	 72, "write many pixels (limited)");
      is_deeply([ $base->getsamples(x => 5, y => 4, width => 72) ],
		[ ( (255, 0, 0), (0, 255, 0), (0, 0, 255), (128, 128, 128)) x 18 ],
		"check written through to based");
    }
    
    {
      # draw outside fails
      is($masked->setscanline(x => 80, y => 2, pixels => [ $red, $green ]),
	 0, "check writing no pixels");
    }
  }

  {
    print "# plinf coverage\n";
    {
      $base->box(filled => 1, color => $black);
      # plinf masked
      # simple path
      is($masked->setscanline(x => 76, y => 1, pixels => [ ($redf, $greenf) x 3 ]),
	 4, "try to write 6 pixels, but only write 4");
      is_deeply([ $base->getsamples(x => 77, y => 3, width => 4, type => "float") ],
		[ ( 0 ) x 12 ],
		"check not written through");
      # !simple path
      is($masked->setscanline(x => 4, y => 2, pixels => [ ($redf, $greenf, $bluef, $greyf) x (72/4) ]),
	 72, "write many pixels (masked)");
      is_deeply([ $base->getsamples(x => 5, y => 4, width => 72, type => "float") ],
		[ ( (1, 0, 0), (0, 1, 0), (0, 0, 1), (0.5, 0.5, 0.5)) x 9,
		  ( 0, 0, 0 ) x 36 ],
		"check written through to base");
      
      # simple path, due to number of transitions
      is($masked->setscanline(x => 0, y => 40, pixels => [ ($redf, $greenf, $bluef, $greyf) x 5 ]),
	 20, "try to write 20 pixels, with alternating write through");
      is_deeply([ $base->getsamples(x => 1, y => 42, width => 20, type => "float") ],
		[ ( (0, 0, 0), (0,1,0), (0,0,0), (0.5,0.5,0.5) ) x 5 ],
		"check correct pixels written through");
    }
    
    {
      $base->box(filled => 1, color => $black);
      # plinf, non-masked path
      is($limited->setscanline(x => 4, y => 2, pixels => [ ($redf, $greenf, $bluef, $greyf) x (72/4) ]),
	 72, "write many pixels (limited)");
      is_deeply([ $base->getsamples(x => 5, y => 4, width => 72, type => "float") ],
		[ ( (1, 0, 0), (0, 1, 0), (0, 0, 1), (0.5, 0.5, 0.5)) x 18 ],
		"check written through to based");
    }
    
    {
      # draw outside fails
      is($masked->setscanline(x => 80, y => 2, pixels => [ $redf, $greenf ]),
	 0, "check writing no pixels");
    }
  }
  # 71.4%
  {
    {
      print "# gpix\n";
      # gpix
      $base->box(filled => 1, color => $black);
      ok($base->setpixel(x => 4, y => 10, color => $red),
	 "set base(4,10) to red");
      is_fcolor3($masked->getpixel(x => 3, y => 8),
		 255, 0, 0, "check pixel written");

      # out of range
      is($masked->getpixel(x => -1, y => 1),
	 undef, "check failure to left");
      is($masked->getpixel(x => 0, y => -1),
	 undef, "check failure to top");
      is($masked->getpixel(x => 80, y => 1),
	 undef, "check failure to right");
      is($masked->getpixel(x => 0, y => 80),
	 undef, "check failure to bottom");
    }
    {
      print "# gpixf\n";
      # gpixf
      $base->box(filled => 1, color => $black);
      ok($base->setpixel(x => 4, y => 10, color => $redf),
	 "set base(4,10) to red");
      is_fcolor3($masked->getpixel(x => 3, y => 8, type => "float"),
		 1.0, 0, 0, 0, "check pixel written");

      # out of range
      is($masked->getpixel(x => -1, y => 1, type => "float"),
	 undef, "check failure to left");
      is($masked->getpixel(x => 0, y => -1, type => "float"),
	 undef, "check failure to top");
      is($masked->getpixel(x => 80, y => 1, type => "float"),
	 undef, "check failure to right");
      is($masked->getpixel(x => 0, y => 80, type => "float"),
	 undef, "check failure to bottom");
    }
  }
  # 74.5
  {
    {
      print "# glin\n";
      $base->box(filled => 1, color => $black);
      is($base->setscanline(x => 31, y => 3, 
			    pixels => [ ( $red, $green) x 10 ]),
	 20, "write 20 pixels to base image");
      my @colors = $masked->
	getscanline(x => 30, y => 1, width => 20);
      is(@colors, 20, "check we got right number of colors");
      is_color3($colors[0], 255, 0, 0, "check first pixel");
      is_color3($colors[19], 0, 255, 0, "check last pixel");

      @colors = $masked->getscanline(x => 76, y => 2, width => 10);
      is(@colors, 4, "read line from right edge");
      is_color3($colors[0], 0, 0, 0, "check pixel");

      is_deeply([ $masked->getscanline(x => -1, y => 0, width => 1) ],
	 [], "fail read left of image");
      is_deeply([ $masked->getscanline(x => 0, y => -1, width => 1) ],
	 [], "fail read top of image");
      is_deeply([$masked->getscanline(x => 80, y => 0, width => 1)],
	 [], "fail read right of image");
      is_deeply([$masked->getscanline(x => 0, y => 80, width => 1)],
	 [], "fail read bottom of image");
    }
    {
      print "# glinf\n";
      $base->box(filled => 1, color => $black);
      is($base->setscanline(x => 31, y => 3, 
			    pixels => [ ( $redf, $greenf) x 10 ]),
	 20, "write 20 pixels to base image");
      my @colors = $masked->
	getscanline(x => 30, y => 1, width => 20, type => "float");
      is(@colors, 20, "check we got right number of colors");
      is_fcolor3($colors[0], 1.0, 0, 0, 0, "check first pixel");
      is_fcolor3($colors[19], 0, 1.0, 0, 0, "check last pixel");

      @colors = $masked->
	getscanline(x => 76, y => 2, width => 10, type => "float");
      is(@colors, 4, "read line from right edge");
      is_fcolor3($colors[0], 0, 0, 0, 0, "check pixel");

      is_deeply([ $masked->getscanline(x => -1, y => 0, width => 1, type => "float") ],
	 [], "fail read left of image");
      is_deeply([ $masked->getscanline(x => 0, y => -1, width => 1, type => "float") ],
	 [], "fail read top of image");
      is_deeply([$masked->getscanline(x => 80, y => 0, width => 1, type => "float")],
	 [], "fail read right of image");
      is_deeply([$masked->getscanline(x => 0, y => 80, width => 1, type => "float")],
	 [], "fail read bottom of image");
    }
  }
  # 81.6%
  {
    {
      print "# gsamp\n";
      $base->box(filled => 1, color => $black);
      is($base->setscanline(x => 31, y => 3, 
			    pixels => [ ( $red, $green) x 10 ]),
	 20, "write 20 pixels to base image");
      my @samps = $masked->
	getsamples(x => 30, y => 1, width => 20);
      is(@samps, 60, "check we got right number of samples");
      is_deeply(\@samps,
		[ (255, 0, 0, 0, 255, 0) x 10 ],
		"check it");

      @samps = $masked->
	getsamples(x => 76, y => 2, width => 10);
      is(@samps, 12, "read line from right edge");
      is_deeply(\@samps, [ (0, 0, 0) x 4], "check result");

      is_deeply([ $masked->getsamples(x => -1, y => 0, width => 1) ],
	 [], "fail read left of image");
      is_deeply([ $masked->getsamples(x => 0, y => -1, width => 1) ],
	 [], "fail read top of image");
      is_deeply([$masked->getsamples(x => 80, y => 0, width => 1)],
	 [], "fail read right of image");
      is_deeply([$masked->getsamples(x => 0, y => 80, width => 1)],
	 [], "fail read bottom of image");
    }
    {
      print "# gsampf\n";
      $base->box(filled => 1, color => $black);
      is($base->setscanline(x => 31, y => 3, 
			    pixels => [ ( $redf, $greenf) x 10 ]),
	 20, "write 20 pixels to base image");
      my @samps = $masked->
	getsamples(x => 30, y => 1, width => 20, type => "float");
      is(@samps, 60, "check we got right number of samples");
      is_deeply(\@samps,
		[ (1.0, 0, 0, 0, 1.0, 0) x 10 ],
		"check it");

      @samps = $masked->
	getsamples(x => 76, y => 2, width => 10, type => "float");
      is(@samps, 12, "read line from right edge");
      is_deeply(\@samps, [ (0, 0, 0) x 4], "check result");

      is_deeply([ $masked->getsamples(x => -1, y => 0, width => 1, type => "float") ],
	 [], "fail read left of image");
      is_deeply([ $masked->getsamples(x => 0, y => -1, width => 1, type => "float") ],
	 [], "fail read top of image");
      is_deeply([$masked->getsamples(x => 80, y => 0, width => 1, type => "float")],
	 [], "fail read right of image");
      is_deeply([$masked->getsamples(x => 0, y => 80, width => 1, type => "float")],
	 [], "fail read bottom of image");
    }
  }
  # 86.2%
}

{
  my $base = Imager->new(xsize => 100, ysize => 100, type => "paletted");
  ok($base, "make paletted base");
  is($base->type, "paletted", "check we got paletted");
  is($base->addcolors(colors => [ $black, $red, $green, $blue ]),
     "0 but true",
     "add some colors to base");
  my $masked = $base->masked(mask => $mask, left => 1, top => 2);
  my $limited = $base->masked(left => 1, top => 2);

  is($masked->type, "paletted", "check masked is same type as base");
  is($limited->type, "paletted", "check limited is same type as base");

  {
    # make sure addcolors forwarded
    is($masked->addcolors(colors => [ $grey ]), 4,
       "test addcolors forwarded");
    my @colors = $masked->getcolors();
    is(@colors, 5, "check getcolors forwarded");
    is_color3($colors[1], 255, 0, 0, "check color from palette");
  }

  my ($blacki, $redi, $greeni, $bluei, $greyi) = 0 .. 4;

  { # gpal
    print "# gpal\n";
    $base->box(filled => 1, color => $black);
    is($base->setscanline(x => 0, y => 5, type => "index",
			  pixels => [ ( $redi, $greeni, $bluei, $greyi) x 25 ]),
       100, "write some pixels to base");
    my @indexes = $masked->getscanline(y => 3, type => "index", width => "81");
    is(@indexes, 80, "got 80 indexes");
    is_deeply(\@indexes,
	      [ ( $greeni, $bluei, $greyi, $redi) x 20 ],
	      "check values");

    is_deeply([ $masked->getscanline(x => -1, y => 3, type => "index") ],
	      [], "fail read left of image");
  }
  # 89.8%

  { # ppal, unmasked
    print "# ppal\n";
    $base->box(filled => 1, color => $black);
    is($limited->setscanline(x => 1, y => 1, type => "index",
			     pixels => [ ( $redi, $greeni, $bluei) x 3 ]),
       9, "ppal limited");
    is_deeply([ $base->getscanline(x => 2, y => 3, type => "index", 
				   width => 9) ],
	      [ ( $redi, $greeni, $bluei) x 3 ],
	      "check set in base");
  }
  { # ppal, masked
    $base->box(filled => 1, color => $black);
    is($masked->setscanline(x => 1, y => 2, type => "index",
			    pixels => [ ( $redi, $greeni, $bluei, $greyi) x 12 ]),
       48, "ppal masked");
    is_deeply([ $base->getscanline(x => 0, y => 4, type => "index") ],
	      [ 0, 0,
		( $redi, $greeni, $bluei, $greyi ) x 9,
		$redi, $greeni, $bluei, ( 0 ) x 59 ],
	      "check written");
  }
  {
    # ppal, errors
    is($masked->setscanline(x => -1, y => 0, type => "index",
			    pixels => [ $redi, $bluei ]),
       0, "fail to write ppal");

    is($masked->setscanline(x => 78, y => 0, type => "index",
			   pixels => [ $redi, $bluei, $greeni, $greyi ]),
       2, "write over right side");
  }
}

my $full_mask = Imager->new(xsize => 10, ysize => 10, channels => 1);
$full_mask->box(filled => 1, color => NC(255, 0, 0));

# no mask and mask with full coverage should behave the same
my $psamp_outside_error = "Image position outside of image";
for my $masked (0, 1){ # psamp
  print "# psamp masked: $masked\n";
  my $imback = Imager::ImgRaw::new(20, 20, 3);
  my $mask;
  if ($masked) {
    $mask = $full_mask->{IMG};
  }
  my $imraw = Imager::i_img_masked_new($imback, $mask, 3, 4, 10, 10);
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
    is(_get_error(), $psamp_outside_error, "check error message");
    is(Imager::i_psamp($imraw, 0, 10, undef, [ 0, 0, 0 ]), undef,
       "y overflow");
    is(_get_error(), $psamp_outside_error, "check error message");
    is(Imager::i_psamp($imraw, -1, 0, undef, [ 0, 0, 0 ]), undef,
       "negative x");
    is(_get_error(), $psamp_outside_error, "check error message");
    is(Imager::i_psamp($imraw, 10, 0, undef, [ 0, 0, 0 ]), undef,
       "x overflow");
    is(_get_error(), $psamp_outside_error, "check error message");
  }
  print "# end psamp tests\n";
}

for my $masked (0, 1) { # psampf
  print "# psampf\n";
  my $imback = Imager::ImgRaw::new(20, 20, 3);
  my $mask;
  if ($masked) {
    $mask = $full_mask->{IMG};
  }
  my $imraw = Imager::i_img_masked_new($imback, $mask, 3, 4, 10, 10);
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
    is(_get_error(), $psamp_outside_error, "check error message");
    is(Imager::i_psampf($imraw, 0, 10, undef, [ 0, 0, 0 ]), undef,
       "y overflow");
    is(_get_error(), $psamp_outside_error, "check error message");
    is(Imager::i_psampf($imraw, -1, 0, undef, [ 0, 0, 0 ]), undef,
       "negative x");
    is(_get_error(), $psamp_outside_error, "check error message");
    is(Imager::i_psampf($imraw, 10, 0, undef, [ 0, 0, 0 ]), undef,
       "x overflow");
    is(_get_error(), $psamp_outside_error, "check error message");
  }
  print "# end psampf tests\n";
}

{
  my $sub_mask = $full_mask->copy;
  $sub_mask->box(filled => 1, color => NC(0,0,0), xmin => 4, xmax => 6);
  my $base = Imager::ImgRaw::new(20, 20, 3);
  my $masked = Imager::i_img_masked_new($base, $sub_mask->{IMG}, 3, 4, 10, 10);

  is(Imager::i_psamp($masked, 0, 2, undef, [ ( 0, 127, 255) x 10 ]), 30,
     "psamp() to masked image");
  is_deeply([ Imager::i_gsamp($base, 0, 20, 6, undef) ],
	    [ ( 0, 0, 0 ) x 3, # left of mask
	      ( 0, 127, 255 ) x 4, # masked area
	      ( 0, 0, 0 ) x 3, # unmasked area
	      ( 0, 127, 255 ) x 3, # masked area
	      ( 0, 0, 0 ) x 7 ], # right of mask
	    "check values written");
  is(Imager::i_psampf($masked, 0, 2, undef, [ ( 0, 0.5, 1.0) x 10 ]), 30,
     "psampf() to masked image");
  is_deeply([ Imager::i_gsamp($base, 0, 20, 6, undef) ],
	    [ ( 0, 0, 0 ) x 3, # left of mask
	      ( 0, 128, 255 ) x 4, # masked area
	      ( 0, 0, 0 ) x 3, # unmasked area
	      ( 0, 128, 255 ) x 3, # masked area
	      ( 0, 0, 0 ) x 7 ], # right of mask
	    "check values written");
}

{
  my $empty = Imager->new;
  ok(!$empty->masked, "fail to make a masked image from an empty");
  is($empty->errstr, "masked: empty input image",
    "check error message");
}

Imager->close_log();

unless ($ENV{IMAGER_KEEP_FILES}) {
  unlink "testout/t020masked.log";
}

sub _get_error {
  my @errors = Imager::i_errors();
  return join(": ", map $_->[0], @errors);
}
