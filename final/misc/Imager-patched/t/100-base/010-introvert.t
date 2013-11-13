#!perl -w
# t/t01introvert.t - tests internals of image formats
# to make sure we get expected values

use strict;
use Test::More tests => 466;

BEGIN { use_ok(Imager => qw(:handy :all)) }

use Imager::Test qw(image_bounds_checks is_color3 is_color4 is_fcolor4 color_cmp mask_tests is_fcolor3);

-d "testout" or mkdir "testout";

Imager->open_log(log => "testout/t01introvert.log");

my $im_g = Imager::ImgRaw::new(100, 101, 1);

my $red = NC(255, 0, 0);
my $green = NC(0, 255, 0);
my $blue = NC(0, 0, 255);

use Imager::Color::Float;
my $f_black = Imager::Color::Float->new(0, 0, 0);
my $f_red = Imager::Color::Float->new(1.0, 0, 0);
my $f_green = Imager::Color::Float->new(0, 1.0, 0);
my $f_blue = Imager::Color::Float->new(0, 0, 1.0);

is(Imager::i_img_getchannels($im_g), 1, "1 channel image channel count");
ok(Imager::i_img_getmask($im_g) & 1, "1 channel image mask");
ok(!Imager::i_img_virtual($im_g), "1 channel image not virtual");
is(Imager::i_img_bits($im_g), 8, "1 channel image has 8 bits/sample");
is(Imager::i_img_type($im_g), 0, "1 channel image is direct");
is(Imager::i_img_get_width($im_g), 100, "100 pixels wide");
is(Imager::i_img_get_height($im_g), 101, "101 pixels high");

my @ginfo = Imager::i_img_info($im_g);
is($ginfo[0], 100, "1 channel image width");
is($ginfo[1], 101, "1 channel image height");

undef $im_g; # can we check for release after this somehow?

my $im_rgb = Imager::ImgRaw::new(100, 101, 3);

is(Imager::i_img_getchannels($im_rgb), 3, "3 channel image channel count");
is((Imager::i_img_getmask($im_rgb) & 7), 7, "3 channel image mask");
is(Imager::i_img_bits($im_rgb), 8, "3 channel image has 8 bits/sample");
is(Imager::i_img_type($im_rgb), 0, "3 channel image is direct");

undef $im_rgb;

my $im_pal = Imager::i_img_pal_new(100, 101, 3, 256);

ok($im_pal, "make paletted image");
is(Imager::i_img_getchannels($im_pal), 3, "pal img channel count");
is(Imager::i_img_bits($im_pal), 8, "pal img bits");
is(Imager::i_img_type($im_pal), 1, "pal img is paletted");

my $red_idx = check_add($im_pal, $red, 0);
my $green_idx = check_add($im_pal, $green, 1);
my $blue_idx = check_add($im_pal, $blue, 2);

# basic writing of palette indicies
# fill with red
is(Imager::i_ppal($im_pal, 0, 0, ($red_idx) x 100), 100, 
   "write red 100 times");
# and blue
is(Imager::i_ppal($im_pal, 50, 0, ($blue_idx) x 50), 50,
   "write blue 50 times");

# make sure we get it back
my @pals = Imager::i_gpal($im_pal, 0, 100, 0);
ok(!grep($_ != $red_idx, @pals[0..49]), "check for red");
ok(!grep($_ != $blue_idx, @pals[50..99]), "check for blue");
is(Imager::i_gpal($im_pal, 0, 100, 0), "\0" x 50 . "\2" x 50, 
   "gpal in scalar context");
my @samp = Imager::i_gsamp($im_pal, 0, 100, 0, [ 0, 1, 2 ]);
is(@samp, 300, "gsamp count in list context");
my @samp_exp = ((255, 0, 0) x 50, (0, 0, 255) x 50);
is_deeply(\@samp, \@samp_exp, "gsamp list deep compare");
my $samp = Imager::i_gsamp($im_pal, 0, 100, 0, [ 0, 1, 2 ]);
is(length($samp), 300, "gsamp scalar length");
is($samp, "\xFF\0\0" x 50 . "\0\0\xFF" x 50, "gsamp scalar bytes");

# reading indicies as colors
my $c_red = Imager::i_get_pixel($im_pal, 0, 0);
ok($c_red, "got the red pixel");
is_color3($c_red, 255, 0, 0, "and it's red");
my $c_blue = Imager::i_get_pixel($im_pal, 50, 0);
ok($c_blue, "got the blue pixel");
is_color3($c_blue, 0, 0, 255, "and it's blue");

# drawing with colors
ok(Imager::i_ppix($im_pal, 0, 0, $green) == 0, "draw with color in palette");
# that was in the palette, should still be paletted
is(Imager::i_img_type($im_pal), 1, "image still paletted");

my $c_green = Imager::i_get_pixel($im_pal, 0, 0);
ok($c_green, "got green pixel");
is_color3($c_green, 0, 255, 0, "and it's green");

is(Imager::i_colorcount($im_pal), 3, "still 3 colors in palette");
is(Imager::i_findcolor($im_pal, $green), 1, "and green is the second");

my $black = NC(0, 0, 0);
# this should convert the image to RGB
ok(Imager::i_ppix($im_pal, 1, 0, $black) == 0, "draw with black (not in palette)");
is(Imager::i_img_type($im_pal), 0, "pal img shouldn't be paletted now");

{
  my %quant =
    (
     colors => [$red, $green, $blue, $black],
     make_colors => 'none',
    );
  my $im_pal2 = Imager::i_img_to_pal($im_pal, \%quant);
  ok($im_pal2, "got an image from quantizing");
  is(@{$quant{colors}}, 4, "quant has the right number of colours");
  is(Imager::i_colorcount($im_pal2), 4, "and so does the image");
  my @colors = Imager::i_getcolors($im_pal2, 0, 4);
  my ($first) = Imager::i_getcolors($im_pal2, 0);
  my @first = $colors[0]->rgba;
  is_color3($first, $first[0], $first[1], $first[2],
	   "check first color is first for multiple or single fetch");
  is_color3($colors[0], 255, 0, 0, "still red");
  is_color3($colors[1], 0, 255, 0, "still green");
  is_color3($colors[2], 0, 0, 255, "still blue");
  is_color3($colors[3], 0, 0, 0, "still black");
  my @samples = Imager::i_gsamp($im_pal2, 0, 100, 0, [ 0, 1, 2 ]);
  my @expect = unpack("C*", "\0\xFF\0\0\0\0"."\xFF\0\0" x 48 . "\0\0\xFF" x 50);
  my $match_list = is_deeply(\@samples, \@expect, "colors are still correct");
  my $samples = Imager::i_gsamp($im_pal2, 0, 100, 0, [ 0, 1, 2 ]);
  my $match_scalar = is_deeply([ unpack("C*", $samples) ],
			       \@expect, "colors are still correct (scalar)");
  unless ($match_list && $match_scalar) {
    # this has been failing on a particular smoker, provide more
    # diagnostic information
    print STDERR "Pallete:\n";
    print STDERR "  $_: ", join(",", $colors[$_]->rgba), "\n" for 0..$#colors;
    print STDERR "Samples (list): ", join(",", @samples), "\n";
    print STDERR "Samples (scalar): ", join(",", unpack("C*", $samples)), "\n";
    print STDERR "Indexes: ", join(",", Imager::i_gpal($im_pal2, 0, 100, 0)), "\n";
  }
}

