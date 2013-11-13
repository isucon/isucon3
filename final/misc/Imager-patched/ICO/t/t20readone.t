#!perl -w
use strict;
use Test::More tests => 1;
use Imager;

# checks that we load the ICO handler automatically
my $im = Imager->new;
ok($im->read(file => 'testimg/rgba3232.ico'),
   "check that icon reader loaded correctly for singles")
  or print "# ", $im->errstr, "\n";
