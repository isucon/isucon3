#!perl -w
use strict;
use Test::More tests => 215;
use Imager qw(:all);
use Imager::Test qw(test_image_raw is_image is_color3 test_image);

-d "testout" or mkdir "testout";

Imager->open_log(log => "testout/t107bmp.log");

my @files;
my $debug_writes = 0;

my $base_diff = 0;
# if you change this make sure you generate new compressed versions
my $green=i_color_new(0,255,0,255);
my $blue=i_color_new(0,0,255,255);
my $red=i_color_new(255,0,0,255);

my $img = test_image_raw();

Imager::i_tags_add($img, 'i_xres', 0, '300', 0);
Imager::i_tags_add($img, 'i_yres', 0, undef, 300);
write_test($img, "testout/t107_24bit.bmp");
push @files, "t107_24bit.bmp";
# 'webmap' is noticably faster than the default
my $im8 = Imager::i_img_to_pal($img, { make_colors=>'webmap', 
				       translate=>'errdiff'});
write_test($im8, "testout/t107_8bit.bmp");
push @files, "t107_8bit.bmp";
# use a fixed palette so we get reproducible results for the compressed
# version
my @pal16 = map { NC($_) } 
  qw(605844 966600 0148b2 00f800 bf0a33 5e009e
     2ead1b 0000f8 004b01 fd0000 0e1695 000002);
my $im4 = Imager::i_img_to_pal($img, { colors=>\@pal16, make_colors=>'none' });
write_test($im4, "testout/t107_4bit.bmp");
push @files, "t107_4bit.bmp";
my $im1 = Imager::i_img_to_pal($img, { colors=>[ NC(0, 0, 0), NC(176, 160, 144) ],
			       make_colors=>'none', translate=>'errdiff' });
write_test($im1, "testout/t107_1bit.bmp");
push @files, "t107_1bit.bmp";
my $bi_rgb = 0;
my $bi_rle8 = 1;
my $bi_rle4 = 2;
my $bi_bitfields = 3;
read_test("testout/t107_24bit.bmp", $img, 
          bmp_compression=>0, bmp_bit_count => 24);
read_test("testout/t107_8bit.bmp", $im8, 
          bmp_compression=>0, bmp_bit_count => 8);
read_test("testout/t107_4bit.bmp", $im4, 
          bmp_compression=>0, bmp_bit_count => 4);
read_test("testout/t107_1bit.bmp", $im1, bmp_compression=>0, 
          bmp_bit_count=>1);
# the following might have slight differences
$base_diff = i_img_diff($img, $im8) * 2;
print "# base difference $base_diff\n";
read_test("testimg/comp4.bmp", $im4, 
          bmp_compression=>$bi_rle4, bmp_bit_count => 4);
read_test("testimg/comp8.bmp", $im8, 
          bmp_compression=>$bi_rle8, bmp_bit_count => 8);

my $imoo = Imager->new;
# read via OO
ok($imoo->read(file=>'testout/t107_24bit.bmp'), "read via OO")
  or print "# ",$imoo->errstr,"\n";

ok($imoo->write(file=>'testout/t107_oo.bmp'), "write via OO")
  or print "# ",$imoo->errstr,"\n";
push @files, "t107_oo.bmp";