# test the OO interfaces
my $impal2 = Imager->new(type=>'pseudo', xsize=>200, ysize=>201);
ok($impal2, "make paletted via OO")
  or diag(Imager->errstr);
is($impal2->getchannels, 3, "check channels");
is($impal2->bits, 8, "check bits");
is($impal2->type, 'paletted', "check type");
is($impal2->getwidth, 200, "check width");
is($impal2->getheight, 201, "check height");

{
  my $red_idx = $impal2->addcolors(colors=>[$red]);
  ok($red_idx, "add red to OO");
  is(0+$red_idx, 0, "and it's expected index for red");
  my $blue_idx = $impal2->addcolors(colors=>[$blue, $green]);
  ok($blue_idx, "add blue/green via OO");
  is($blue_idx, 1, "and it's expected index for blue");
  my $green_idx = $blue_idx + 1;
  my $c = $impal2->getcolors(start=>$green_idx);
  is_color3($c, 0, 255, 0, "found green where expected");
  my @cols = $impal2->getcolors;
  is(@cols, 3, "got 3 colors");
  my @exp = ( $red, $blue, $green );
  my $good = 1;
  for my $i (0..2) {
    if (color_cmp($cols[$i], $exp[$i])) {
      $good = 0;
      last;
    }
  }
  ok($good, "all colors in palette as expected");
  is($impal2->colorcount, 3, "and colorcount returns 3");
  is($impal2->maxcolors, 256, "maxcolors as expected");
  is($impal2->findcolor(color=>$blue), 1, "findcolors found blue");
  ok($impal2->setcolors(start=>0, colors=>[ $blue, $red ]),
     "we can setcolors");

  # make an rgb version
  my $imrgb2 = $impal2->to_rgb8()
    or diag($impal2->errstr);
  is($imrgb2->type, 'direct', "converted is direct");

  # and back again, specifying the palette
  my @colors = ( $red, $blue, $green );
  my $impal3 = $imrgb2->to_paletted(colors=>\@colors,
                                    make_colors=>'none',
                                    translate=>'closest');
  ok($impal3, "got a paletted image from conversion");
  dump_colors(@colors);
  print "# in image\n";
  dump_colors($impal3->getcolors);
  is($impal3->colorcount, 3, "new image has expected color table size");
  is($impal3->type, 'paletted', "and is paletted");
}

{
  my $im = Imager->new;
  ok($im, "make empty image");
  ok(!$im->to_rgb8, "convert to rgb8");
  is($im->errstr, "to_rgb8: empty input image", "check message");
  is($im->bits, undef, "can't call bits on an empty image");
  is($im->errstr, "bits: empty input image", "check message");
  is($im->type, undef, "can't call type on an empty image");
  is($im->errstr, "type: empty input image", "check message");
  is($im->virtual, undef, "can't call virtual on an empty image");
  is($im->errstr, "virtual: empty input image", "check message");
  is($im->is_bilevel, undef, "can't call virtual on an empty image");
  is($im->errstr, "is_bilevel: empty input image", "check message");
  ok(!$im->getscanline(y => 0), "can't call getscanline on an empty image");
  is($im->errstr, "getscanline: empty input image", "check message");
  ok(!$im->setscanline(y => 0, pixels => [ $red, $blue ]),
     "can't call setscanline on an empty image");
  is($im->errstr, "setscanline: empty input image", "check message");
  ok(!$im->getsamples(y => 0), "can't call getsamples on an empty image");
  is($im->errstr, "getsamples: empty input image", "check message");
  is($im->getwidth, undef, "can't get width of empty image");
  is($im->errstr, "getwidth: empty input image", "check message");
  is($im->getheight, undef, "can't get height of empty image");
  is($im->errstr, "getheight: empty input image", "check message");
  is($im->getchannels, undef, "can't get channels of empty image");
  is($im->errstr, "getchannels: empty input image", "check message");
  is($im->getmask, undef, "can't get mask of empty image");
  is($im->errstr, "getmask: empty input image", "check message");
  is($im->setmask, undef, "can't set mask of empty image");
  is($im->errstr, "setmask: empty input image", "check message");
}

{ # basic checks, 8-bit direct images
  my $im = Imager->new(xsize => 2, ysize => 3);
  ok($im, 'create 8-bit direct image');
  is($im->bits, 8, '8 bits');
  ok(!$im->virtual, 'not virtual');
  is($im->type, 'direct', 'direct image');
  ok(!$im->is_bilevel, 'not mono');
}

ok(!Imager->new(xsize=>0, ysize=>1), "fail to create 0 height image");
cmp_ok(Imager->errstr, '=~', qr/Image sizes must be positive/,
       "0 height error message check");
ok(!Imager->new(xsize=>1, ysize=>0), "fail to create 0 width image");
cmp_ok(Imager->errstr, '=~', qr/Image sizes must be positive/,
       "0 width error message check");
ok(!Imager->new(xsize=>-1, ysize=>1), "fail to create -ve height image");
cmp_ok(Imager->errstr, '=~', qr/Image sizes must be positive/,
       "-ve width error message check");
ok(!Imager->new(xsize=>1, ysize=>-1), "fail to create -ve width image");
cmp_ok(Imager->errstr, '=~', qr/Image sizes must be positive/,
       "-ve height error message check");
ok(!Imager->new(xsize=>-1, ysize=>-1), "fail to create -ve width/height image");
cmp_ok(Imager->errstr, '=~', qr/Image sizes must be positive/,
       "-ve width/height error message check");

ok(!Imager->new(xsize=>1, ysize=>1, channels=>0),
   "fail to create a zero channel image");
cmp_ok(Imager->errstr, '=~', qr/channels must be between 1 and 4/,
       "out of range channel message check");
ok(!Imager->new(xsize=>1, ysize=>1, channels=>5),
   "fail to create a five channel image");
