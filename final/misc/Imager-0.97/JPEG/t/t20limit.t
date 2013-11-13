#!perl -w
use strict;
use Imager;
use Test::More tests => 12;

my $max_dim = 65500;

{
  # JPEG files are limited to 0xFFFF x 0xFFFF pixels
  # but libjpeg sets the limit lower to avoid overflows
  {
    my $im = Imager->new(xsize => 1+$max_dim, ysize => 1);
    my $data = '';
    ok(!$im->write(data => \$data, type => "jpeg"),
       "fail to write too wide an image");
    is($im->errstr, "image too large for JPEG",
       "check error message");
  }
 SKIP:
  {
    my $im = Imager->new(xsize => $max_dim, ysize => 1);
    $im->box(fill => { hatch => "check4x4" });
    my $data = '';
    ok($im->write(data => \$data, type => "jpeg"),
       "write image at width limit")
      or print "# ", $im->errstr, "\n";
    my $im2 = Imager->new(data => $data, ftype => "jpeg");
    ok($im2, "read it ok")
      or skip("cannot load the wide image", 1);
    is($im->getwidth, $max_dim, "check width");
    is($im->getheight, 1, "check height");
  }
  {
    my $im = Imager->new(xsize => 1, ysize => 1+$max_dim);
    my $data = '';
    ok(!$im->write(data => \$data, type => "jpeg"),
       "fail to write too tall an image");
    is($im->errstr, "image too large for JPEG",
       "check error message");
  }
 SKIP:
  {
    my $im = Imager->new(xsize => 1, ysize => $max_dim);
    $im->box(fill => { hatch => "check2x2" });
    my $data = '';
    ok($im->write(data => \$data, type => "jpeg"),
       "write image at width limit");
    my $im2 = Imager->new(data => $data, ftype => "jpeg");
    ok($im2, "read it ok")
      or skip("cannot load the wide image", 1);
    is($im->getwidth, 1, "check width");
    is($im->getheight, $max_dim, "check height");
  }
}
