#!perl -w
use Imager;
use Test::More tests => 22;
use Imager::Test qw(is_image);

{
  # GIF files are limited to 0xFFFF x 0xFFFF pixels
  {
    my $im = Imager->new(xsize => 0x10000, ysize => 1);
    my $data = '';
    ok(!$im->write(data => \$data, type => "gif"),
       "fail to write too wide an image");
    is($im->errstr, "image too large for GIF",
       "check error message");
  }
 SKIP:
  {
    my $im = Imager->new(xsize => 0xFFFF, ysize => 1);
    $im->box(fill => { hatch => "check4x4" });
    my $data = '';
    ok($im->write(data => \$data, type => "gif"),
       "write image at width limit");
    my $im2 = Imager->new(data => $data, ftype => "gif");
    ok($im2, "read it ok")
      or skip("cannot load the wide image", 1);
    is_image($im, $im2, "check we read what we wrote");
    is($im->getwidth, 0xffff, "check width");
    is($im->getheight, 1, "check height");
  }
  {
    my $im = Imager->new(xsize => 1, ysize => 0x10000);
    my $data = '';
    ok(!$im->write(data => \$data, type => "gif"),
       "fail to write too tall an image");
    is($im->errstr, "image too large for GIF",
       "check error message");
  }
 SKIP:
  {
    my $im = Imager->new(xsize => 1, ysize => 0xFFFF);
    $im->box(fill => { hatch => "check2x2" });
    my $data = '';
    ok($im->write(data => \$data, type => "gif"),
       "write image at width limit");
    my $im2 = Imager->new(data => $data, ftype => "gif");
    ok($im2, "read it ok")
      or skip("cannot load the wide image", 1);
    is_image($im, $im2, "check we read what we wrote");
    is($im->getwidth, 1, "check width");
    is($im->getheight, 0xffff, "check height");
  }
}
{
  my $im = Imager->new(xsize => 1, ysize => 1);
  $im->settag(name => "gif_screen_width", value => 65536);
  my $data = '';
  ok(!$im->write(data => \$data, type => "gif"),
     "save a with a large explicit screen width should fail");
  is($im->errstr, "screen size too large for GIF",
     "check error message");
}
{
  my $im = Imager->new(xsize => 0x8000, ysize => 1);
  $im->settag(name => "gif_left", value => 32768);
  my $data = '';
  ok(!$im->write(data => \$data, type => "gif"),
     "save a with a large implicit screen width should fail");
  is($im->errstr, "screen size too large for GIF",
     "check error message");
}
{
  my $im = Imager->new(xsize => 1, ysize => 1);
  $im->settag(name => "gif_screen_height", value => 65536);
  my $data = '';
  ok(!$im->write(data => \$data, type => "gif"),
     "save a with a large explicit screen height should fail");
  is($im->errstr, "screen size too large for GIF",
     "check error message");
}
{
  my $im = Imager->new(xsize => 1, ysize => 0x8000);
  $im->settag(name => "gif_top", value => 32768);
  my $data = '';
  ok(!$im->write(data => \$data, type => "gif"),
     "save a with a large implicit screen height should fail");
  is($im->errstr, "screen size too large for GIF",
     "check error message");
}
