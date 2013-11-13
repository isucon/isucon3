#!perl -w
use strict;
use Test::More tests => 155;

BEGIN { use_ok(Imager=>qw(:all :handy)) }

-d "testout" or mkdir "testout";

Imager->open_log(log => "testout/t021sixteen.log");

use Imager::Color::Float;
use Imager::Test qw(test_image is_image image_bounds_checks test_colorf_gpix
                    test_colorf_glin mask_tests is_color3);

my $im_g = Imager::i_img_16_new(100, 101, 1);

is(Imager::i_img_getchannels($im_g), 1, "1 channel image channel count");
ok(Imager::i_img_getmask($im_g) & 1, "1 channel image mask");
ok(!Imager::i_img_virtual($im_g), "shouldn't be marked virtual");
is(Imager::i_img_bits($im_g), 16, "1 channel image has bits == 16");
is(Imager::i_img_type($im_g), 0, "1 channel image isn't direct");

my @ginfo = i_img_info($im_g);
is($ginfo[0], 100, "1 channel image width");
is($ginfo[1], 101, "1 channel image height");

undef $im_g;

my $im_rgb = Imager::i_img_16_new(100, 101, 3);

is(Imager::i_img_getchannels($im_rgb), 3, "3 channel image channel count");
ok((Imager::i_img_getmask($im_rgb) & 7) == 7, "3 channel image mask");
is(Imager::i_img_bits($im_rgb), 16, "3 channel image bits");
is(Imager::i_img_type($im_rgb), 0, "3 channel image type");

my $redf = NCF(1, 0, 0);
my $greenf = NCF(0, 1, 0);
my $bluef = NCF(0, 0, 1);

# fill with red
for my $y (0..101) {
  Imager::i_plinf($im_rgb, 0, $y, ($redf) x 100);
}
pass("fill with red");
# basic sanity
test_colorf_gpix($im_rgb, 0,  0,   $redf, 0, "top-left");
test_colorf_gpix($im_rgb, 99, 0,   $redf, 0, "top-right");
test_colorf_gpix($im_rgb, 0,  100, $redf, 0, "bottom left");
test_colorf_gpix($im_rgb, 99, 100, $redf, 0, "bottom right");
test_colorf_glin($im_rgb, 0,  0,   [ ($redf) x 100 ], "first line");
test_colorf_glin($im_rgb, 0,  100, [ ($redf) x 100 ], "last line");

Imager::i_plinf($im_rgb, 20, 1, ($greenf) x 60);
test_colorf_glin($im_rgb, 0, 1, 
                 [ ($redf) x 20, ($greenf) x 60, ($redf) x 20 ],
		"added some green in the middle");
{
  my @samples;
  is(Imager::i_gsamp_bits($im_rgb, 18, 22, 1, 16, \@samples, 0, [ 0 .. 2 ]), 12, 
     "i_gsamp_bits all channels - count")
    or print "# ", Imager->_error_as_msg(), "\n";
  is_deeply(\@samples, [ 65535, 0, 0,   65535, 0, 0,
			 0, 65535, 0,   0, 65535, 0 ],
	    "check samples retrieved");
  @samples = ();
  is(Imager::i_gsamp_bits($im_rgb, 18, 22, 1, 16, \@samples, 0, [ 0, 2 ]), 8, 
     "i_gsamp_bits some channels - count")
    or print "# ", Imager->_error_as_msg(), "\n";
  is_deeply(\@samples, [ 65535, 0,   65535, 0,
			 0, 0,       0, 0     ],
	    "check samples retrieved");
  # fail gsamp
  is(Imager::i_gsamp_bits($im_rgb, 18, 22, 1, 16, \@samples, 0, [ 0, 3 ]), undef,
     "i_gsamp_bits fail bad channel");
  is(Imager->_error_as_msg(), 'No channel 3 in this image', 'check message');

  is(Imager::i_gsamp_bits($im_rgb, 18, 22, 1, 17, \@samples, 0, [ 0, 2 ]), 8, 
     "i_gsamp_bits succeed high bits");
  is($samples[0], 131071, "check correct with high bits");

  # write some samples back
  my @wr_samples = 
    ( 
     0, 0, 65535,
     65535, 0, 0,  
     0, 65535, 0,  
     65535, 65535, 0 
    );
  is(Imager::i_psamp_bits($im_rgb, 18, 2, 16, [ 0 .. 2 ], \@wr_samples),
     12, "write 16-bit samples")
    or print "# ", Imager->_error_as_msg(), "\n";
  @samples = ();
  is(Imager::i_gsamp_bits($im_rgb, 18, 22, 2, 16, \@samples, 0, [ 0 .. 2 ]), 12, 
     "read them back")
    or print "# ", Imager->_error_as_msg(), "\n";
  is_deeply(\@samples, \@wr_samples, "check they match");
  my $c = Imager::i_get_pixel($im_rgb, 18, 2);
  is_color3($c, 0, 0, 255, "check it write to the right places");
}

