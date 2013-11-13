#!perl -w
use strict;
use blib;
use Imager;
use Test::More tests => 4;

BEGIN { use_ok('Imager::Filter::DynTest') }

my $im = Imager->new;
SKIP:
{
  ok($im->read(file => '../testimg/penguin-base.ppm'), "load source image")
    or skip("couldn't load work image", 2);
  ok($im->filter(type=>'lin_stretch', a => 50, b => 200),
     "try filter")
    or print "# ", $im->errstr, "\n";
  ok($im->write(file => '../testout/t00dyntest.ppm'),
     "save result");
}
