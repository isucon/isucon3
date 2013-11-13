#!perl -w
use strict;
use Test::More tests => 15;
use Imager;
use Imager::Test qw(is_image);

-d "testout" or mkdir "testout";

{ # flood_fill wouldn't fill to the right if the area was just a
  # single scan-line
  my $im = Imager->new(xsize => 5, ysize => 3);
  ok($im, "make flood_fill test image");
  ok($im->line(x1 => 0, y1 => 1, x2 => 4, y2 => 1, color => "white"),
     "create fill area");
  ok($im->flood_fill(x => 3, y => 1, color => "blue"),
     "fill it");
  my $cmp = Imager->new(xsize => 5, ysize => 3);
  ok($cmp, "make test image");
  ok($cmp->line(x1 => 0, y1 => 1, x2 => 4, y2 => 1, color => "blue"),
     "synthezied filled area");
  is_image($im, $cmp, "flood_fill filled horizontal line");
}

SKIP:
{ # flood_fill won't fill entire line below if line above is shorter
  my $im = Imager->new(file => "testimg/filltest.ppm");
  ok($im, "Load test image")
    or skip("Couldn't load test image: " . Imager->errstr, 3);

  # fill from first bad place
  my $fill1 = $im->copy;
  ok($fill1->flood_fill(x => 8, y => 2, color => "#000000"),
     "fill from a top most spot");
  my $cmp = Imager->new(xsize => $im->getwidth, ysize => $im->getheight);
  is_image($fill1, $cmp, "check it filled the lot");
  ok($fill1->write(file => "testout/t22fill1.ppm"), "save");

  # second bad place
  my $fill2 = $im->copy;
  ok($fill2->flood_fill(x => 17, y => 3, color => "#000000"),
     "fill from not quite top most spot");
  is_image($fill2, $cmp, "check it filled the lot");
  ok($fill2->write(file => "testout/t22fill2.ppm"), "save");
}

{ # verticals
  my $im = vimage("FFFFFF");
  my $cmp = vimage("FF0000");

  ok($im->flood_fill(x => 4, y=> 8, color => "FF0000"),
     "fill at bottom of vertical well");
  is_image($im, $cmp, "check the result");
}

unless ($ENV{IMAGER_KEEP_FILES}) {
  unlink "testout/t22fill1.ppm";
  unlink "testout/t22fill2.ppm";
}

# make a vertical test image
sub vimage {
  my $c = shift;

  my $im = Imager->new(xsize => 10, ysize => 10);
  $im->line(x1 => 1, y1 => 1, x2 => 8, y2 => 1, color => $c);
  $im->line(x1 => 4, y1 => 2, x2 => 4, y2 => 8, color => $c);

  return $im;
}
