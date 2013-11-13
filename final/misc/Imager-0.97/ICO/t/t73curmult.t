#!perl -w
use strict;
use Test::More tests => 1;
use Imager;
use Imager::Test qw(test_image);

-d "testout" or mkdir "testout";

# checks that we load the CUR write handler automatically
my $img = test_image();
ok(Imager->write_multi({ file => 'testout/icomult.cur' }, $img, $img),
   "write_multi cur with autoload")
  or print "# ",Imager->errstr,"\n";
