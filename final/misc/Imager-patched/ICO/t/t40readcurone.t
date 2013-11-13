#!perl -w
use strict;
use Test::More tests => 1;
use Imager;

# checks that we load the CUR handler automatically
my $im = Imager->new;
ok($im->read(file => 'testimg/pal43232.cur'),
   "check that cursor reader loaded correctly for singles")
  or print "# ", $im->errstr, "\n";