cmp_ok(Imager->errstr, '=~', qr/channels must be between 1 and 4/,
       "out of range channel message check");

{
  # https://rt.cpan.org/Ticket/Display.html?id=8213
  # check for handling of memory allocation of very large images
  # only test this on 32-bit machines - on a 64-bit machine it may
  # result in trying to allocate 4Gb of memory, which is unfriendly at
  # least and may result in running out of memory, causing a different
  # type of exit
 SKIP:
  {
    use Config;
    skip("don't want to allocate 4Gb", 8) unless $Config{ptrsize} == 4;

    my $uint_range = 256 ** $Config{intsize};
    print "# range $uint_range\n";
    my $dim1 = int(sqrt($uint_range))+1;
    
    my $im_b = Imager->new(xsize=>$dim1, ysize=>$dim1, channels=>1);
    is($im_b, undef, "integer overflow check - 1 channel");
    
    $im_b = Imager->new(xisze=>$dim1, ysize=>1, channels=>1);
    ok($im_b, "but same width ok");
    $im_b = Imager->new(xisze=>1, ysize=>$dim1, channels=>1);
    ok($im_b, "but same height ok");
    cmp_ok(Imager->errstr, '=~', qr/integer overflow/,
           "check the error message");

    # do a similar test with a 3 channel image, so we're sure we catch
    # the same case where the third dimension causes the overflow
    my $dim3 = int(sqrt($uint_range / 3))+1;
    
    $im_b = Imager->new(xsize=>$dim3, ysize=>$dim3, channels=>3);
    is($im_b, undef, "integer overflow check - 3 channel");
    
    $im_b = Imager->new(xisze=>$dim3, ysize=>1, channels=>3);
    ok($im_b, "but same width ok");
    $im_b = Imager->new(xisze=>1, ysize=>$dim3, channels=>3);
    ok($im_b, "but same height ok");

    cmp_ok(Imager->errstr, '=~', qr/integer overflow/,
           "check the error message");
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
  $img->to_rgb8(); # doesn't really matter what the source is
  cmp_ok($warning, '=~', 'void', "correct warning");
  cmp_ok($warning, '=~', 'introvert\\.t', "correct file");
}

{ # http://rt.cpan.org/NoAuth/Bug.html?id=11860
  my $im = Imager->new(xsize=>2, ysize=>2);
  $im->setpixel(x=>0, 'y'=>0, color=>$red);
  $im->setpixel(x=>1, 'y'=>0, color=>$blue);

  my @row = Imager::i_glin($im->{IMG}, 0, 2, 0);
  is(@row, 2, "got 2 pixels from i_glin");
  is_color3($row[0], 255, 0, 0, "red first");
  is_color3($row[1], 0, 0, 255, "then blue");
}

{ # general tag tests
  
  # we don't care much about the image itself
  my $im = Imager::ImgRaw::new(10, 10, 1);

  ok(Imager::i_tags_addn($im, 'alpha', 0, 101), "i_tags_addn(...alpha, 0, 101)");
  ok(Imager::i_tags_addn($im, undef, 99, 102), "i_tags_addn(...undef, 99, 102)");
  is(Imager::i_tags_count($im), 2, "should have 2 tags");
  ok(Imager::i_tags_addn($im, undef, 99, 103), "i_tags_addn(...undef, 99, 103)");
  is(Imager::i_tags_count($im), 3, "should have 3 tags, despite the dupe");
  is(Imager::i_tags_find($im, 'alpha', 0), '0 but true', "find alpha");
  is(Imager::i_tags_findn($im, 99, 0), 1, "find 99");
  is(Imager::i_tags_findn($im, 99, 2), 2, "find 99 again");
  is(Imager::i_tags_get($im, 0), 101, "check first");
  is(Imager::i_tags_get($im, 1), 102, "check second");
  is(Imager::i_tags_get($im, 2), 103, "check third");

  ok(Imager::i_tags_add($im, 'beta', 0, "hello", 0), 
     "add string with string key");
  ok(Imager::i_tags_add($im, 'gamma', 0, "goodbye", 0),
     "add another one");
  ok(Imager::i_tags_add($im, undef, 199, "aloha", 0),
     "add one keyed by number");
  is(Imager::i_tags_find($im, 'beta', 0), 3, "find beta");
  is(Imager::i_tags_find($im, 'gamma', 0), 4, "find gamma");
  is(Imager::i_tags_findn($im, 199, 0), 5, "find 199");
  ok(Imager::i_tags_delete($im, 2), "delete");
  is(Imager::i_tags_find($im, 'beta', 0), 2, 'find beta after deletion');
  ok(Imager::i_tags_delbyname($im, 'beta'), 'delete beta by name');
  is(Imager::i_tags_find($im, 'beta', 0), undef, 'beta not there now');
  is(Imager::i_tags_get_string($im, "gamma"), "goodbye", 
     'i_tags_get_string() on a string');
  is(Imager::i_tags_get_string($im, 99), 102, 
     'i_tags_get_string() on a number entry');
  ok(Imager::i_tags_delbycode($im, 99), 'delete by code');
  is(Imager::i_tags_findn($im, 99, 0), undef, '99 not there now');
  is(Imager::i_tags_count($im), 3, 'final count of 3');
}

{ 
  print "# low-level scan line function tests\n";
  my $im = Imager::ImgRaw::new(10, 10, 4);
  Imager::i_ppix($im, 5, 0, $red);

  # i_glin/i_glinf
  my @colors = Imager::i_glin($im, 0, 10, 0);
  is_deeply([ (0) x 20, (255, 0, 0, 255), (0) x 16 ], 
	    [ map $_->rgba, @colors ],
	    "i_glin - list context");
  my $colors = Imager::i_glin($im, 0, 10, 0);
  is("00" x 20 . "FF0000FF" . "00" x 16, 
     uc unpack("H*", $colors), "i_glin - scalar context");
  my @fcolors = Imager::i_glinf($im, 0, 10, 0);
  is_deeply([ (0.0) x 20, (1.0, 0, 0, 1.0) , (0) x 16 ],
	    [ map $_->rgba, @fcolors ],
	    "i_glinf - list context");
  my $fcolors = Imager::i_glinf($im, 0, 10, 0);
  is_deeply([ (0.0) x 20, (1.0, 0, 0, 1.0) , (0) x 16 ],
	    [ unpack "d*", $fcolors ],
	    "i_glinf - scalar context");

  # i_plin/i_plinf
  my @plin_colors = (($black) x 4, $red, $blue, ($black) x 4);
  is(Imager::i_plin($im, 0, 1, @plin_colors),
     10, "i_plin - pass in a list");
  # make sure we get it back
  is_deeply([ map [ $_->rgba ], @plin_colors ],
	    [ map [ $_->rgba ], Imager::i_glin($im, 0, 10, 1) ],
	    "check i_plin wrote to the image");
  my @scalar_plin = 
    (
     (0,0,0,0) x 4, 
     (0, 255, 0, 255),
     (0, 0, 255, 255), 
     (0, 0, 0, 0) x 4,
    );
  is(Imager::i_plin($im, 0, 2, pack("C*", @scalar_plin)),
     10, "i_plin - pass in a scalar");
  is_deeply(\@scalar_plin,
	    [ map $_->rgba , Imager::i_glin($im, 0, 10, 2) ],
	    "check i_plin scalar wrote to the image");

  my @plinf_colors = # Note: only 9 pixels
    ( 
     ($f_blue) x 4, 
     $f_red, 
     ($f_black) x 3, 
     $f_black
    );
  is(Imager::i_plinf($im, 0, 3, @plinf_colors), 9,
     "i_plinf - list");
  is_deeply([ map $_->rgba, Imager::i_glinf($im, 0, 9, 3) ],
	    [ map $_->rgba, @plinf_colors ],
	    "check colors were written");
  my @scalar_plinf =
    (
     ( 1.0, 1.0,   0, 1.0 ) x 3,
     (   0, 1.0, 1.0, 1.0 ) x 2,
     (   0,   0,   0,   0 ),
     ( 1.0,   0, 1.0, 1.0 ),
    );
  is(Imager::i_plinf($im, 2, 4, pack("d*", @scalar_plinf)),
     7, "i_plinf - scalar");
  is_deeply(\@scalar_plinf,
	    [ map $_->rgba, Imager::i_glinf($im, 2, 9, 4) ],
	    "check colors were written");

  is_deeply([ Imager::i_gsamp($im, 0, 10, 0, [ 0, 3 ]) ],
	    [ (0, 0) x 5, (255, 255), (0, 0) x 4 ],
	    "i_gsamp list context");
  is("0000" x 5 . "FFFF" . "0000" x 4,
     uc unpack("H*", Imager::i_gsamp($im, 0, 10, 0, [ 0, 3 ])),
     "i_gsamp scalar context");
  is_deeply([ Imager::i_gsampf($im, 2, 9, 4, [ 0, 2, 3 ]) ],
	    [ (1.0, 0, 1.0) x 3, (0, 1.0, 1.0) x 2, (0, 0, 0),
	      (1.0, 1.0, 1.0) ], "i_gsampf - list context");
  is_deeply([ unpack("d*", Imager::i_gsampf($im, 2, 9, 4, [ 0, 2, 3 ])) ],
	    [ (1.0, 0, 1.0) x 3, (0, 1.0, 1.0) x 2, (0, 0, 0),
              (1.0, 1.0, 1.0) ], "i_gsampf - scalar context");
  print "# end low-level scan-line function tests\n";
}

my $psamp_outside_error = "Image position outside of image";
{ # psamp
  print "# psamp\n";
  my $imraw = Imager::ImgRaw::new(10, 20, 3);
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
    is(Imager::i_psamp($imraw, 4, 6, undef, [ 0 .. 18 ], 1), 18,
       "psamp with offset");
    is_deeply([ Imager::i_gsamp($imraw, 0, 10, 6, undef) ],
	      [ (0) x 12, 1 .. 18 ],
	      "check result");
    is(Imager::i_psamp($imraw, 4, 11, undef, [ 0 .. 18 ], 1, 3), 9,
       "psamp with offset and width");
    is_deeply([ Imager::i_gsamp($imraw, 0, 10, 11, undef) ],
	      [ (0) x 12, 1 .. 9, (0) x 9 ],
	      "check result");
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
    is(_get_error(), $psamp_outside_error,
       "check error message");
    is(Imager::i_psamp($imraw, 0, 20, undef, [ 0, 0, 0 ]), undef,
       "y overflow");
    is(_get_error(), $psamp_outside_error,
       "check error message");
    is(Imager::i_psamp($imraw, -1, 0, undef, [ 0, 0, 0 ]), undef,
       "negative x");
    is(_get_error(), $psamp_outside_error,
       "check error message");
    is(Imager::i_psamp($imraw, 10, 0, undef, [ 0, 0, 0 ]), undef,
       "x overflow");
    is(_get_error(), $psamp_outside_error,
       "check error message");
  }
  { # test the im_sample_list typemap
    ok(!eval { Imager::i_psamp($imraw, 9, 9, [ 0 ], undef); 1 },
       "pass undef as the sample list");
    like($@, qr/data must be a scalar or an arrayref/,
	 "check message");
    ok(!eval { Imager::i_psamp($imraw, 9, 9, [ 0 ], { a => 1 }); 1 },
       "hashref as the sample list");
    like($@, qr/data must be a scalar or an arrayref/,
	 "check message");
    ok(!eval { Imager::i_psamp($imraw, 9, 9, [ 0 ], []); 1 },
       "empty sample list");
    like($@, qr/i_psamp: no samples provided in data/,
	 "check message");
    ok(!eval { Imager::i_psamp($imraw, 9, 9, [ 0 ], ""); 1 },
       "empty scalar sample list");
    like($@, qr/i_psamp: no samples provided in data/,
	 "check message");

    # not the typemap
    is(Imager::i_psamp($imraw, 0, 8, undef, [ (0) x 3 ], -1), undef,
       "negative offset");
    is(_get_error(), "offset must be non-negative",
       "check message");

    is(Imager::i_psamp($imraw, 0, 8, undef, [ (0) x 3 ], 4), undef,
       "too high offset");
    is(_get_error(), "offset greater than number of samples supplied",
       "check message");
  }
  print "# end psamp tests\n";
}

