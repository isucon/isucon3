#!perl -w
use strict;
use Test::More tests => 10;
use Imager::Test qw(is_image);

-d "testout" or mkdir "testout";

Imager::init("log"=>'testout/t68map.log');

use Imager qw(:all :handy);

my $imbase = Imager::ImgRaw::new(200,300,3);


my @map1 = map { int($_/2) } 0..255;
my @map2 = map { 255-int($_/2) } 0..255;
my @map3 = 0..255;
my @maps = 0..24;
my @mapl = 0..400;

my $tst = 1;

ok(i_map($imbase, [ [],     [],     \@map1 ]), "map1 in ch 3");
ok(i_map($imbase, [ \@map1, \@map1, \@map1 ]), "map1 in ch1-3");

ok(i_map($imbase, [ \@map1, \@map2, \@map3 ]), "map1-3 in ch 1-3");

ok(i_map($imbase, [ \@maps, \@mapl, \@map3 ]), "incomplete maps");

# test the highlevel interface
# currently this requires visual inspection of the output files

SKIP: {
  my $im = Imager->new;
  $im->read(file=>'testimg/scale.ppm')
    or skip "Cannot load test image testimg/scale.ppm", 2;

  ok( $im->map(red=>\@map1, green=>\@map2, blue=>\@map3),
      "test OO interface (maps by color)");
  ok( $im->map(maps=>[\@map1, [], \@map2]),
      "test OO interface (maps by maps)");
}

{
  my $empty = Imager->new;
  ok(!$empty->map(maps => [ \@map1, \@map2, \@map3 ]),
     "can't map an empty image");
  is($empty->errstr, "map: empty input image", "check error message");
}

{ # a real map test
  my $im = Imager->new(xsize => 10, ysize => 10);
  $im->box(filled => 1, color => [ 255, 128, 128 ], xmax => 4, ymax => 4);
  $im->box(filled => 1, color => [ 0, 255, 0 ], xmin => 5);

  my $cmp = Imager->new(xsize => 10, ysize => 10);
  $cmp->box(filled => 1, color => [ 127, 64, 64 ], xmax => 4, ymax => 4);
  $cmp->box(filled => 1, color => [ 0, 127, 0 ], xmin => 5);
  my @map = ( map int $_/2, 0 .. 255 );
  my $out = $im->map(maps => [ \@map, \@map, \@map ]);
  ok($out, "map()");
  is_image($out, $cmp, "test map output");
}
