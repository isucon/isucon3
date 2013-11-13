#!perl -w
use strict;
use blib;
use lib '../t';
use Imager;
use Test::More tests => 3;

BEGIN { use_ok('Imager::Filter::Mandelbrot') }

my $im = Imager->new(xsize=>100, ysize=>100);
SKIP:
{
  ok($im->filter(type=>'mandelbrot'),
     "try filter")
    or print "# ", $im->errstr, "\n";
  ok($im->write(file => '../testout/t00mandel.ppm'),
     "save result");
}
