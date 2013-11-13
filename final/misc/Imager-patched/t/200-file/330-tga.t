#!perl -w
use Imager qw(:all);
use strict;
use Test::More tests=>68;
use Imager::Test qw(is_color4 is_image test_image);

-d "testout" or mkdir "testout";

init_log("testout/t108tga.log",1);

my $img = create_test_image();
my $base_diff = 0;

write_test($img, "testout/t108_24bit.tga", 0, 0, "");
write_test($img, "testout/t108_24bit_rle.tga", 0, 1, "");
write_test($img, "testout/t108_15bit.tga", 1, 1, "");
write_test($img, "testout/t108_15bit_rle.tga", 1, 1, "");

# 'webmap' is noticably faster than the default
my $im8 = Imager::i_img_to_pal($img, { make_colors=>'webmap',
				       translate=>'errdiff'});

write_test($im8, "testout/t108_8bit.tga", 0, 0, "");
write_test($im8, "testout/t108_8bit_rle.tga", 0, 1, "");
write_test($im8, "testout/t108_8_15bit.tga", 1, 0, "");
write_test($im8, "testout/t108_8_15bit_rle.tga", 1, 1, "");


# use a fixed palette so we get reproducible results for the compressed
# version

my @bit4 = map { NC($_) }
  qw(605844 966600 0148b2 00f800 bf0a33 5e009e
     2ead1b 0000f8 004b01 fd0000 0e1695 000002);

my @bit1 = (NC(0, 0, 0), NC(176, 160, 144));

my $im4 = Imager::i_img_to_pal($img, { colors=>\@bit4,
				       make_colors=>'none' });

my $im1 = Imager::i_img_to_pal($img, { colors=>\@bit1,
				       make_colors=>'none',
				       translate=>'errdiff' });

write_test($im4, "testout/t108_4bit.tga", 0, 1, "");
write_test($im1, "testout/t108_1bit.tga", 0, 1, "This is a comment!");

read_test("testout/t108_24bit.tga", $img);
read_test("testout/t108_8bit.tga",  $im8);
read_test("testout/t108_4bit.tga",  $im4);
read_test("testout/t108_1bit.tga",  $im1);

# the following might have slight differences

$base_diff = i_img_diff($img, $im8) * 2;

print "# base difference $base_diff\n";

my $imoo = Imager->new;
ok($imoo->read(file=>'testout/t108_24bit.tga'),
   "OO read image")
  or print "# ",$imoo->errstr,"\n";

ok($imoo->write(file=>'testout/t108_oo.tga'),
   "OO write image")
  or print "# ",$imoo->errstr,"\n";

my ($type) = $imoo->tags(name=>'i_format');
is($type, 'tga', "check i_format tag");

# in 0.44 and earlier, reading an image with an idstring of 128 or more
# bytes would result in an allocation error, if the platform char type
# was signed
$imoo = Imager->new;
ok($imoo->read(file=>'testimg/longid.tga'), "read long id image");
my ($id) = $imoo->tags(name=>'tga_idstring');
is($id, "X" x 128, "check tga_idstring tag");
my ($bitspp) = $imoo->tags(name=>'tga_bitspp');
is($bitspp, 24, "check tga_bitspp tag");
my ($compressed) = $imoo->tags(name=>'compressed');
is($compressed, 1, "check compressed tag");

{ # check file limits are checked
  my $limit_file = "testout/t108_24bit.tga";
  ok(Imager->set_file_limits(reset=>1, width=>149), "set width limit 149");
  my $im = Imager->new;
  ok(!$im->read(file=>$limit_file),
     "should fail read due to size limits");
  print "# ",$im->errstr,"\n";
  like($im->errstr, qr/image width/, "check message");
  
  ok(Imager->set_file_limits(reset=>1, height=>149), "set height limit 149");
  ok(!$im->read(file=>$limit_file),
     "should fail read due to size limits");
  print "# ",$im->errstr,"\n";
  like($im->errstr, qr/image height/, "check message");
  
  ok(Imager->set_file_limits(reset=>1, width=>150), "set width limit 150");
  ok($im->read(file=>$limit_file),
     "should succeed - just inside width limit");
  ok(Imager->set_file_limits(reset=>1, height=>150), "set height limit 150");
  ok($im->read(file=>$limit_file),
     "should succeed - just inside height limit");
  
  # 150 x 150 x 3 channel image uses 67500 bytes
  ok(Imager->set_file_limits(reset=>1, bytes=>67499),
     "set bytes limit 67499");
  ok(!$im->read(file=>$limit_file),
     "should fail - too many bytes");
  print "# ",$im->errstr,"\n";
  like($im->errstr, qr/storage size/, "check error message");
  ok(Imager->set_file_limits(reset=>1, bytes=>67500),
     "set bytes limit 67500");
  ok($im->read(file=>$limit_file),
     "should succeed - just inside bytes limit");
  Imager->set_file_limits(reset=>1);
}

{ # Issue # 18397
  # the issue is for 4 channel images to jpeg, but 2 channel images have
  # a similar problem on tga
  my $im = Imager->new(xsize=>100, ysize=>100, channels => 2);
  my $data;
  ok(!$im->write(data => \$data, type=>'tga'),
     "check failure of writing a 2 channel image");
  is($im->errstr, "Cannot store 2 channel image in targa format",
     "check the error message");
}

{
  ok(grep($_ eq 'tga', Imager->read_types), "check tga in read types");
  ok(grep($_ eq 'tga', Imager->write_types), "check tga in write types");
}

