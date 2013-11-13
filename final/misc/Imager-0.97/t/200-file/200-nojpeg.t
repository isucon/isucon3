#!perl -w
use strict;
use Test::More;
use Imager qw(:all);

-d "testout" or mkdir "testout";

Imager->open_log(log => "testout/t101jpeg.log");

$Imager::formats{"jpeg"}
  and plan skip_all => "have jpeg support - this tests the lack of it";

plan tests => 6;

my $im = Imager->new;
ok(!$im->read(file=>"testimg/base.jpg"), "should fail to read jpeg");
cmp_ok($im->errstr, '=~', qr/format 'jpeg' not supported/, "check no jpeg message");
$im = Imager->new(xsize=>2, ysize=>2);
ok(!$im->write(file=>"testout/nojpeg.jpg"), "should fail to write jpeg");
cmp_ok($im->errstr, '=~', qr/format 'jpeg' not supported/, "check no jpeg message");
ok(!grep($_ eq 'jpeg', Imager->read_types), "check jpeg not in read types");
ok(!grep($_ eq 'jpeg', Imager->write_types), "check jpeg not in write types");

Imager->close_log;

unless ($ENV{IMAGER_KEEP_FILES}) {
  unlink "testout/t101jpeg.log";
}