# basic OO tests
my $oo16img = Imager->new(xsize=>200, ysize=>201, bits=>16);
ok($oo16img, "make a 16-bit oo image");
is($oo16img->bits,  16, "test bits");
isnt($oo16img->is_bilevel, "should not be considered mono");
# make sure of error handling
ok(!Imager->new(xsize=>0, ysize=>1, bits=>16),
    "fail to create a 0 pixel wide image");
cmp_ok(Imager->errstr, '=~', qr/Image sizes must be positive/,
       "and correct error message");

ok(!Imager->new(xsize=>1, ysize=>0, bits=>16),
    "fail to create a 0 pixel high image");
cmp_ok(Imager->errstr, '=~', qr/Image sizes must be positive/,
       "and correct error message");

ok(!Imager->new(xsize=>-1, ysize=>1, bits=>16),
    "fail to create a negative width image");
cmp_ok(Imager->errstr, '=~', qr/Image sizes must be positive/,
       "and correct error message");

ok(!Imager->new(xsize=>1, ysize=>-1, bits=>16),
    "fail to create a negative height image");
cmp_ok(Imager->errstr, '=~', qr/Image sizes must be positive/,
       "and correct error message");

ok(!Imager->new(xsize=>-1, ysize=>-1, bits=>16),
    "fail to create a negative width/height image");
cmp_ok(Imager->errstr, '=~', qr/Image sizes must be positive/,
       "and correct error message");

ok(!Imager->new(xsize=>1, ysize=>1, bits=>16, channels=>0),
    "fail to create a zero channel image");
cmp_ok(Imager->errstr, '=~', qr/channels must be between 1 and 4/,
       "and correct error message");
ok(!Imager->new(xsize=>1, ysize=>1, bits=>16, channels=>5),
    "fail to create a five channel image");
cmp_ok(Imager->errstr, '=~', qr/channels must be between 1 and 4/,
       "and correct error message");

{
  # https://rt.cpan.org/Ticket/Display.html?id=8213
  # check for handling of memory allocation of very large images
  # only test this on 32-bit machines - on a 64-bit machine it may
  # result in trying to allocate 4Gb of memory, which is unfriendly at
  # least and may result in running out of memory, causing a different
  # type of exit
 SKIP: {
    use Config;
    $Config{ptrsize} == 4
      or skip("don't want to allocate 4Gb", 10);
    my $uint_range = 256 ** $Config{intsize};
    print "# range $uint_range\n";
    my $dim1 = int(sqrt($uint_range/2))+1;
    
    my $im_b = Imager->new(xsize=>$dim1, ysize=>$dim1, channels=>1, bits=>16);
    is($im_b, undef, "integer overflow check - 1 channel");
    
    $im_b = Imager->new(xisze=>$dim1, ysize=>1, channels=>1, bits=>16);
    ok($im_b, "but same width ok");
    $im_b = Imager->new(xisze=>1, ysize=>$dim1, channels=>1, bits=>16);
    ok($im_b, "but same height ok");
    cmp_ok(Imager->errstr, '=~', qr/integer overflow/,
           "check the error message");

    # do a similar test with a 3 channel image, so we're sure we catch
    # the same case where the third dimension causes the overflow
    my $dim3 = int(sqrt($uint_range / 3 / 2))+1;
    
    $im_b = Imager->new(xsize=>$dim3, ysize=>$dim3, channels=>3, bits=>16);
    is($im_b, undef, "integer overflow check - 3 channel");
    
    $im_b = Imager->new(xisze=>$dim3, ysize=>1, channels=>3, bits=>16);
    ok($im_b, "but same width ok");
    $im_b = Imager->new(xisze=>1, ysize=>$dim3, channels=>3, bits=>16);
    ok($im_b, "but same height ok");

    cmp_ok(Imager->errstr, '=~', qr/integer overflow/,
           "check the error message");

    # check we can allocate a scanline, unlike double images the scanline
    # in the image itself is smaller than a line of i_fcolor
    # divide by 2 to get to int range, by 2 for 2 bytes/pixel, by 3 to 
    # fit the image allocation in, but for the floats to overflow
    my $dim4 = $uint_range / 2 / 2 / 3;
    my $im_o = Imager->new(xsize=>$dim4, ysize=>1, channels=>1, bits=>16);
    is($im_o, undef, "integer overflow check - scanline");
    cmp_ok(Imager->errstr, '=~',
           qr/integer overflow calculating scanline allocation/,
           "check error message");
  }
}