{ # psampf
  print "# psampf\n";
  my $imraw = Imager::ImgRaw::new(10, 20, 3);
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
    is(Imager::i_psampf($imraw, 4, 6, undef, [ map $_/254.9, 0 .. 18 ], 1), 18,
       "psampf with offset");
    is_deeply([ Imager::i_gsamp($imraw, 0, 10, 6, undef) ],
	      [ (0) x 12, 1 .. 18 ],
	      "check result");
    is(Imager::i_psampf($imraw, 4, 11, undef, [ map $_/254.9, 0 .. 18 ], 1, 3), 9,
       "psampf with offset and width");
    is_deeply([ Imager::i_gsamp($imraw, 0, 10, 11, undef) ],
	      [ (0) x 12, 1 .. 9, (0) x 9 ],
	      "check result");
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
    is(_get_error(), $psamp_outside_error,
       "check error message");
    is(Imager::i_psampf($imraw, 0, 20, undef, [ 0, 0, 0 ]), undef,
       "y overflow");
    is(_get_error(), $psamp_outside_error,
       "check error message");
    is(Imager::i_psampf($imraw, -1, 0, undef, [ 0, 0, 0 ]), undef,
       "negative x");
    is(_get_error(), $psamp_outside_error,
       "check error message");
    is(Imager::i_psampf($imraw, 10, 0, undef, [ 0, 0, 0 ]), undef,
       "x overflow");
    is(_get_error(), $psamp_outside_error,
       "check error message");
  }
  { # test the im_fsample_list typemap
    ok(!eval { Imager::i_psampf($imraw, 9, 9, [ 0 ], undef); 1 },
       "pass undef as the sample list");
    like($@, qr/data must be a scalar or an arrayref/,
	 "check message");
    ok(!eval { Imager::i_psampf($imraw, 9, 9, [ 0 ], { a => 1 }); 1 },
       "hashref as the sample list");
    like($@, qr/data must be a scalar or an arrayref/,
	 "check message");
    ok(!eval { Imager::i_psampf($imraw, 9, 9, [ 0 ], []); 1 },
       "empty sample list");
    like($@, qr/i_psampf: no samples provided in data/,
	 "check message");
    ok(!eval { Imager::i_psampf($imraw, 9, 9, [ 0 ], ""); 1 },
       "empty scalar sample list");
    like($@, qr/i_psampf: no samples provided in data/,
	 "check message");

    # not the typemap
    is(Imager::i_psampf($imraw, 0, 8, undef, [ (0) x 3 ], -1), undef,
       "negative offset");
    is(_get_error(), "offset must be non-negative",
       "check message");

    is(Imager::i_psampf($imraw, 0, 8, undef, [ (0) x 3 ], 4), undef,
       "too high offset");
    is(_get_error(), "offset greater than number of samples supplied",
       "check message");
  }
  print "# end psampf tests\n";
}

