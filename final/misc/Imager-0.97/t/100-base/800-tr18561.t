#!perl -w
# regression test for RT issue 18561
# 
use strict;
use Test::More tests => 1;
eval {
  use Imager;
  
  my $i = Imager->new(
          xsize => 50,
	  ysize => 50,
  );
  
  $i->setpixel(
	x => 10,
	y => 10,
	color => [0, 0, 0],
  );
};
ok(!$@, "shouldn't crash")
  or print "# $@\n";