# various invalid format tests
# we have so many different test images to try to detect all the possible
# failure paths in the code, adding these did detect real problems
print "# catch various types of invalid bmp files\n";
my @tests =
  (
   # entries in each array ref are:
   #  - basename of an invalid BMP file
   #  - error message that should be produced
   #  - description of what is being tested
   #  - possible flag to indicate testing only on 32-bit machines
   [ 'badplanes.bmp', 'not a BMP file', "invalid planes value" ],
   [ 'badbits.bmp', 'unknown bit count for BMP file (5)', 
     'should fail to read invalid bits' ],

   # 1-bit/pixel BMPs
   [ 'badused1.bmp', 'out of range colors used (3)',
     'out of range palette size (1-bit)' ],
   [ 'badcomp1.bmp', 'unknown 1-bit BMP compression (1)',
     'invalid compression value (1-bit)' ],
   [ 'bad1wid0.bmp', 'file size limit - image width of 0 is not positive',
     'width 0 (1-bit)' ],
   [ 'bad4oflow.bmp', 
     'file size limit - integer overflow calculating storage',
     'overflow integers on 32-bit machines (1-bit)', '32bitonly' ],
   [ 'short1.bmp', 'failed reading 1-bit bmp data', 
     'short 1-bit' ],

   # 4-bit/pixel BMPs
   [ 'badused4a.bmp', 'out of range colors used (272)', 
     'should fail to read invalid pal size (272) (4-bit)' ],
   [ 'badused4b.bmp', 'out of range colors used (17)',
     'should fail to read invalid pal size (17) (4-bit)' ],
   [ 'badcomp4.bmp', 'unknown 4-bit BMP compression (1)',
     'invalid compression value (4-bit)' ],
   [ 'short4.bmp', 'failed reading 4-bit bmp data', 
     'short uncompressed 4-bit' ],
   [ 'short4rle.bmp', 'missing data during decompression', 
     'short compressed 4-bit' ],
   [ 'bad4wid0.bmp', 'file size limit - image width of 0 is not positive',
     'width 0 (4-bit)' ],
   [ 'bad4widbig.bmp', 'file size limit - image width of -2147483628 is not positive',
     'width big (4-bit)' ],
   [ 'bad4oflow.bmp', 'file size limit - integer overflow calculating storage',
     'overflow integers on 32-bit machines (4-bit)', '32bitonly' ],

   # 8-bit/pixel BMPs
   [ 'bad8useda.bmp', 'out of range colors used (257)',
     'should fail to read invalid pal size (8-bit)' ],
   [ 'bad8comp.bmp', 'unknown 8-bit BMP compression (2)',
     'invalid compression value (8-bit)' ],
   [ 'short8.bmp', 'failed reading 8-bit bmp data', 
     'short uncompressed 8-bit' ],
   [ 'short8rle.bmp', 'missing data during decompression', 
     'short compressed 8-bit' ],
   [ 'bad8wid0.bmp', 'file size limit - image width of 0 is not positive',
     'width 0 (8-bit)' ],
   [ 'bad8oflow.bmp', 'file size limit - integer overflow calculating storage',
     'overflow integers on 32-bit machines (8-bit)', '32bitonly' ],

   # 24-bit/pixel BMPs
   [ 'short24.bmp', 'failed reading image data',
     'short 24-bit' ],
   [ 'bad24wid0.bmp', 'file size limit - image width of 0 is not positive',
     'width 0 (24-bit)' ],
   [ 'bad24oflow.bmp', 'file size limit - integer overflow calculating storage',
     'overflow integers on 32-bit machines (24-bit)', '32bitonly' ],
   [ 'bad24comp.bmp', 'unknown 24-bit BMP compression (4)',
     'bad compression (24-bit)' ],
  );
use Config;
my $ptrsize = $Config{ptrsize};
for my $test (@tests) {
  my ($file, $error, $comment, $bit32only) = @$test;
 SKIP:
  {
    skip("only tested on 32-bit machines", 2)
      if $bit32only && $ptrsize != 4;
    ok(!$imoo->read(file=>"testimg/$file"), $comment);
    print "# ", $imoo->errstr, "\n";
    is($imoo->errstr, $error, "check error message");
  }
}

# previously we didn't seek to the offbits position before reading
# the image data, check we handle it correctly
# in each case the first is an original image with a given number of
# bits and the second is the same file with data inserted before the
# image bits and the offset modified to suit
my @comp =
  (
   [ 'winrgb2.bmp', 'winrgb2off.bmp', 1 ],
   [ 'winrgb4.bmp', 'winrgb4off.bmp', 4 ],
   [ 'winrgb8.bmp', 'winrgb8off.bmp', 8 ],
   [ 'winrgb24.bmp', 'winrgb24off.bmp', 24 ],
  );

for my $comp (@comp) {
  my ($base_file, $off_file, $bits) = @$comp;

  my $base_im = Imager->new;
  my $got_base = 
    ok($base_im->read(file=>"testimg/$base_file"),
        "read original")
      or print "# ",$base_im->errstr,"\n";
  my $off_im = Imager->new;
  my $got_off =
    ok($off_im->read(file=>"testimg/$off_file"),
        "read offset file")
      or print "# ",$off_im->errstr,"\n";
 SKIP:
  {
    skip("missed one file", 1)
      unless $got_base && $got_off;
    is(i_img_diff($base_im->{IMG}, $off_im->{IMG}), 0,
        "compare base and offset image ($bits bits)");
  }
}

