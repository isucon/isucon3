#!perl -w
use strict;
use Test::More tests => 1;
use Imager;

# checks that we load the CUR handler automatically for multiple image reads
my @im = Imager->read_multi(file=>'testimg/pal43232.cur');
is(scalar(@im), 1,
   "check that cursor reader loaded correctly for singles")
  or print "# ", Imager->errstr, "\n";
