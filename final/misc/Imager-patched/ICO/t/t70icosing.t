#!perl -w
use strict;
use Test::More tests => 1;
use Imager;
use Imager::Test qw(test_image);

-d "testout" or mkdir "testout";
# checks that we load the ICO write handler automatically

my $img = test_image();
ok($img->write(file => 'testout/icosing.ico'),
   "write ico with autoload")
  or print "# ",$img->errstr,"\n";
