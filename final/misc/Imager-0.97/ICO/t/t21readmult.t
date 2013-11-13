#!perl -w
use strict;
use Test::More tests => 1;
use Imager;

# checks that we load the ICO handler automatically
my @imgs = Imager->read_multi(file => 'testimg/combo.ico')
  or print "# ",Imager->errstr,"\n";
is(@imgs, 3,
   "check that icon reader loaded correctly for multiples");
