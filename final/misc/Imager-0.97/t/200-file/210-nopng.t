#!perl -w
use strict;
use Imager qw(:all);
use Test::More;

$Imager::formats{"png"}
  and plan skip_all => "png available, and this tests the lack of it";

plan tests => 6;

my $im = Imager->new;
ok(!$im->read(file=>"testimg/test.png"), "should fail to read png");
cmp_ok($im->errstr, '=~', "format 'png' not supported", "check no png message");
$im = Imager->new(xsize=>2, ysize=>2);
ok(!$im->write(file=>"testout/nopng.png"), "should fail to write png");
cmp_ok($im->errstr, '=~', "format 'png' not supported", "check no png message");
ok(!grep($_ eq 'png', Imager->read_types), "check png not in read types");
ok(!grep($_ eq 'png', Imager->write_types), "check png not in write types");

