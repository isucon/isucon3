#!perl -w
use strict;
use Imager;
use Test::More tests => 31;
use Imager::Test qw/test_image test_image_double is_image/;

my $test_im = test_image;
my $test_im_dbl = test_image_double;

{
  # split out channels and put it back together
  my $red = Imager->combine(src => [ $test_im ]);
  ok($red, "extracted the red channel");
  is($red->getchannels, 1, "red should be a single channel");
  my $green = Imager->combine(src => [ $test_im ], channels => [ 1 ]);
  ok($green, "extracted the green channel");
  is($green->getchannels, 1, "green should be a single channel");
  my $blue = $test_im->convert(preset => "blue");
  ok($blue, "extracted blue (via convert)");

  # put them back together
  my $combined = Imager->combine(src => [ $red, $green, $blue ]);
  is($combined->getchannels, 3, "check we got a three channel image");
  is_image($combined, $test_im, "presto! check it's the same");
}

{
  # no src
  ok(!Imager->combine(), "no src");
  is(Imager->errstr, "src parameter missing", "check message");
}

{
  # bad image error
  my $im = Imager->new;
  ok(!Imager->combine(src => [ $im ]), "empty image");
  is(Imager->errstr, "combine: empty input image (src->[0])",
     "check message");
}

{
  # not an image
  my $im = {};
  ok(!Imager->combine(src => [ $im ]), "not an image");
  is(Imager->errstr, "src must contain image objects", "check message");
}

{
  # no images
  ok(!Imager->combine(src => []), "no images");
  is(Imager->errstr, "At least one image must be supplied",
     "check message");
}

{
  # too many images
  ok(!Imager->combine(src => [ ($test_im) x 5 ]), "too many source images");
  is(Imager->errstr, "Maximum of 4 channels, you supplied 5",
     "check message");
}

{
  # negative channel
  ok(!Imager->combine(src => [ $test_im ], channels => [ -1 ]),
     "negative channel");
  is(Imager->errstr, "Channel numbers must be zero or positive",
     "check message");
}

{
  # channel too high
  ok(!Imager->combine(src => [ $test_im ], channels => [ 3 ]),
     "too high channel");
  is(Imager->errstr, "Channel 3 for image 0 is too high (3 channels)",
     "check message");
}

{
  # make sure we get the higher of the bits
  my $out = Imager->combine(src => [ $test_im, $test_im_dbl ]);
  ok($out, "make from 8 and double/sample images");
  is($out->bits, "double", "check output bits");
}

{
  # check high-bit processing
  # split out channels and put it back together
  my $red = Imager->combine(src => [ $test_im_dbl ]);
  ok($red, "extracted the red channel");
  is($red->getchannels, 1, "red should be a single channel");
  my $green = Imager->combine(src => [ $test_im_dbl ], channels => [ 1 ]);
  ok($green, "extracted the green channel");
  is($green->getchannels, 1, "green should be a single channel");
  my $blue = $test_im_dbl->convert(preset => "blue");
  ok($blue, "extracted blue (via convert)");

  # put them back together
  my $combined = Imager->combine(src => [ $red, $green, $blue ]);
  is($combined->getchannels, 3, "check we got a three channel image");
  is_image($combined, $test_im_dbl, "presto! check it's the same");
  is($combined->bits, "double", "and we got a double image output");
}