{
  print "# OO level scanline function tests\n";
  my $im = Imager->new(xsize=>10, ysize=>10, channels=>4);
  $im->setpixel(color=>$red, 'x'=>5, 'y'=>0);
  ok(!$im->getscanline(), "getscanline() - supply nothing, get nothing");
  is($im->errstr, "missing y parameter", "check message");
  is_deeply([ map [ $_->rgba ], $im->getscanline('y'=>0) ],
	    [ ([ 0,0,0,0]) x 5, [ 255, 0, 0, 255 ], ([ 0,0,0,0]) x 4 ],
	    "getscanline, list context, default x, width");
  is_deeply([ map [ $_->rgba ], $im->getscanline('y'=>0, 'x'=>3) ],
	    [ ([0,0,0,0]) x 2, [ 255, 0, 0, 255 ], ([0,0,0,0]) x 4 ],
	    "getscanline, list context, default width");
  is_deeply([ map [ $_->rgba ], $im->getscanline('y'=>0, 'x'=>4, width=>4) ],
	    [ [0,0,0,0], [ 255, 0, 0, 255 ], ([0,0,0,0]) x 2 ],
	    "getscanline, list context, no defaults");
  is(uc unpack("H*",  $im->getscanline('y'=>0)),
     "00000000" x 5 .  "FF0000FF" . "00000000" x 4,
     "getscanline, scalar context, default x, width");
  is_deeply([ map [ $_->rgba ], 
	      $im->getscanline('y'=>0, 'x'=>4, width=>4, type=>'float') ],
	    [ [0,0,0,0], [ 1.0, 0, 0, 1.0 ], ([0,0,0,0]) x 2 ],
	    "getscanline float, list context, no defaults");
  is_deeply([ unpack "d*",
	      $im->getscanline('y'=>0, 'x'=>4, width=>4, type=>'float') ],
	    [ (0,0,0,0), ( 1.0, 0, 0, 1.0 ), (0,0,0,0) x 2 ],
	    "getscanline float, scalar context, no defaults");

  ok(!$im->getscanline('y'=>0, type=>'invalid'),
     "check invalid type checking");
  like($im->errstr, qr/invalid type parameter/, 
       "check message for invalid type");

  my @plin_colors = (($black) x 4, $red, $blue, ($green) x 4);
  is($im->setscanline('y'=>1, pixels=>\@plin_colors), 10,
     "setscanline - arrayref, default x");
  is_deeply([ map [ $_->rgba ], @plin_colors ],
	    [ map [ $_->rgba ], $im->getscanline('y'=>1) ],
	    "check colors were written");

  my @plin_colors2 = ( $green, $red, $blue, $red );
  is($im->setscanline('y'=>2, 'x'=>3, pixels=>\@plin_colors2), 4,
     "setscanline - arrayref");

  # using map instead of x here due to a bug in some versions of Test::More
  # fixed in the latest Test::More
  is_deeply([ ( map [ 0,0,0,0 ], 1..3), (map [ $_->rgba ], @plin_colors2),
	      ( map [ 0,0,0,0 ], 1..3) ],
	    [ map [ $_->rgba ], $im->getscanline('y'=>2) ],
	    "check write to middle of line");
  
  my $raw_colors = pack "H*", "FF00FFFF"."FF0000FF"."FFFFFFFF";
  is($im->setscanline('y'=>3, 'x'=>2, pixels=>$raw_colors), 3,
     "setscanline - scalar, default raw type")
    or print "# ",$im->errstr,"\n";
  is(uc unpack("H*", $im->getscanline('y'=>3, 'x'=>1, 'width'=>5)),
     "00000000".uc(unpack "H*", $raw_colors)."00000000",
     "check write");

  # float colors
  my @fcolors = ( $f_red, $f_blue, $f_black, $f_green );
  is($im->setscanline('y'=>4, 'x'=>3, pixels=>\@fcolors), 4,
     "setscanline - float arrayref");
  is_deeply([ map [ $_->rgba ], @fcolors ],
	    [ map [ $_->rgba ], $im->getscanline('y'=>4, 'x'=>3, width=>4, type=>'float') ],
	    "check write");
  # packed
  my $packed_fcolors = pack "d*", map $_->rgba, @fcolors;
  is($im->setscanline('y'=>5, 'x'=>4, pixels=>$packed_fcolors, type=>'float'), 4,
     "setscanline - float scalar");
  is_deeply([ map [ $_->rgba ], @fcolors ],
	    [ map [ $_->rgba ], $im->getscanline('y'=>5, 'x'=>4, width=>4, type=>'float') ],
	    "check write");

  # get samples
  is_deeply([ $im->getsamples('y'=>1, channels=>[ 0 ]) ],
	    [ map +($_->rgba)[0], @plin_colors ],
	    "get channel 0, list context, default x, width");
  is_deeply([ unpack "C*", $im->getsamples('y'=>1, channels=>[0, 2]) ],
	    [ map { ($_->rgba)[0, 2] } @plin_colors ],
	    "get channel 0, 1, scalar context");
  is_deeply([ $im->getsamples('y'=>4, 'x'=>3, width=>4, type=>'float',
			      channels=>[1,3]) ],
	    [ map { ($_->rgba)[1,3] } @fcolors ],
	    "get channels 1,3, list context, float samples");
  is_deeply([ unpack "d*", 
	      $im->getsamples('y'=>4, 'x'=>3, width=>4,
			      type=>'float', channels=>[3,2,1,0]) ],
	    [ map { ($_->rgba)[3,2,1,0] } @fcolors ],
	    "get channels 3..0 as scalar, float samples");
  
  print "# end OO level scanline function tests\n";
}