{ # check the channel mask function
  
  my $im = Imager->new(xsize => 10, ysize=>10, bits=>16);

  mask_tests($im, 1.0/65535);
}

{ # convert to rgb16
  my $im = test_image();
  my $im16 = $im->to_rgb16;
  print "# check conversion to 16 bit\n";
  is($im16->bits, 16, "check bits");
  is_image($im, $im16, "check image data matches");
}

{ # empty image handling
  my $im = Imager->new;
  ok($im, "make empty image");
  ok(!$im->to_rgb16, "convert empty image to 16-bit");
  is($im->errstr, "to_rgb16: empty input image", "check message");
}

{ # bounds checks
  my $im = Imager->new(xsize => 10, ysize => 10, bits => 16);
  image_bounds_checks($im);
}

{
  my $im = Imager->new(xsize => 10, ysize => 10, bits => 16, channels => 3);
  my @wr_samples = map int(rand 65536), 1..30;
  is($im->setsamples('y' => 1, data => \@wr_samples, type => '16bit'),
     30, "write 16-bit to OO image")
    or print "# ", $im->errstr, "\n";
  my @samples;
  is($im->getsamples(y => 1, target => \@samples, type => '16bit'),
     30, "read 16-bit from OO image")
    or print "# ", $im->errstr, "\n";
  is_deeply(\@wr_samples, \@samples, "check it matches");
}

my $psamp_outside_error = "Image position outside of image";
{ # psamp
  print "# psamp\n";
  my $imraw = Imager::i_img_16_new(10, 10, 3);
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
    is(_get_error(), $psamp_outside_error,
       "check error message");
    is(Imager::i_psamp($imraw, 0, 10, undef, [ 0, 0, 0 ]), undef,
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
  print "# end psamp tests\n";
}

{ # psampf
  print "# psampf\n";
  my $imraw = Imager::i_img_16_new(10, 10, 3);
  {
    is(Imager::i_psampf($imraw, 0, 2, undef, [ 1, 0.5, 0.25 ]), 3,
       "i_psampf def channels, 3 samples");
    is_color3(Imager::i_get_pixel($imraw, 0, 2), 255, 127, 64,
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
    is_color3(Imager::i_get_pixel($imraw, 2, 4), 255, 127, 0,
	      "check first color written");
    is_color3(Imager::i_get_pixel($imraw, 3, 4), 64, 32, 0,
	      "check second color written");
    is(Imager::i_psampf($imraw, 0, 5, [ 0, 1, 2 ], [ (0.5, 0.25, 0.125) x 10 ]), 30,
       "write a full row");
    is_deeply([ Imager::i_gsamp($imraw, 0, 10, 5, [ 0, 1, 2 ]) ],
	      [ (127, 64, 32) x 10 ],
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
    is(_get_error(), $psamp_outside_error,
       "check error message");
    is(Imager::i_psampf($imraw, 0, 10, undef, [ 0, 0, 0 ]), undef,
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
  print "# end psampf tests\n";
}

Imager->close_log;

unless ($ENV{IMAGER_KEEP_FILES}) {
  unlink "testout/t021sixteen.log";
}

sub _get_error {
  my @errors = Imager::i_errors();
  return join(": ", map $_->[0], @errors);
}

