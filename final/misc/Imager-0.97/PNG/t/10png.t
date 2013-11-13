#!perl -w
use strict;
use Imager qw(:all);
use Test::More;
use Imager::Test qw(test_image_raw test_image is_image is_imaged test_image_16 test_image_double);

my $debug_writes = 1;

-d "testout" or mkdir "testout";

init_log("testout/t102png.log",1);

plan tests => 249;

# this loads Imager::File::PNG too
ok($Imager::formats{"png"}, "must have png format");

diag("Library version " . Imager::File::PNG::i_png_lib_version());

my %png_feat = map { $_ => 1 } Imager::File::PNG->features;

my $green  = i_color_new(0,   255, 0,   255);
my $blue   = i_color_new(0,   0,   255, 255);
my $red    = i_color_new(255, 0,   0,   255);

my $img    = test_image_raw();

my $timg = Imager::ImgRaw::new(20, 20, 4);
my $trans = i_color_new(255, 0, 0, 127);
i_box_filled($timg, 0, 0, 20, 20, $green);
i_box_filled($timg, 2, 2, 18, 18, $trans);

Imager::i_tags_add($img, "i_xres", 0, "300", 0);
Imager::i_tags_add($img, "i_yres", 0, undef, 200);
# the following confuses the GIMP
#Imager::i_tags_add($img, "i_aspect_only", 0, undef, 1);
open(FH,">testout/t102.png") || die "cannot open testout/t102.png for writing\n";
binmode(FH);
my $IO = Imager::io_new_fd(fileno(FH));
ok(Imager::File::PNG::i_writepng_wiol($img, $IO), "write")
  or diag(Imager->_error_as_msg());
close(FH);

open(FH,"testout/t102.png") || die "cannot open testout/t102.png\n";
binmode(FH);
$IO = Imager::io_new_fd(fileno(FH));
my $cmpimg = Imager::File::PNG::i_readpng_wiol($IO);
close(FH);
ok($cmpimg, "read png");

print "# png average mean square pixel difference: ",sqrt(i_img_diff($img,$cmpimg))/150*150,"\n";
is(i_img_diff($img, $cmpimg), 0, "compare saved and original images");

my %tags = map { Imager::i_tags_get($cmpimg, $_) }
  0..Imager::i_tags_count($cmpimg) - 1;
ok(abs($tags{i_xres} - 300) < 1, "i_xres: $tags{i_xres}");
ok(abs($tags{i_yres} - 200) < 1, "i_yres: $tags{i_yres}");
is($tags{i_format}, "png", "i_format: $tags{i_format}");

open FH, "> testout/t102_trans.png"
  or die "Cannot open testout/t102_trans.png: $!";
binmode FH;
$IO = Imager::io_new_fd(fileno(FH));
ok(Imager::File::PNG::i_writepng_wiol($timg, $IO), "write tranparent");
close FH;

open FH,"testout/t102_trans.png" 
  or die "cannot open testout/t102_trans.png\n";
binmode(FH);
$IO = Imager::io_new_fd(fileno(FH));
$cmpimg = Imager::File::PNG::i_readpng_wiol($IO);
ok($cmpimg, "read transparent");
close(FH);

print "# png average mean square pixel difference: ",sqrt(i_img_diff($timg,$cmpimg))/150*150,"\n";
is(i_img_diff($timg, $cmpimg), 0, "compare saved and original transparent");

# REGRESSION TEST
# png.c 1.1 would produce an incorrect image when loading images with
# less than 8 bits/pixel with a transparent palette entry
open FH, "< testimg/palette.png"
  or die "cannot open testimg/palette.png: $!\n";
binmode FH;
$IO = Imager::io_new_fd(fileno(FH));
# 1.1 may segfault here (it does with libefence)
my $pimg = Imager::File::PNG::i_readpng_wiol($IO);
ok($pimg, "read transparent paletted image");
close FH;