{ # RT 74882
  # for the non-gsamp_bits case with a target parameter it was
  # treating the target parameter as a hashref
  {
    my $im = Imager->new(xsize => 10, ysize => 10);
    my $c1 = NC(0, 63, 255);
    my $c2 = NC(255, 128, 255);
    is($im->setscanline(y => 1, pixels => [ ( $c1, $c2 ) x 5 ]),
       10, "set some test data")
      or diag "setscanline: ", $im->errstr;
    my @target;
    is($im->getsamples(y => 1, x => 1, target => \@target, width => 3),
       9, "getsamples to target");
    is_deeply(\@target, [ 255, 128, 255, 0, 63, 255, 255, 128, 255 ],
	      "check result");
  }
  {
    my $im = Imager->new(xsize => 10, ysize => 10, bits => "double");
    my $c1 = NCF(0, 0.25, 1.0);
    my $c2 = NCF(1.0, 0.5, 1.0);
    is($im->setscanline(y => 1, pixels => [ ( $c1, $c2 ) x 5 ]),
       10, "set some test data")
      or diag "setscanline: ", $im->errstr;
    my @target;
    is($im->getsamples(y => 1, x => 1, target => \@target, width => 3, type => "float"),
       9, "getsamples to target");
    is_deeply(\@target, [ 1.0, 0.5, 1.0, 0, 0.25, 1.0, 1.0, 0.5, 1.0 ],
	      "check result");
  }
}

{ # to avoid confusion, i_glin/i_glinf modified to return 0 in unused
  # channels at the perl level
  my $im = Imager->new(xsize => 4, ysize => 4, channels => 2);
  my $fill = Imager::Color->new(128, 255, 0, 0);
  ok($im->box(filled => 1, color => $fill), 'fill it up');
  my $data = $im->getscanline('y' => 0);
  is(unpack("H*", $data), "80ff000080ff000080ff000080ff0000",
     "check we get zeros");
  my @colors = $im->getscanline('y' => 0);
  is_color4($colors[0], 128, 255, 0, 0, "check object interface[0]");
  is_color4($colors[1], 128, 255, 0, 0, "check object interface[1]");
  is_color4($colors[2], 128, 255, 0, 0, "check object interface[2]");
  is_color4($colors[3], 128, 255, 0, 0, "check object interface[3]");
  
  my $dataf = $im->getscanline('y' => 0, type => 'float');
  # the extra pack/unpack is to force double precision rather than long
  # double, otherwise the test fails
  is_deeply([ unpack("d*", $dataf) ],
	    [ unpack("d*", pack("d*", ( 128.0 / 255.0, 1.0, 0, 0, ) x 4)) ],
	    "check we get zeroes (double)");
  my @fcolors = $im->getscanline('y' => 0, type => 'float');
  is_fcolor4($fcolors[0], 128.0/255.0, 1.0, 0, 0, "check object interface[0]");
  is_fcolor4($fcolors[1], 128.0/255.0, 1.0, 0, 0, "check object interface[1]");
  is_fcolor4($fcolors[2], 128.0/255.0, 1.0, 0, 0, "check object interface[2]");
  is_fcolor4($fcolors[3], 128.0/255.0, 1.0, 0, 0, "check object interface[3]");
}

{ # check the channel mask function
  
  my $im = Imager->new(xsize => 10, ysize=>10, bits=>8);

  mask_tests($im, 0.005);
}

{ # check bounds checking
  my $im = Imager->new(xsize => 10, ysize => 10);

  image_bounds_checks($im);
}

{ # setsamples() interface to psamp()
  my $im = Imager->new(xsize => 10, ysize => 10);
  is($im->setsamples(y => 1, x => 2, data => [ 1 .. 6 ]), 6,
     "simple put (array), default channels");
  is_deeply([ $im->getsamples(y => 1, x => 0) ],
	    [ (0) x 6, 1 .. 6, (0) x 18 ], "check they were stored");
  is($im->setsamples(y => 3, x => 3, data => pack("C*", 2 .. 10 )), 9,
     "simple put (scalar), default channels")
    or diag $im->errstr;
  is_deeply([ $im->getsamples(y => 3, x => 0) ],
	    [ (0) x 9, 2 .. 10, (0) x 12 ], "check they were stored");
  is($im->setsamples(y => 4, x => 4, data => [ map $_ / 254.5, 1 .. 6 ], type => 'float'),
     6, "simple put (float array), default channels");
  is_deeply([ $im->getsamples(y => 4, x => 0) ],
	    [ (0) x 12, 1 .. 6, (0) x 12 ], "check they were stored");

  is($im->setsamples(y => 5, x => 3, data => pack("d*", map $_ / 254.5, 1 .. 6), type => 'float'),
     6, "simple put (float scalar), default channels");
  is_deeply([ $im->getsamples(y => 5, x => 0) ],
	    [ (0) x 9, 1 .. 6, (0) x 15 ], "check they were stored");

  is($im->setsamples(y => 7, x => 3, data => [ 0 .. 18 ], offset => 1), 18,
     "setsamples offset");
  is_deeply([ $im->getsamples(y => 7) ],
	    [ (0) x 9, 1 .. 18, (0) x 3 ],
	    "check result");

  is($im->setsamples(y => 8, x => 3, data => [ map $_ / 254.9, 0 .. 18 ],
		     offset => 1, type => 'float'),
     18, "setsamples offset (float)");
  is_deeply([ $im->getsamples(y => 8) ],
	    [ (0) x 9, 1 .. 18, (0) x 3 ],
	    "check result");

  is_deeply([ $im->setsamples(y => 6, x => 10, data => [ (0) x 3 ]) ],
	    [], "check out of range result (8bit)");
  is($im->errstr, $psamp_outside_error, "check error message");

  is_deeply([ $im->setsamples(y => 6, x => 10, data => [ (0) x 3 ], type => "float") ],
	    [], "check out of range result (float)");
  is($im->errstr, $psamp_outside_error, "check error message");

  is_deeply([ $im->setsamples(y => 6, x => 2, channels => [0, 1, 3 ],
			      data => [ (0) x 3 ]) ],
	    [], "check bad channels (8bit)");
  is($im->errstr, "No channel 3 in this image",
     "check error message");
  
  is_deeply([ $im->setsamples(y => 6, x => 2, channels => [0, 1, 3 ], 
			      data => [ (0) x 3 ], type => "float") ],
	    [], "check bad channels (float)");
  is($im->errstr, "No channel 3 in this image",
     "check error message");

  is($im->setsamples(y => 5, data => [ (0) x 3 ], type => "bad"),
     undef, "setsamples with bad type");
  is($im->errstr, "setsamples: type parameter invalid",
     "check error message");
  is($im->setsamples(y => 5),
     undef, "setsamples with no data");
  is($im->errstr, "setsamples: data parameter missing",
     "check error message");

  is($im->setsamples(y => 5, data => undef),
     undef, "setsamples with undef data");
  is($im->errstr, "setsamples: data parameter not defined",
     "check error message");

  my $imempty = Imager->new;
  is($imempty->setsamples(y => 0, data => [ (0) x 3 ]), undef,
     "setsamples to empty image");
  is($imempty->errstr, "setsamples: empty input image",
     "check error message");
}

