#!perl -w
use strict;
use Test::More;
use Imager qw(:all);

$Imager::formats{"tiff"}
  and plan skip_all => "tiff support available - this tests the lack of it";

plan tests => 12;

my $im = Imager->new;

ok(!$im->read(file=>"TIFF/testimg/comp4.tif"), "should fail to read tif");
cmp_ok($im->errstr, '=~', "format 'tiff' not supported",
       "check no tiff message");

ok(!$im->read_multi(file => "TIFF/testimg/comp4.tif"),
   "should fail to read multi tiff");
cmp_ok($im->errstr, '=~', "format 'tiff' not supported",
       "check no tiff message");

$im = Imager->new(xsize=>2, ysize=>2);

ok(!$im->write(file=>"testout/notiff.tif"), "should fail to write tiff");
cmp_ok($im->errstr, '=~', "format 'tiff' not supported",
       "check no tiff message");
ok(!-e "testout/notiff.tif", "file shouldn't be created");

ok(!Imager->write_multi({file=>"testout/notiff.tif"}, $im, $im),
   "should fail to write multi tiff");
cmp_ok($im->errstr, '=~', "format 'tiff' not supported",
       "check no tiff message");
ok(!-e "testout/notiff.tif", "file shouldn't be created");

ok(!grep($_ eq 'tiff', Imager->read_types), "check tiff not in read types");
ok(!grep($_ eq 'tiff', Imager->write_types), "check tiff not in write types");