open FH, "< testimg/palette_out.png"
  or die "cannot open testimg/palette_out.png: $!\n";
binmode FH;
$IO = Imager::io_new_fd(fileno(FH));
my $poimg = Imager::File::PNG::i_readpng_wiol($IO);
ok($poimg, "read palette_out image");
close FH;
if (!is(i_img_diff($pimg, $poimg), 0, "images the same")) {
  print <<EOS;
# this tests a bug in Imager's png.c v1.1
# if also tickles a bug in libpng before 1.0.5, so you may need to
# upgrade libpng
EOS
}

{ # check file limits are checked
  my $limit_file = "testout/t102.png";
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

{ # check if the read_multi fallback works
  my @imgs = Imager->read_multi(file => 'testout/t102.png');
  is(@imgs, 1, "check the image was loaded");
  is(i_img_diff($img, $imgs[0]), 0, "check image matches");
  
  # check the write_multi fallback
  ok(Imager->write_multi({ file => 'testout/t102m.png', type => 'png' }, 
			 @imgs),
       'test write_multi() callback');
  
  # check that we fail if we actually write 2
  ok(!Imager->write_multi({ file => 'testout/t102m.png', type => 'png' }, 
			   @imgs, @imgs),
     'test write_multi() callback failure');
}

{ # check close failures are handled correctly
  my $im = test_image();
  my $fail_close = sub {
    Imager::i_push_error(0, "synthetic close failure");
    print "# closecb called\n";
    return 0;
  };
  ok(!$im->write(type => "png", callback => sub { 1 },
		 closecb => $fail_close),
     "check failing close fails");
    like($im->errstr, qr/synthetic close failure/,
	 "check error message");
}

{
  ok(grep($_ eq 'png', Imager->read_types), "check png in read types");
  ok(grep($_ eq 'png', Imager->write_types), "check png in write types");
}

{ # read error reporting
  my $im = Imager->new;
  ok(!$im->read(file => "testimg/badcrc.png", type => "png"),
     "read png with bad CRC chunk should fail");
  is($im->errstr, "IHDR: CRC error", "check error message");
}

SKIP:
{ # ignoring "benign" errors
  $png_feat{"benign-errors"}
      or skip "libpng not configured for benign error support", 1;
  my $im = Imager->new;
  ok($im->read(file => "testimg/badcrc.png", type => "png",
	       png_ignore_benign_errors => 1),
     "read bad crc with png_ignore_benign_errors");
}

{ # write error reporting
  my $im = test_image();
  ok(!$im->write(type => "png", callback => limited_write(1), buffered => 0),
     "write limited to 1 byte should fail");
  is($im->errstr, "Write error on an iolayer source.: limit reached",
     "check error message");
}

SKIP:
{ # https://sourceforge.net/tracker/?func=detail&aid=3314943&group_id=5624&atid=105624
  # large images
  Imager::File::PNG::i_png_lib_version() >= 10503
      or skip("older libpng limits image sizes", 12);

  {
    my $im = Imager->new(xsize => 1000001, ysize => 1, channels => 1);
    ok($im, "make a wide image");
    my $data;
    ok($im->write(data => \$data, type => "png"),
       "write wide image as png")
      or diag("write wide: " . $im->errstr);
    my $im2 = Imager->new;
    ok($im->read(data => $data, type => "png"),
       "read wide image as png")
      or diag("read wide: " . $im->errstr);
    is($im->getwidth, 1000001, "check width");
    is($im->getheight, 1, "check height");
    is($im->getchannels, 1, "check channels");
  }

  {
    my $im = Imager->new(xsize => 1, ysize => 1000001, channels => 1);
    ok($im, "make a tall image");
    my $data;
    ok($im->write(data => \$data, type => "png"),
       "write wide image as png")
      or diag("write tall: " . $im->errstr);
    my $im2 = Imager->new;
    ok($im->read(data => $data, type => "png"),
       "read tall image as png")
      or diag("read tall: " . $im->errstr);
    is($im->getwidth, 1, "check width");
    is($im->getheight, 1000001, "check height");
    is($im->getchannels, 1, "check channels");
  }
}

{ # test grayscale read as greyscale
  my $im = Imager->new;
  ok($im->read(file => "testimg/gray.png", type => "png"),
     "read grayscale");
  is($im->getchannels, 1, "check channel count");
  is($im->type, "direct", "check type");
  is($im->bits, 8, "check bits");
  is($im->tags(name => "png_bits"), 8, "check png_bits tag");
  is($im->tags(name => "png_interlace"), 0, "check png_interlace tag");
}

{ # test grayscale + alpha read as greyscale + alpha
  my $im = Imager->new;
  ok($im->read(file => "testimg/graya.png", type => "png"),
     "read grayscale + alpha");
  is($im->getchannels, 2, "check channel count");
  is($im->type, "direct", "check type");
  is($im->bits, 8, "check bits");
  is($im->tags(name => "png_bits"), 8, "check png_bits tag");
  is($im->tags(name => "png_interlace"), 0, "check png_interlace tag");
}

{ # test paletted + alpha read as paletted
  my $im = Imager->new;
  ok($im->read(file => "testimg/paltrans.png", type => "png"),
     "read paletted with alpha");
  is($im->getchannels, 4, "check channel count");
  is($im->type, "paletted", "check type");
  is($im->tags(name => "png_bits"), 8, "check png_bits tag");
  is($im->tags(name => "png_interlace"), 0, "check png_interlace tag");
}

{ # test paletted read as paletted
  my $im = Imager->new;
  ok($im->read(file => "testimg/pal.png", type => "png"),
     "read paletted");
  is($im->getchannels, 3, "check channel count");
  is($im->type, "paletted", "check type");
  is($im->tags(name => "png_bits"), 8, "check png_bits tag");
  is($im->tags(name => "png_interlace"), 0, "check png_interlace tag");
}

{ # test 16-bit rgb read as 16 bit
  my $im = Imager->new;
  ok($im->read(file => "testimg/rgb16.png", type => "png"),
     "read 16-bit rgb");
  is($im->getchannels, 3, "check channel count");
  is($im->type, "direct", "check type");
  is($im->tags(name => "png_interlace"), 0, "check png_interlace tag");
  is($im->bits, 16, "check bits");
  is($im->tags(name => "png_bits"), 16, "check png_bits tag");
}

{ # test 1-bit grey read as mono
  my $im = Imager->new;
  ok($im->read(file => "testimg/bilevel.png", type => "png"),
     "read bilevel png");
  is($im->getchannels, 1, "check channel count");
  is($im->tags(name => "png_interlace"), 0, "check png_interlace tag");
  is($im->type, "paletted", "check type");
  ok($im->is_bilevel, "should be bilevel");
  is($im->tags(name => "png_bits"), 1, "check png_bits tag");
}

SKIP:
{ # test interlaced read as interlaced and matches original
  my $im_i = Imager->new(file => "testimg/rgb8i.png", filetype => "png");
  ok($im_i, "read interlaced")
    or skip("Could not read rgb8i.png: " . Imager->errstr, 7);
  is($im_i->getchannels, 3, "check channel count");
  is($im_i->type, "direct", "check type");
  is($im_i->tags(name => "png_bits"), 8, "check png_bits");
  is($im_i->tags(name => "png_interlace"), 1, "check png_interlace");

  my $im = Imager->new(file => "testimg/rgb8.png", filetype => "png");
  ok($im, "read non-interlaced")
    or skip("Could not read testimg/rgb8.png: " . Imager->errstr, 2);
  is($im->tags(name => "png_interlace"), 0, "check png_interlace");
  is_image($im_i, $im, "compare interlaced and non-interlaced");
}

{
  my @match =
    (
     [ "cover.png", "coveri.png" ],
     [ "cover16.png", "cover16i.png" ],
     [ "coverpal.png", "coverpali.png" ],
    );
  for my $match (@match) {
    my ($normal, $interlace) = @$match;

    my $n_im = Imager->new(file => "testimg/$normal");
    ok($n_im, "read $normal")
      or diag "reading $normal: ", Imager->errstr;
    my $i_im = Imager->new(file => "testimg/$interlace");
    ok($i_im, "read $interlace")
      or diag "reading $interlace: ", Imager->errstr;
  SKIP:
    {
      $n_im && $i_im
	or skip("Couldn't read a file", 1);
      is_image($i_im, $n_im, "check normal and interlace files read the same");
    }
  }
}

{
  my $interlace = 0;
  for my $name ("cover.png", "coveri.png") {
  SKIP: {
      my $im = Imager->new(file => "testimg/$name");
      ok($im, "read $name")
	or diag "Failed to read $name: ", Imager->errstr;
      $im
	or skip("Couldn't load $name", 5);
      is($im->tags(name => "i_format"), "png", "$name: i_format");
      is($im->tags(name => "png_bits"), 8, "$name: png_bits");
      is($im->tags(name => "png_interlace"), $interlace,
	 "$name: png_interlace");
      is($im->getchannels, 4, "$name: four channels");
      is($im->type, "direct", "$name: direct type");

      is_deeply([ $im->getsamples(y => 0, width => 5) ],
		[ ( 255, 255, 0, 255 ), ( 255, 255, 0, 191 ),
		  ( 255, 255, 0, 127 ), ( 255, 255, 0, 63 ),
		  ( 0, 0, 0, 0) ],
		"$name: check expected samples row 0");
      is_deeply([ $im->getsamples(y => 1, width => 5) ],
		[ ( 255, 0, 0, 255 ), ( 255, 0, 0, 191 ),
		  ( 255, 0, 0, 127 ), ( 255, 0, 0, 63 ),
		  ( 0, 0, 0, 0) ],
		"$name: check expected samples row 1");
    }
    $interlace = 1;
  }
}

{
  my $interlace = 0;
  for my $name ("coverpal.png", "coverpali.png") {
  SKIP: {
      my $im = Imager->new(file => "testimg/$name");
      ok($im, "read $name")
	or diag "Failed to read $name: ", Imager->errstr;
      $im
	or skip("Couldn't load $name", 5);
      is($im->tags(name => "i_format"), "png", "$name: i_format");
      is($im->tags(name => "png_bits"), 4, "$name: png_bits");
      is($im->tags(name => "png_interlace"), $interlace,
	 "$name: png_interlace");
      is($im->getchannels, 4, "$name: four channels");
      is($im->type, "paletted", "$name: paletted type");

      is_deeply([ $im->getsamples(y => 0, width => 5) ],
		[ ( 255, 255, 0, 255 ), ( 255, 255, 0, 191 ),
		  ( 255, 255, 0, 127 ), ( 255, 255, 0, 63 ),
		  ( 0, 0, 0, 0) ],
		"$name: check expected samples row 0");
      is_deeply([ $im->getsamples(y => 1, width => 5) ],
		[ ( 255, 0, 0, 255 ), ( 255, 0, 0, 191 ),
		  ( 255, 0, 0, 127 ), ( 255, 0, 0, 63 ),
		  ( 0, 0, 0, 0) ],
		"$name: check expected samples row 1");
    }
    $interlace = 1;
  }
}

{
  my $interlace = 0;
  for my $name ("cover16.png", "cover16i.png") {
  SKIP: {
      my $im = Imager->new(file => "testimg/$name");
      ok($im, "read $name")
	or diag "Failed to read $name: ", Imager->errstr;
      $im
	or skip("Couldn't load $name", 5);
      is($im->tags(name => "i_format"), "png", "$name: i_format");
      is($im->tags(name => "png_bits"), 16, "$name: png_bits");
      is($im->tags(name => "png_interlace"), $interlace,
	 "$name: png_interlace");
      is($im->getchannels, 4, "$name: four channels");
      is($im->type, "direct", "$name: direct type");

      is_deeply([ $im->getsamples(y => 0, width => 5, type => "16bit") ],
		[ ( 65535, 65535, 0, 65535 ), ( 65535, 65535, 0, 49087 ),
		  ( 65535, 65535, 0, 32639 ), ( 65535, 65535, 0, 16191 ),
		  ( 65535, 65535, 65535, 0) ],
		"$name: check expected samples row 0");
      is_deeply([ $im->getsamples(y => 1, width => 5, type => "16bit") ],
		[ ( 65535, 0, 0, 65535 ), ( 65535, 0, 0, 49087 ),
		  ( 65535, 0, 0, 32639 ), ( 65535, 0, 0, 16191 ),
		  ( 65535, 65535, 65535, 0) ],
		"$name: check expected samples row 1");
    }
    $interlace = 1;
  }
}

{
  my $pim = Imager->new(xsize => 5, ysize => 2, channels => 3, type => "paletted");
  ok($pim, "make a 3 channel paletted image");
  ok($pim->addcolors(colors => [ qw(000000 FFFFFF FF0000 00FF00 0000FF) ]),
     "add some colors");
  is($pim->setscanline(y => 0, type => "index",
		       pixels => [ 0, 1, 2, 4, 3 ]), 5, "set some pixels");
  is($pim->setscanline(y => 1, type => "index",
		       pixels => [ 4, 1, 0, 4, 2 ]), 5, "set some more pixels");
  ok($pim->write(file => "testout/pal3.png"),
     "write to testout/pal3.png")
    or diag("Cannot save testout/pal3.png: ".$pim->errstr);
  my $in = Imager->new(file => "testout/pal3.png");
  ok($in, "read it back in")
    or diag("Cann't read pal3.png back: " . Imager->errstr);
  is_image($pim, $in, "check it matches");
  is($in->type, "paletted", "make sure the result is paletted");
  is($in->tags(name => "png_bits"), 4, "4 bit representation");
}

{
  # make sure the code that pushes maxed alpha to the end doesn't break
  my $pim = Imager->new(xsize => 8, ysize => 2, channels => 4, type => "paletted");
  ok($pim, "make a 4 channel paletted image");
  ok($pim->addcolors
     (colors => [ NC(255, 255, 0, 128), qw(000000 FFFFFF FF0000 00FF00 0000FF),
		  NC(0, 0, 0, 0), NC(255, 0, 128, 64) ]),
     "add some colors");
  is($pim->setscanline(y => 0, type => "index",
		       pixels => [ 5, 0, 1, 7, 2, 4, 6, 3 ]), 8,
     "set some pixels");
  is($pim->setscanline(y => 1, type => "index",
		       pixels => [ 7, 4, 6, 1, 0, 4, 2, 5 ]), 8,
     "set some more pixels");
  ok($pim->write(file => "testout/pal4.png"),
     "write to testout/pal4.png")
    or diag("Cannot save testout/pal4.png: ".$pim->errstr);
  my $in = Imager->new(file => "testout/pal4.png");
  ok($in, "read it back in")
    or diag("Cann't read pal4.png back: " . Imager->errstr);
  is_image($pim, $in, "check it matches");
  is($in->type, "paletted", "make sure the result is paletted");
  is($in->tags(name => "png_bits"), 4, "4 bit representation");
}

{
  my $pim = Imager->new(xsize => 8, ysize => 2, channels => 1, type => "paletted");
  ok($pim, "make a 1 channel paletted image");
  ok($pim->addcolors(colors => [ map NC($_, 0, 0), 0, 7, 127, 255 ]),
     "add some colors^Wgreys");
  is($pim->setscanline(y => 0, type => "index",
		       pixels => [ 0, 2, 1, 3, 2, 1, 0, 3 ]), 8,
     "set some pixels");
  is($pim->setscanline(y => 1, type => "index",
		       pixels => [ 3, 0, 2, 1, 0, 0, 2, 3 ]), 8,
     "set some more pixels");
  ok($pim->write(file => "testout/pal1.png"),
     "write to testout/pal1.png")
    or diag("Cannot save testout/pal1.png: ".$pim->errstr);
  my $in = Imager->new(file => "testout/pal1.png");
  ok($in, "read it back in")
    or diag("Cann't read pal1.png back: " . Imager->errstr);
  # PNG doesn't have a paletted greyscale type, so it's written as
  # paletted color, convert our source image for the comparison
  my $cmpim = $pim->convert(preset => "rgb");
  is_image($in, $cmpim, "check it matches");
  is($in->type, "paletted", "make sure the result is paletted");
  is($in->tags(name => "png_bits"), 2, "2 bit representation");
}

{
  my $pim = Imager->new(xsize => 8, ysize => 2, channels => 2, type => "paletted");
  ok($pim, "make a 2 channel paletted image");
  ok($pim->addcolors(colors => [ NC(0, 255, 0), NC(128, 255, 0), NC(255, 255, 0), NC(128, 128, 0) ]),
     "add some colors^Wgreys")
    or diag("adding colors: " . $pim->errstr);
  is($pim->setscanline(y => 0, type => "index",
		       pixels => [ 0, 2, 1, 3, 2, 1, 0, 3 ]), 8,
     "set some pixels");
  is($pim->setscanline(y => 1, type => "index",
		       pixels => [ 3, 0, 2, 1, 0, 0, 2, 3 ]), 8,
     "set some more pixels");
  ok($pim->write(file => "testout/pal2.png"),
     "write to testout/pal2.png")
    or diag("Cannot save testout/pal2.png: ".$pim->errstr);
  my $in = Imager->new(file => "testout/pal2.png");
  ok($in, "read it back in")
    or diag("Can't read pal1.png back: " . Imager->errstr);
  # PNG doesn't have a paletted greyscale type, so it's written as
  # paletted color, convert our source image for the comparison
  my $cmpim = $pim->convert(preset => "rgb");
  is_image($in, $cmpim, "check it matches");
  is($in->type, "paletted", "make sure the result is paletted");
  is($in->tags(name => "png_bits"), 2, "2 bit representation");
}

{
  my $imbase = test_image();
  my $mono = $imbase->convert(preset => "gray")
    ->to_paletted(make_colors => "mono", translate => "errdiff");

  ok($mono->write(file => "testout/bilevel.png"),
     "write bilevel.png");
  my $in = Imager->new(file => "testout/bilevel.png");
  ok($in, "read it back in")
    or diag("Can't read bilevel.png: " . Imager->errstr);
  is_image($in, $mono, "check it matches");
  is($in->type, "paletted", "make sure the result is paletted");
  is($in->tags(name => "png_bits"), 1, "1 bit representation");
}

SKIP:
{
  my $im = test_image_16();
  ok($im->write(file => "testout/rgb16.png", type => "png"),
     "write 16-bit/sample image")
    or diag("Could not write rgb16.png: ".$im->errstr);
  my $in = Imager->new(file => "testout/rgb16.png")
    or diag("Could not read rgb16.png: ".Imager->errstr);
  ok($in, "read rgb16.png back in")
    or skip("Could not load image to check", 4);
  is_imaged($in, $im, 0, "check image matches");
  is($in->bits, 16, "check we got a 16-bit image");
  is($in->type, "direct", "check it's direct");
  is($in->tags(name => "png_bits"), 16, "check png_bits");
}

SKIP:
{
  my $im = test_image_double();
  my $cmp = $im->to_rgb16;
  ok($im->write(file => "testout/rgbdbl.png", type => "png"),
     "write double/sample image - should write as 16-bit/sample")
    or diag("Could not write rgbdbl.png: ".$im->errstr);
  my $in = Imager->new(file => "testout/rgbdbl.png")
    or diag("Could not read rgbdbl.png: ".Imager->errstr);
  ok($in, "read pngdbl.png back in")
    or skip("Could not load image to check", 4);
  is_imaged($in, $cmp, 0, "check image matches");
  is($in->bits, 16, "check we got a 16-bit image");
  is($in->type, "direct", "check it's direct");
  is($in->tags(name => "png_bits"), 16, "check png_bits");
}

SKIP:
{
  my $im = Imager->new(file => "testimg/comment.png");
  ok($im, "read file with comment")
    or diag("Cannot read comment.png: ".Imager->errstr);
  $im
    or skip("Cannot test tags file I can't read", 5);
  is($im->tags(name => "i_comment"), "Test comment", "check i_comment");
  is($im->tags(name => "png_interlace"), "0", "no interlace");
  is($im->tags(name => "png_interlace_name"), "none", "no interlace (text)");
  is($im->tags(name => "png_srgb_intent"), "0", "srgb perceptual");
  is($im->tags(name => "png_time"), "2012-04-16T07:37:36",
     "modification time");
  is($im->tags(name => "i_background"), "color(255,255,255,255)",
     "background color");
}

SKIP:
{ # test tag writing
  my $im = Imager->new(xsize => 1, ysize => 1);
  ok($im->write(file => "testout/tags.png",
		i_comment => "A Comment",
		png_author => "An Author",
		png_author_compressed => 1,
		png_copyright => "A Copyright",
		png_creation_time => "16 April 2012 22:56:30+1000",
		png_description => "A Description",
		png_disclaimer => "A Disclaimer",
		png_software => "Some Software",
		png_source => "A Source",
		png_title => "A Title",
		png_warning => "A Warning",
		png_text0_key => "Custom Key",
		png_text0_text => "Custom Value",
		png_text0_compressed => 1,
		png_text1_key => "Custom Key2",
		png_text1_text => "Another Custom Value",
		png_time => "2012-04-20T00:15:10",
	       ),
     "write with many tags")
    or diag("Cannot write with many tags: ", $im->errstr);

  my $imr = Imager->new(file => "testout/tags.png");
  ok($imr, "read it back in")
    or skip("Couldn't read it back: ". Imager->errstr, 1);

  is_deeply({ map @$_, $imr->tags },
	    {
	     i_format => "png",
	     i_comment => "A Comment",
	     png_author => "An Author",
	     png_author_compressed => 1,
	     png_copyright => "A Copyright",
	     png_creation_time => "16 April 2012 22:56:30+1000",
	     png_description => "A Description",
	     png_disclaimer => "A Disclaimer",
	     png_software => "Some Software",
	     png_source => "A Source",
	     png_title => "A Title",
	     png_warning => "A Warning",
	     png_text0_key => "Custom Key",
	     png_text0_text => "Custom Value",
	     png_text0_compressed => 1,
	     png_text0_type => "text",
	     png_text1_key => "Custom Key2",
	     png_text1_text => "Another Custom Value",
	     png_text1_type => "text",
	     png_time => "2012-04-20T00:15:10",
	     png_interlace => 0,
	     png_interlace_name => "none",
	     png_bits => 8,
	    }, "check tags are what we expected");
}

SKIP:
{ # cHRM test
  my $im = Imager->new(xsize => 1, ysize => 1);
  ok($im->write(file => "testout/tagschrm.png", type => "png",
		png_chroma_white_x => 0.3,
		png_chroma_white_y => 0.32,
		png_chroma_red_x => 0.7,
		png_chroma_red_y => 0.28,
		png_chroma_green_x => 0.075,
		png_chroma_green_y => 0.8,
		png_chroma_blue_x => 0.175,
		png_chroma_blue_y => 0.05),
     "write cHRM chunk");
  my $imr = Imager->new(file => "testout/tagschrm.png", ftype => "png");
  ok($imr, "read tagschrm.png")
    or diag("reading tagschrm.png: ".Imager->errstr);
  $imr
    or skip("read of tagschrm.png failed", 1);
  is_deeply({ map @$_, $imr->tags },
	    {
	     i_format => "png",
	     png_interlace => 0,
	     png_interlace_name => "none",
	     png_bits => 8,
	     png_chroma_white_x => 0.3,
	     png_chroma_white_y => 0.32,
	     png_chroma_red_x => 0.7,
	     png_chroma_red_y => 0.28,
	     png_chroma_green_x => 0.075,
	     png_chroma_green_y => 0.8,
	     png_chroma_blue_x => 0.175,
	     png_chroma_blue_y => 0.05,
	    }, "check chroma tags written");
}

{ # gAMA
  my $im = Imager->new(xsize => 1, ysize => 1);
  ok($im->write(file => "testout/tagsgama.png", type => "png",
	       png_gamma => 2.22),
     "write with png_gammma tag");
  my $imr = Imager->new(file => "testout/tagsgama.png", ftype => "png");
  ok($imr, "read tagsgama.png")
    or diag("reading tagsgama.png: ".Imager->errstr);
  $imr
    or skip("read of tagsgama.png failed", 1);
  is_deeply({ map @$_, $imr->tags },
	    {
	     i_format => "png",
	     png_interlace => 0,
	     png_interlace_name => "none",
	     png_bits => 8,
	     png_gamma => "2.22",
	    }, "check gamma tag written");
}

{ # various bad tag failures
  my @tests =
    (
     [
      [ png_chroma_white_x => 0.5 ],
      "all png_chroma_* tags must be supplied or none"
     ],
     [
      [ png_srgb_intent => 4 ],
      "tag png_srgb_intent out of range"
     ],
     [
      [ i_comment => "test\0with nul" ],
      "tag i_comment may not contain NUL characters"
     ],
     [
      [ png_text0_key => "" ],
      "tag png_text0_key must be between 1 and 79 characters in length"
     ],
     [
      [ png_text0_key => ("x" x 80) ],
      "tag png_text0_key must be between 1 and 79 characters in length"
     ],
     [
      [ png_text0_key => " x" ],
      "tag png_text0_key may not contain leading or trailing spaces"
     ],
     [
      [ png_text0_key => "x " ],
      "tag png_text0_key may not contain leading or trailing spaces"
     ],
     [
      [ png_text0_key => "x  y" ],
      "tag png_text0_key may not contain consecutive spaces"
     ],
     [
      [ png_text0_key => "\x7F" ],
      "tag png_text0_key may only contain Latin1 characters 32-126, 161-255"
     ],
     [
      [ png_text0_key => "x", png_text0_text => "a\0b" ],
      "tag png_text0_text may not contain NUL characters"
     ],
     [
      [ png_text0_key => "test" ],
      "tag png_text0_key found but not png_text0_text"
     ],
     [
      [ png_text0_text => "test" ],
      "tag png_text0_text found but not png_text0_key"
     ],
     [
      [ png_time => "bad format" ],
      "png_time must be formatted 'y-m-dTh:m:s'"
     ],
     [
      [ png_time => "2012-13-01T00:00:00" ],
      "invalid date/time for png_time"
     ],
    ); 
  my $im = Imager->new(xsize => 1, ysize => 1);
  for my $test (@tests) {
    my ($tags, $error) = @$test;
    my $im2 = $im->copy;
    my $data;
    ok(!$im2->write(data => \$data, type => "png", @$tags),
       "expect $error");
    is($im2->errstr, $error, "check error message");
  }
}

sub limited_write {
  my ($limit) = @_;

  return
     sub {
       my ($data) = @_;
       $limit -= length $data;
       if ($limit >= 0) {
         print "# write of ", length $data, " bytes successful ($limit left)\n" if $debug_writes;
         return 1;
       }
       else {
         print "# write of ", length $data, " bytes failed\n";
         Imager::i_push_error(0, "limit reached");
         return;
       }
     };
}

