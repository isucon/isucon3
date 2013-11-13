#!perl -w
use strict;
$|=1;
use Test::More;
use Imager qw(:all);

$Imager::formats{"gif"}
  and plan skip_all => "gif support available and this tests the lack of it";

plan tests => 12;

my $im = Imager->new;
ok(!$im->read(file=>"GIF/testimg/scale.gif"), "should fail to read gif");
cmp_ok($im->errstr, '=~', "format 'gif' not supported",
       "check no gif message");
ok(!Imager->read_multi(file=>"GIF/testimg/scale.gif"), 
   "should fail to read multi gif");
cmp_ok($im->errstr, '=~', "format 'gif' not supported",
       "check no gif message");

$im = Imager->new(xsize=>2, ysize=>2);

ok(!$im->write(file=>"testout/nogif.gif"), "should fail to write gif");
ok(!-e "testout/nogif.gif", "shouldn't create the file");
cmp_ok($im->errstr, '=~', "format 'gif' not supported",
       "check no gif message");

ok(!Imager->write_multi({file => "testout/nogif.gif"}, $im, $im),
   "should fail to write multi gif");
ok(!-e "testout/nogif.gif", "shouldn't create the file");
cmp_ok($im->errstr, '=~', "format 'gif' not supported",
       "check no gif message");

ok(!grep($_ eq 'gif', Imager->read_types), "check gif not in read types");
ok(!grep($_ eq 'gif', Imager->write_types), "check gif not in write types");
