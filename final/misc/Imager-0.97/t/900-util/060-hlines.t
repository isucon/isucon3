#!perl -w
use strict;
use Test::More;
use Imager;

# this script tests an internal set of functions for Imager, they 
# aren't intended to be used at the perl level.
# these functions aren't present in all Imager builds

unless (Imager::Internal::Hlines::testing()) {
  plan skip_all => 'Imager not built to run this test';
}

plan tests => 17;

my $hline = Imager::Internal::Hlines::new(0, 100, 0, 100);
my $base_text = 'start_y: 0 limit_y: 100 start_x: 0 limit_x: 100';
ok($hline, "made hline");
is($hline->dump, "$base_text\n", "check values");
$hline->add(5, -5, 7);
is($hline->dump, <<EOS, "check (-5, 7) added");
$base_text
 5 (1): [0, 2)
EOS
$hline->add(5, 8, 4);
is($hline->dump, <<EOS, "check (8, 4) added");
$base_text
 5 (2): [0, 2) [8, 12)
EOS
$hline->add(5, 3, 3);
is($hline->dump, <<EOS, "check (3, 3) added");
$base_text
 5 (3): [0, 2) [3, 6) [8, 12)
EOS
$hline->add(5, 2, 6);
is($hline->dump, <<EOS, "check (2, 6) added");
$base_text
 5 (1): [0, 12)
EOS
# adding out of range should do nothing
my $current = <<EOS;
$base_text
 5 (1): [0, 12)
EOS
$hline->add(6, -5, 5);
is($hline->dump, $current, "check (6, -5, 5) not added");
$hline->add(6, 100, 5);
is($hline->dump, $current, "check (6, 100, 5) not added");
$hline->add(-1, 5, 2);
is($hline->dump, $current, "check (-1, 5, 2) not added");
$hline->add(100, 5, 2);
is($hline->dump, $current, "check (10, 5, 2) not added");

# overlapped add check
$hline->add(6, 2, 6);
$hline->add(6, 3, 4);
is($hline->dump, <<EOS, "check internal overlap merged");
$base_text
 5 (1): [0, 12)
 6 (1): [2, 8)
EOS

# white box test: try to force reallocation of an entry
for my $i (0..20) {
  $hline->add(7, $i*2, 1);
}
is($hline->dump, <<EOS, "lots of segments");
$base_text
 5 (1): [0, 12)
 6 (1): [2, 8)
 7 (21): [0, 1) [2, 3) [4, 5) [6, 7) [8, 9) [10, 11) [12, 13) [14, 15) [16, 17) [18, 19) [20, 21) [22, 23) [24, 25) [26, 27) [28, 29) [30, 31) [32, 33) [34, 35) [36, 37) [38, 39) [40, 41)
EOS
# now merge them
$hline->add(7, 1, 39);
is($hline->dump, <<EOS, "merge lots of segments");
$base_text
 5 (1): [0, 12)
 6 (1): [2, 8)
 7 (1): [0, 41)
EOS

# clean object
$hline = Imager::Internal::Hlines::new(50, 50, 50, 50);
$base_text = 'start_y: 50 limit_y: 100 start_x: 50 limit_x: 100';

# left merge
$hline->add(51, 45, 10);
$hline->add(51, 55, 4);
is($hline->dump, <<EOS, "left merge");
$base_text
 51 (1): [50, 59)
EOS

# right merge
$hline->add(52, 90, 5);
$hline->add(52, 87, 5);
is($hline->dump, <<EOS, "right merge");
$base_text
 51 (1): [50, 59)
 52 (1): [87, 95)
EOS

undef $hline;

{ # test the image constructor
  my $im = Imager->new(xsize => 50, ysize => 60);
  my $hl = Imager::Internal::Hlines::new_img($im->{IMG});
  ok($hl, "make hlines object from image");
  is($hl->dump, "start_y: 0 limit_y: 60 start_x: 0 limit_x: 50\n",
     "check initialized properly");
}
