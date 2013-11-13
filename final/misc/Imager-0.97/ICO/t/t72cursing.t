#!perl -w
use strict;
use Test::More tests => 1;
use Imager;
use Imager::Test qw(test_image);

-d "testout" or mkdir "testout";

# checks that we load the CUR write handler automatically
my $img = test_image();
ok($img->write(file => 'testout/cursing.cur'),
   "write cur with autoload")
  or print "# ",$img->errstr,"\n";