{ # Issue #32926
  # a sample image was read as all transparent
  # it had bitsperpixel = 16 and atribute channel set to 1, so it
  # should have an alpha channel.
  # So we'll do what the gimp does and treat a zero value as opaque.

  my $im = Imager->new;
  ok($im->read(file => 'testimg/alpha16.tga'),
     "read 16-bit/pixel alpha image");
  my $c1 = $im->getpixel('x' => 0, 'y' => 0);
  is_color4($c1, 0, 0, 0, 0, "check transparent pixel");
  my $c2 = $im->getpixel('x' => 19, 'y' => 0);
  is_color4($c2, 255, 0, 0, 255, "check opaque pixel");

  # since this has an effect on writing too, write,it, read it, check it
  my $data;
  ok($im->write(data => \$data, type => 'tga', wierdpack => 1),
     "write 16-bit/pixel w/alpha");
  my $im2 = Imager->new;
  ok($im2->read(data => $data), "read it back");
  is_image($im, $im2, "check they match");
}

{ # prior to the types re-work we treated the tga xsize/ysize as
  # signed short, which is wrong
 SKIP:
  {
    my $im = Imager->new(xsize => 40960, ysize => 1);
    my $data;
    ok($im->write(data => \$data, type => "tga"),
       "write a wide (but not too wide) image out");
    my $im2 = Imager->new(data => $data);
    ok($im2, "read it back in")
      or skip("Couldn't read the wide image", 2);
    is($im2->getwidth, 40960, "make sure the width survived the trip");
    is($im2->getheight, 1, "make sure the height survived the trip");
  }

 SKIP:
  {
    my $im = Imager->new(xsize => 1, ysize => 40960);
    my $data;
    ok($im->write(data => \$data, type => "tga"),
       "write a tall (but not too tall) image out");
    my $im2 = Imager->new(data => $data);
    ok($im2, "read it back in")
      or skip("Couldn't read the tall image", 2);
    is($im2->getwidth, 1, "make sure the width survived the trip");
    is($im2->getheight, 40960, "make sure the height survived the trip");
  }
}

{
  # TGA files are limited to 0xFFFF x 0xFFFF pixels
  my $max_dim = 0xFFFF;
  {
    my $im = Imager->new(xsize => 1+$max_dim, ysize => 1);
    my $data = '';
    ok(!$im->write(data => \$data, type => "tga"),
       "fail to write too wide an image");
    is($im->errstr, "image too large for TGA",
       "check error message");
  }
 SKIP:
  {
    my $im = Imager->new(xsize => $max_dim, ysize => 1);
    $im->box(fill => { hatch => "check4x4" });
    my $data = '';
    ok($im->write(data => \$data, type => "tga"),
       "write image at width limit")
      or print "# ", $im->errstr, "\n";
    my $im2 = Imager->new(data => $data, ftype => "tga");
    ok($im2, "read it ok")
      or skip("cannot load the wide image", 1);
    is($im->getwidth, $max_dim, "check width");
    is($im->getheight, 1, "check height");
  }
  {
    my $im = Imager->new(xsize => 1, ysize => 1+$max_dim);
    my $data = '';
    ok(!$im->write(data => \$data, type => "tga"),
       "fail to write too tall an image");
    is($im->errstr, "image too large for TGA",
       "check error message");
  }
 SKIP:
  {
    my $im = Imager->new(xsize => 1, ysize => $max_dim);
    $im->box(fill => { hatch => "check2x2" });
    my $data = '';
    ok($im->write(data => \$data, type => "tga"),
       "write image at width limit");
    my $im2 = Imager->new(data => $data, ftype => "tga");
    ok($im2, "read it ok")
      or skip("cannot load the wide image", 1);
    is($im->getwidth, 1, "check width");
    is($im->getheight, $max_dim, "check height");
  }
}

{ # check close failures are handled correctly
  my $im = test_image();
  my $fail_close = sub {
    Imager::i_push_error(0, "synthetic close failure");
    return 0;
  };
  ok(!$im->write(type => "tga", callback => sub { 1 },
		 closecb => $fail_close),
     "check failing close fails");
    like($im->errstr, qr/synthetic close failure/,
	 "check error message");
}

sub write_test {
  my ($im, $filename, $wierdpack, $compress, $idstring) = @_;
  local *FH;

  if (open FH, "> $filename") {
    binmode FH;
    my $IO = Imager::io_new_fd(fileno(FH));
    ok(Imager::i_writetga_wiol($im, $IO, $wierdpack, $compress, $idstring),
       "write $filename")
      or print "# ",Imager->_error_as_msg(),"\n";
    undef $IO;
    close FH;
  } else {
    fail("write $filename: open failed: $!");
  }
}


sub read_test {
  my ($filename, $im, %tags) = @_;
  local *FH;

  if (open FH, "< $filename") {
    binmode FH;
    my $IO = Imager::io_new_fd(fileno(FH));
    my $im_read = Imager::i_readtga_wiol($IO,-1);
    if ($im_read) {
      my $diff = i_img_diff($im, $im_read);
      cmp_ok($diff, '<=', $base_diff,
	     "check read image vs original");
    } else {
      fail("read $filename ".Imager->_error_as_msg());
    }
    undef $IO;
    close FH;
  } else {
    fail("read $filename, open failure: $!");
  }
}

sub create_test_image {

  my $green  = i_color_new(0,255,0,255);
  my $blue   = i_color_new(0,0,255,255);
  my $red    = i_color_new(255,0,0,255);

  my $img    = Imager::ImgRaw::new(150,150,3);

  i_box_filled($img, 70, 25, 130, 125, $green);
  i_box_filled($img, 20, 25,  80, 125, $blue);
  i_arc($img, 75, 75, 30, 0, 361, $red);
  i_conv($img, [0.1, 0.2, 0.4, 0.2, 0.1]);

  return $img;
}