{ # getpixel parameters
  my $im = Imager->new(xsize => 10, ysize => 10);
  $im->box(filled => 1, xmax => 4, color => NC(255, 0, 0));
  $im->box(filled => 1, xmin => 5, ymax => 4, color => NC(0, 255, 255));
  $im->box(filled => 1, xmin => 5, ymin => 5, color => NC(255, 0, 255));
  { # error handling
    my $empty = Imager->new;
    ok(!$empty->getpixel(x => 0, y => 0), "getpixel empty image");
    is($empty->errstr, "getpixel: empty input image", "check message");

    ok(!$im->getpixel(y => 0), "missing x");
    is($im->errstr, "getpixel: missing x or y parameter", "check message");

    $im->_set_error("something different");
    ok(!$im->getpixel(x => 0), "missing y");
    is($im->errstr, "getpixel: missing x or y parameter", "check message");

    ok(!$im->getpixel(x => [], y => 0), "empty x array ref");
    is($im->errstr, "getpixel: x is a reference to an empty array",
       "check message");

    ok(!$im->getpixel(x => 0, y => []), "empty y array ref");
    is($im->errstr, "getpixel: y is a reference to an empty array",
       "check message");

    ok(!$im->getpixel(x => 0, y => 0, type => "bad"), "bad type (scalar path)");
    is($im->errstr, "getpixel: type must be '8bit' or 'float'",
      "check message");

    $im->_set_error("something different");
    ok(!$im->getpixel(x => [ 0 ], y => [ 0 ], type => "bad"),
       "bad type (array path)");
    is($im->errstr, "getpixel: type must be '8bit' or 'float'",
      "check message");
  }

  # simple calls
  is_color3($im->getpixel(x => 1, y => 0), 255, 0, 0,
	    "getpixel(1, 0)");
  is_color3($im->getpixel(x => 8, y => 1), 0, 255, 255,
	    "getpixel(8, 1)");
  is_color3($im->getpixel(x => 8, y => 7), 255, 0, 255,
	    "getpixel(8, 7)");

  {
    # simple arrayrefs
    my @colors = $im->getpixel(x => [ 0, 8, 7 ], y => [ 0, 7, 3 ]);
    is(@colors, 3, "getpixel 2 3 element array refs");
    is_color3($colors[0], 255, 0, 0, "check first color");
    is_color3($colors[1], 255, 0, 255, "check second color");
    is_color3($colors[2], 0, 255, 255, "check third color");
  }
  
  # array and scalar
  {
    my @colors = $im->getpixel(x => 5, y => [ 4, 5, 9 ]);
    is(@colors, 3, "getpixel x scalar, y arrayref of 3");
    is_color3($colors[0], 0, 255, 255, "check first color");
    is_color3($colors[1], 255, 0, 255, "check second color");
    is_color3($colors[2], 255, 0, 255, "check third color");
  }

  {
    my @colors = $im->getpixel(x => [ 0, 4, 5 ], y => 2);
    is(@colors, 3, "getpixel y scalar, x arrayref of 3");
    is_color3($colors[0], 255, 0, 0, "check first color");
    is_color3($colors[1], 255, 0, 0, "check second color");
    is_color3($colors[2], 0, 255, 255, "check third color");
  }

  { # float
    is_fcolor3($im->getpixel(x => 1, y => 0, type => 'float'),
	       1.0, 0, 0, "getpixel(1,0) float");
    is_fcolor3($im->getpixel(x => 8, y => 1, type => 'float'),
	       0, 1.0, 1.0, "getpixel(8,1) float");
    is_fcolor3($im->getpixel(x => 8, y => 7, type => 'float'),
	       1.0, 0, 1.0, "getpixel(8,7) float");

    my @colors = $im->getpixel(x => [ 0, 8, 7 ], y => [ 0, 7, 3 ], type => 'float');
    is(@colors, 3, "getpixel 2 3 element array refs (float)");
    is_fcolor3($colors[0], 1, 0, 0, "check first color");
    is_fcolor3($colors[1], 1, 0, 1, "check second color");
    is_fcolor3($colors[2], 0, 1, 1, "check third color");
  }

  { # out of bounds
    my @colors = $im->getpixel(x => [ 0, -1, 5, 10 ], y => 0);
    is(@colors, 4, "should be 4 entries")
      or diag $im->errstr;
    is_color3($colors[0], 255, 0, 0, "first red");
    is($colors[1], undef, "second undef");
    is_color3($colors[2], 0, 255, 255, "third cyan");
    is($colors[3], undef, "fourth undef");
  }

  { # out of bounds
    my @colors = $im->getpixel(x => [ 0, -1, 5, 10 ], y => 0, type => "float");
    is(@colors, 4, "should be 4 entries")
      or diag $im->errstr;
    is_fcolor3($colors[0], 1.0, 0, 0, "first red");
    is($colors[1], undef, "second undef");
    is_fcolor3($colors[2], 0, 1.0, 1.0, "third cyan");
    is($colors[3], undef, "fourth undef");
  }
}