{ # check file limits are checked
  my $limit_file = "testout/t107_24bit.bmp";
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

{ # various short read failure tests, each entry has:
  # source filename, size, expected error
  # these have been selected based on code coverage, to check each
  # failure path is checked, where practical
  my @tests =
    (
     [ 
      "file truncated inside header",
      "winrgb2.bmp", 
      20, "file too short to be a BMP file"
     ],
     [
      "1-bit, truncated inside palette",
      "winrgb2.bmp", 
      56, "reading BMP palette" 
     ],
     [ 
      "1-bit, truncated in offset region",
      "winrgb2off.bmp", 64, "failed skipping to image data offset" 
     ],
     [ 
      "1-bit, truncated in image data",
      "winrgb2.bmp", 96, "failed reading 1-bit bmp data"
     ],
     [
      "4-bit, truncated inside palette",
      "winrgb4.bmp",
      56, "reading BMP palette"
     ],
     [
      "4-bit, truncated in offset region",
      "winrgb4off.bmp", 120, "failed skipping to image data offset",
     ],
     [
      "4-bit, truncate in image data",
      "winrgb4.bmp", 120, "failed reading 4-bit bmp data"
     ],
     [
      "4-bit RLE, truncate in uncompressed data",
      "comp4.bmp", 0x229, "missing data during decompression"
     ],
     [
      "8-bit, truncated in palette",
      "winrgb8.bmp", 1060, "reading BMP palette"
      ],
     [
      "8-bit, truncated in offset region",
      "winrgb8off.bmp", 1080, "failed skipping to image data offset"
     ],
     [
      "8-bit, truncated in image data",
      "winrgb8.bmp", 1080, "failed reading 8-bit bmp data"
     ],
     [
      "8-bit RLE, truncate in uncompressed data",
      "comp8.bmp", 0x68C, "missing data during decompression"
     ],
     [
      "24-bit, truncate in offset region",
      "winrgb24off.bmp", 56, "failed skipping to image data offset",
     ],
     [
      "24-bit, truncate in image data",
      "winrgb24.bmp", 100, "failed reading image data",
     ],
    );

  my $test_index = 0;
  for my $test (@tests) {
    my ($desc, $srcfile, $size, $error) = @$test;
    my $im = Imager->new;
    open IMDATA, "< testimg/$srcfile"
      or die "$test_index - $desc: Cannot open testimg/$srcfile: $!";
    binmode IMDATA;
    my $data;
    read(IMDATA, $data, $size) == $size
      or die "$test_index - $desc: Could not read $size data from $srcfile";
    close IMDATA;
    ok(!$im->read(data => $data, type =>'bmp'),
       "$test_index - $desc: Should fail to read");
    is($im->errstr, $error, "$test_index - $desc: check message");
    ++$test_index;
  }
}

{ # various short read success tests, each entry has:
  # source filename, size, expected tags
  print "# allow_incomplete tests\n";
  my @tests =
    (
     [ 
      "1-bit",
      "winrgb2.bmp", 96,
      {
       bmp_compression_name => 'BI_RGB',
       bmp_compression => 0,
       bmp_used_colors => 2,
       i_lines_read => 8,
      },
     ],
     [
      "4-bit",
      "winrgb4.bmp", 250,
      {
       bmp_compression_name => 'BI_RGB',
       bmp_compression => 0,
       bmp_used_colors => 16,
       i_lines_read => 11,
      },
     ],
     [
      "4-bit RLE - uncompressed seq",
      "comp4.bmp", 0x229, 
      {
       bmp_compression_name => 'BI_RLE4',
       bmp_compression => 2,
       bmp_used_colors => 16,
       i_lines_read => 44,
      },
     ],
     [
      "4-bit RLE - start seq",
      "comp4.bmp", 0x97, 
      {
       bmp_compression_name => 'BI_RLE4',
       bmp_compression => 2,
       bmp_used_colors => 16,
       i_lines_read => 8,
      },
     ],
     [
      "8-bit",
      "winrgb8.bmp", 1250,
      {
       bmp_compression_name => 'BI_RGB',
       bmp_compression => 0,
       bmp_used_colors => 256,
       i_lines_read => 8,
      },
     ],
     [
      "8-bit RLE - uncompressed seq",
      "comp8.bmp", 0x68C, 
      {
       bmp_compression_name => 'BI_RLE8',
       bmp_compression => 1,
       bmp_used_colors => 256,
       i_lines_read => 27,
      },
     ],
     [
      "8-bit RLE - initial seq",
      "comp8.bmp", 0x487, 
      {
       bmp_compression_name => 'BI_RLE8',
       bmp_compression => 1,
       bmp_used_colors => 256,
       i_lines_read => 20,
      },
     ],
     [
      "24-bit",
      "winrgb24.bmp", 800,
      {
       bmp_compression_name => 'BI_RGB',
       bmp_compression => 0,
       bmp_used_colors => 0,
       i_lines_read => 12,
      },
     ],
    );

  my $test_index = 0;
  for my $test (@tests) {
    my ($desc, $srcfile, $size, $tags) = @$test;
    my $im = Imager->new;
    open IMDATA, "< testimg/$srcfile"
      or die "$test_index - $desc: Cannot open testimg/$srcfile: $!";
    binmode IMDATA;
    my $data;
    read(IMDATA, $data, $size) == $size
      or die "$test_index - $desc: Could not read $size data from $srcfile";
    close IMDATA;
    ok($im->read(data => $data, type =>'bmp', allow_incomplete => 1),
       "$test_index - $desc: Should read successfully");
    # check standard tags are set
    is($im->tags(name => 'i_format'), 'bmp',
       "$test_index - $desc: i_format set");
    is($im->tags(name => 'i_incomplete'), 1, 
       "$test_index - $desc: i_incomplete set");
    my %check_tags;
    for my $key (keys %$tags) {
      $check_tags{$key} = $im->tags(name => $key);
    }
    is_deeply(\%check_tags, $tags, "$test_index - $desc: check tags");
    ++$test_index;
  }
}

{ # check handling of reading images with negative height
  # each entry is:
  # source file, description
  print "# check handling of negative height values\n";
  my @tests =
    (
     [ "winrgb2.bmp", "1-bit, uncompressed" ],
     [ "winrgb4.bmp", "4-bit, uncompressed" ],
     [ "winrgb8.bmp", "8-bit, uncompressed" ],
     [ "winrgb24.bmp", "24-bit, uncompressed" ],
     [ "comp4.bmp", "4-bit, RLE" ],
     [ "comp8.bmp", "8-bit, RLE" ],
    );
  my $test_index = 0;
  for my $test (@tests) {
    my ($file, $desc) = @$test;
    open IMDATA, "< testimg/$file"
      or die "$test_index - Cannot open $file: $!";
    binmode IMDATA;
    my $data = do { local $/; <IMDATA> };
    close IMDATA;
    my $im_orig = Imager->new;
    $im_orig->read(data => $data)
      or die "Cannot load original $file: ", $im_orig->errstr;
    
    # now negate the height
    my $orig_height = unpack("V", substr($data, 0x16, 4));
    my $neg_height = 0xFFFFFFFF & ~($orig_height - 1);
    substr($data, 0x16, 4) = pack("V", $neg_height);

    # and read the modified image
    my $im = Imager->new;
    ok($im->read(data => $data),
       "$test_index - $desc: read negated height image")
      or print "# ", $im->errstr, "\n";

    # flip orig to match what we should get
    $im_orig->flip(dir => 'v');

    # check it out
    is_image($im, $im_orig, "$test_index - $desc: check image");

    ++$test_index;
  }
}

{ print "# patched data read failure tests\n";
  # like the "various invalid format" tests, these generate fail
  # images from other images included with Imager without providing a
  # full bmp source, saving on dist size and focusing on the changes needed
  # to cause the failure
  # each entry is: source file, patches, expected error, description
  
  my @tests =
    (
     # low image data offsets
     [ 
      "winrgb2.bmp", 
      { 10 => "3d 00 00 00" }, 
      "image data offset too small (61)",
      "1-bit, small image offset"
     ],
     [ 
      "winrgb4.bmp", 
      { 10 => "75 00 00 00" }, 
      "image data offset too small (117)",
      "4-bit, small image offset"
     ],
     [ 
      "winrgb8.bmp", 
      { 10 => "35 04 00 00" }, 
      "image data offset too small (1077)",
      "8-bit, small image offset"
     ],
     [ 
      "winrgb24.bmp", 
      { 10 => "35 00 00 00" }, 
      "image data offset too small (53)",
      "24-bit, small image offset"
     ],
     # compression issues
     [
      "comp8.bmp",
      { 0x436 => "97" },
      "invalid data during decompression",
      "8bit, RLE run beyond edge of image"
     ],
     [
      # caused glibc malloc or valgrind to complain
      "comp8.bmp",
      { 0x436 => "94 00 00 03" },
      "invalid data during decompression",
      "8bit, literal run beyond edge of image"
     ],
     [
      "comp4.bmp",
      { 0x76 => "FF bb FF BB" },
      "invalid data during decompression",
      "4bit - RLE run beyond edge of image"
     ],
     [
      "comp4.bmp",
      { 0x76 => "94 bb 00 FF" },
      "invalid data during decompression",
      "4bit - literal run beyond edge of image"
     ],
    );
  my $test_index = 0;
  for my $test (@tests) {
    my ($filename, $patches, $error, $desc) = @$test;

    my $data = load_patched_file("testimg/$filename", $patches);
    my $im = Imager->new;
    ok(!$im->read(data => $data, type=>'bmp'),
       "$test_index - $desc:should fail to read");
    is($im->errstr, $error, "$test_index - $desc:check message");
    ++$test_index;
  }
}

{ # various write failure tests
  # each entry is:
  # source, limit, expected error, description
  my @tests =
    (
     [ 
      "winrgb2.bmp", 1, 
      "cannot write bmp header: limit reached",
      "1-bit, writing header" 
     ],
     [ 
      "winrgb4.bmp", 1, 
      "cannot write bmp header: limit reached",
      "4-bit, writing header" 
     ],
     [ 
      "winrgb8.bmp", 1, 
      "cannot write bmp header: limit reached",
      "8-bit, writing header" 
     ],
     [ 
      "winrgb24.bmp", 1, 
      "cannot write bmp header: limit reached",
      "24-bit, writing header" 
     ],
     [ 
      "winrgb2.bmp", 0x38, 
      "cannot write palette entry: limit reached",
      "1-bit, writing palette" 
     ],
     [ 
      "winrgb4.bmp", 0x38, 
      "cannot write palette entry: limit reached",
      "4-bit, writing palette" 
     ],
     [ 
      "winrgb8.bmp", 0x38, 
      "cannot write palette entry: limit reached",
      "8-bit, writing palette" 
     ],
     [ 
      "winrgb2.bmp", 0x40, 
      "writing 1 bit/pixel packed data: limit reached",
      "1-bit, writing image data" 
     ],
     [ 
      "winrgb4.bmp", 0x80, 
      "writing 4 bit/pixel packed data: limit reached",
      "4-bit, writing image data" 
     ],
     [ 
      "winrgb8.bmp", 0x440, 
      "writing 8 bit/pixel packed data: limit reached",
      "8-bit, writing image data" 
     ],
     [ 
      "winrgb24.bmp", 0x39, 
      "writing image data: limit reached",
      "24-bit, writing image data" 
     ],
    );
  print "# write failure tests\n";
  my $test_index = 0;
  for my $test (@tests) {
    my ($file, $limit, $error, $desc) = @$test;

    my $im = Imager->new;
    $im->read(file => "testimg/$file")
      or die "Cannot read $file: ", $im->errstr;

    my $io = Imager::io_new_cb(limited_write($limit), undef, undef, undef, 1);
    $io->set_buffered(0);
    print "# writing with limit of $limit\n";
    ok(!$im->write(type => 'bmp', io => $io),
       "$test_index - $desc: write should fail");
    is($im->errstr, $error, "$test_index - $desc: check error message");

    ++$test_index;
  }
}

{
  ok(grep($_ eq 'bmp', Imager->read_types), "check bmp in read types");
  ok(grep($_ eq 'bmp', Imager->write_types), "check bmp in write types");
}

{
  # RT #30075
  # give 4/2 channel images a background color when saving to BMP
  my $im = Imager->new(xsize=>16, ysize=>16, channels=>4);
  $im->box(filled => 1, xmin => 8, color => '#FFE0C0');
  $im->box(filled => 1, color => NC(0, 192, 192, 128),
	   ymin => 8, xmax => 7);
  ok($im->write(file=>"testout/t107_alpha.bmp", type=>'bmp'),
     "should succeed writing 4 channel image");
  push @files, "t107_alpha.bmp";
  my $imread = Imager->new;
  ok($imread->read(file => 'testout/t107_alpha.bmp'), "read it back");
  is_color3($imread->getpixel('x' => 0, 'y' => 0), 0, 0, 0, 
	    "check transparent became black");
  is_color3($imread->getpixel('x' => 8, 'y' => 0), 255, 224, 192,
	    "check color came through");
  is_color3($imread->getpixel('x' => 0, 'y' => 15), 0, 96, 96,
	    "check translucent came through");
  my $data;
  ok($im->write(data => \$data, type => 'bmp', i_background => '#FF0000'),
     "write with red background");
  ok($imread->read(data => $data, type => 'bmp'),
     "read it back");
  is_color3($imread->getpixel('x' => 0, 'y' => 0), 255, 0, 0, 
	    "check transparent became red");
  is_color3($imread->getpixel('x' => 8, 'y' => 0), 255, 224, 192,
	    "check color came through");
  is_color3($imread->getpixel('x' => 0, 'y' => 15), 127, 96, 96,
	    "check translucent came through");
}

{ # RT 41406
  my $data;
  my $im = test_image();
  ok($im->write(data => \$data, type => 'bmp'), "write using OO");
  my $size = unpack("V", substr($data, 34, 4));
  is($size, 67800, "check data size");
}

{ # check close failures are handled correctly
  my $im = test_image();
  my $fail_close = sub {
    Imager::i_push_error(0, "synthetic close failure");
    return 0;
  };
  ok(!$im->write(type => "bmp", callback => sub { 1 },
		 closecb => $fail_close),
     "check failing close fails");
    like($im->errstr, qr/synthetic close failure/,
	 "check error message");
}

Imager->close_log;

unless ($ENV{IMAGER_KEEP_FILES}) {
  unlink map "testout/$_", @files;
  unlink "testout/t107bmp.log";
}

sub write_test {
  my ($im, $filename) = @_;
  local *FH;

  if (open FH, "> $filename") {
    binmode FH;
    my $IO = Imager::io_new_fd(fileno(FH));
    unless (ok(Imager::i_writebmp_wiol($im, $IO), $filename)) {
      print "# ",Imager->_error_as_msg(),"\n";
    }
    undef $IO;
    close FH;
  }
  else {
    fail("could not open $filename: $!");
  }
}

sub read_test {
  my ($filename, $im, %tags) = @_;
  local *FH;
  
  print "# read_test: $filename\n";

  $tags{i_format} = "bmp";

  if (open FH, "< $filename") {
    binmode FH;
    my $IO = Imager::io_new_fd(fileno(FH));
    my $im_read = Imager::i_readbmp_wiol($IO);
    if ($im_read) {
      my $diff = i_img_diff($im, $im_read);
      if ($diff > $base_diff) {
	fail("image mismatch reading $filename");
      }
      else {
        my $tags_ok = 1;
        for my $tag (keys %tags) {
          if (my $index = Imager::i_tags_find($im_read, $tag, 0)) {
            my ($name, $value) = Imager::i_tags_get($im_read, $index);
            my $exp_value = $tags{$tag};
            print "#   tag $name = '$value' - expect '$exp_value'\n";
            if ($exp_value =~ /\d/) {
              if ($value != $tags{$tag}) {
                print "# tag $tag value mismatch $tags{$tag} != $value\n";
                $tags_ok = 0;
              }
            }
            else {
              if ($value ne $tags{$tag}) {
                print "# tag $tag value mismatch $tags{$tag} != $value\n";
                $tags_ok = 0;
              }
            }
          }
        }
        ok($tags_ok, "reading $filename");
        #  for my $i (0 .. Imager::i_tags_count($im_read)-1) {
        #    my ($name, $value) = Imager::i_tags_get($im_read, $i);
        #    print "# tag '$name' => '$value'\n";
        #}
      }
    }
    else {
      fail("could not read $filename: ".Imager->_error_as_msg());
    }
    undef $IO;
    close FH;
  }
  else {
    fail("could not open $filename: $!");
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

sub load_patched_file {
  my ($filename, $patches) = @_;

  open IMDATA, "< $filename"
    or die "Cannot open $filename: $!";
  binmode IMDATA;
  my $data = do { local $/; <IMDATA> };
  for my $offset (keys %$patches) {
    (my $hdata = $patches->{$offset}) =~ tr/ //d;
    my $pdata = pack("H*", $hdata);
    substr($data, $offset, length $pdata) = $pdata;
  }

  return $data;
}
