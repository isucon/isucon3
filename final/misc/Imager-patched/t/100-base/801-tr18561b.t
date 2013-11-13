#!perl -w
# variant on the code that produces 18561
# the old _color() code could return floating colors in some cases
# but in most cases the caller couldn't handle it
use strict;
use Test::More tests => 1;
eval {
  use Imager;
  use Imager::Color::Float; # prevent the actual 18561 crash
  my $i = Imager->new(
	  xsize => 50,
	  ysize => 50,
  );
  $i->line(x1 => 0, y1 => 0, x2 => 99, y2=>99, color => [ 0, 0, 0 ]);
};
ok(!$@, "shouldn't crash")
  or print "# $@\n";