{ # setpixel
  my $im = Imager->new(xsize => 10, ysize => 10);
  { # errors
    my $empty = Imager->new;
    ok(!$empty->setpixel(x => 0, y => 0, color => $red),
       "setpixel on empty image");
    is($empty->errstr, "setpixel: empty input image", "check message");

    ok(!$im->setpixel(y => 0, color => $red), "missing x");
    is($im->errstr, "setpixel: missing x or y parameter", "check message");

    $im->_set_error("something different");
    ok(!$im->setpixel(x => 0, color => $red), "missing y");
    is($im->errstr, "setpixel: missing x or y parameter", "check message");

    ok(!$im->setpixel(x => [], y => 0, color => $red), "empty x array ref");
    is($im->errstr, "setpixel: x is a reference to an empty array",
       "check message");

    ok(!$im->setpixel(x => 0, y => [], color => $red), "empty y array ref");
    is($im->errstr, "setpixel: y is a reference to an empty array",
       "check message");

    ok(!$im->setpixel(x => 0, y => 0, color => "not really a color"),
       "color not a color");
    is($im->errstr, "setpixel: No color named not really a color found",
       "check message");
  }

  # simple set
  is($im->setpixel(x => 0, y => 0, color => $red), $im,
     "simple setpixel")
    or diag "simple set float: ", $im->errstr;
  is_color3($im->getpixel(x => 0, y => 0), 255, 0, 0, "check stored pixel");

  is($im->setpixel(x => 1, y => 2, color => $f_red), $im,
     "simple setpixel (float)")
    or diag "simple set float: ", $im->errstr;
  is_color3($im->getpixel(x => 1, y => 2), 255, 0, 0, "check stored pixel");

  is($im->setpixel(x => -1, y => 0, color => $red), undef,
     "simple setpixel outside of image");
  is($im->setpixel(x => 0, y => -1, color => $f_red), undef,
     "simple setpixel (float) outside of image");

  # simple arrayrefs
  is($im->setpixel( x => [ 0, 8, 7 ], y => [ 0, 7, 3 ], color => $blue),
     3, "setpixel with 3 element array refs");
  my @colors = $im->getpixel(x => [ 8, 7, 0 ], y => [ 7, 3, 0 ]);
  is_color3($colors[0], 0, 0, 255, "check first color");
  is_color3($colors[1], 0, 0, 255, "check second color");
  is_color3($colors[2], 0, 0, 255, "check third color");

  # array and scalar
  {
    is($im->setpixel(x => 5, y => [ 4, 5, 9 ], color => $green), 3,
       "setpixel with x scalar, y arrayref of 3");
    my @colors = $im->getpixel(x => [ 5, 5, 5 ], y => [ 4, 5, 9 ]);
    is_color3($colors[0], 0, 255, 0, "check first color");
    is_color3($colors[1], 0, 255, 0, "check second color");
    is_color3($colors[2], 0, 255, 0, "check third color");
  }

  {
    is($im->setpixel(x => [ 0, 4, 5 ], y => 2, color => $blue), 3,
       "setpixel with y scalar, x arrayref of 3");
    my @colors = $im->getpixel(x => [ 0, 4, 5 ], y => [ 2, 2, 2 ]);
    is_color3($colors[0], 0, 0, 255, "check first color");
    is_color3($colors[1], 0, 0, 255, "check second color");
    is_color3($colors[2], 0, 0, 255, "check third color");
  }

  {
    is($im->setpixel(x => [ 0, -1, 10, 5, 0 ], y => [ 0, 1, 2, 3, 1 ], color => $blue), 3,
       "set array with two bad locations")
      or diag "set array bad locations: ", $im->errstr;
    my @colors = $im->getpixel(x => [ 0, 5, 0 ], y => [ 0, 3, 1 ]);
    is_color3($colors[0], 0, 0, 255, "check first color");
    is_color3($colors[1], 0, 0, 255, "check second color");
    is_color3($colors[2], 0, 0, 255, "check third color");
  }
  {
    is($im->setpixel(x => [ 0, -1, 10, 5, 0 ], y => [ 0, 1, 2, 3, 1 ], color => $f_green), 3,
       "set array with two bad locations (float)")
      or diag "set array bad locations (float): ", $im->errstr;
    my @colors = $im->getpixel(x => [ 0, 5, 0 ], y => [ 0, 3, 1 ]);
    is_color3($colors[0], 0, 255, 0, "check first color");
    is_color3($colors[1], 0, 255, 0, "check second color");
    is_color3($colors[2], 0, 255, 0, "check third color");
  }
  { # default color
    is($im->setpixel(x => 0, y => 9), $im, "setpixel() default color")
      or diag "setpixel default color: ", $im->errstr;
    is_color3($im->getpixel(x => 0, y => 9), 255, 255, 255,
	      "check color set");
  }
}

{
  my $empty = Imager->new;
  ok(!$empty->addtag(name => "foo", value => 1),
     "can't addtag on an empty image");
  is($empty->errstr, "addtag: empty input image",
    "check error message");
  ok(!$empty->settag(name => "foo", value => 1),
     "can't settag on an empty image");
  is($empty->errstr, "settag: empty input image",
    "check error message");
  ok(!$empty->deltag(name => "foo"), "can't deltag on an empty image");
  is($empty->errstr, "deltag: empty input image",
     "check error message");
  ok(!$empty->tags(name => "foo"), "can't tags on an empty image");
  is($empty->errstr, "tags: empty input image",
     "check error message");
}

Imager->close_log();

unless ($ENV{IMAGER_KEEP_FILES}) {
  unlink "testout/t01introvert.log";
}

sub check_add {
  my ($im, $color, $expected) = @_;
  my $index = Imager::i_addcolors($im, $color);
  ok($index, "got index");
  print "# $index\n";
  is(0+$index, $expected, "index matched expected");
  my ($new) = Imager::i_getcolors($im, $index);
  ok($new, "got the color");
  ok(color_cmp($new, $color) == 0, "color matched what was added");

  $index;
}

# sub array_ncmp {
#   my ($a1, $a2) = @_;
#   my $len = @$a1 < @$a2 ? @$a1 : @$a2;
#   for my $i (0..$len-1) {
#     my $diff = $a1->[$i] <=> $a2->[$i] 
#       and return $diff;
#   }
#   return @$a1 <=> @$a2;
# }

sub dump_colors {
  for my $col (@_) {
    print "# ", map(sprintf("%02X", $_), ($col->rgba)[0..2]),"\n";
  }
}

sub _get_error {
  my @errors = Imager::i_errors();
  return join(": ", map $_->[0], @errors);
}
