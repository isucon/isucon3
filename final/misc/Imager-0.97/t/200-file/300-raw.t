#!perl -w
use strict;
use Test::More tests => 53;
use Imager qw(:all);
use Imager::Test qw/is_color3 is_color4 test_image test_image_mono/;

-d "testout" or mkdir "testout";

Imager->open_log(log => "testout/t103raw.log");

$| = 1;

my $green=i_color_new(0,255,0,255);
my $blue=i_color_new(0,0,255,255);
my $red=i_color_new(255,0,0,255);

my $img=Imager::ImgRaw::new(150,150,3);
my $cmpimg=Imager::ImgRaw::new(150,150,3);

i_box_filled($img,70,25,130,125,$green);
i_box_filled($img,20,25,80,125,$blue);
i_arc($img,75,75,30,0,361,$red);
i_conv($img,[0.1, 0.2, 0.4, 0.2, 0.1]);

my $timg = Imager::ImgRaw::new(20, 20, 4);
my $trans = i_color_new(255, 0, 0, 127);
i_box_filled($timg, 0, 0, 20, 20, $green);
i_box_filled($timg, 2, 2, 18, 18, $trans);

open(FH,">testout/t103.raw") || die "Cannot open testout/t103.raw for writing\n";
binmode(FH);
my $IO = Imager::io_new_fd( fileno(FH) );
ok(i_writeraw_wiol($img, $IO), "write raw low") or
  print "# Cannot write testout/t103.raw\n";
close(FH);

open(FH,"testout/t103.raw") || die "Cannot open testout/t103.raw\n";
binmode(FH);
$IO = Imager::io_new_fd( fileno(FH) );
$cmpimg = i_readraw_wiol($IO, 150, 150, 3, 3, 0);
ok($cmpimg, "read raw low")
  or print "# Cannot read testout/t103.raw\n";
close(FH);

print "# raw average mean square pixel difference: ",sqrt(i_img_diff($img,$cmpimg))/150*150,"\n";

# I could have kept the raw images for these tests in binary files in
# testimg/, but I think keeping them as hex encoded data in here makes
# it simpler to add more if necessary
# Later we may change this to read from a scalar instead
save_data('testout/t103_base.raw');
save_data('testout/t103_3to4.raw');
save_data('testout/t103_line_int.raw');
save_data('testout/t103_img_int.raw');

# load the base image
open FH, "testout/t103_base.raw" 
  or die "Cannot open testout/t103_base.raw: $!";
binmode FH;
$IO = Imager::io_new_fd( fileno(FH) );

my $baseimg = i_readraw_wiol( $IO, 4, 4, 3, 3, 0);
ok($baseimg, "read base raw image")
  or die "Cannot read base raw image";
close FH;

# the actual read tests
# each read_test() call does 2 tests:
#  - check if the read succeeds
#  - check if it matches $baseimg
read_test('testout/t103_3to4.raw', 4, 4, 4, 3, 0, $baseimg);
read_test('testout/t103_line_int.raw', 4, 4, 3, 3, 1, $baseimg);
# intrl==2 is documented in raw.c but doesn't seem to be implemented
#read_test('testout/t103_img_int.raw', 4, 4, 3, 3, 2, $baseimg, 7);

# paletted images
SKIP:
{
  my $palim = Imager::i_img_pal_new(20, 20, 3, 256);
  ok($palim, "make paletted image")
    or skip("couldn't make paletted image", 2);
  my $redindex = Imager::i_addcolors($palim, $red);
  my $blueindex = Imager::i_addcolors($palim, $blue);
  for my $y (0..9) {
    Imager::i_ppal($palim, 0, $y, ($redindex) x 20);
  }
  for my $y (10..19) {
    Imager::i_ppal($palim, 0, $y, ($blueindex) x 20);
  }
  open FH, "> testout/t103_pal.raw"
    or die "Cannot create testout/t103_pal.raw: $!";
  binmode FH;
  $IO = Imager::io_new_fd(fileno(FH));
  ok(i_writeraw_wiol($palim, $IO), "write low paletted");
  close FH;
  
  open FH, "testout/t103_pal.raw"
    or die "Cannot open testout/t103_pal.raw: $!";
  binmode FH;
  my $data = do { local $/; <FH> };
  is($data, "\x0" x 200 . "\x1" x 200, "compare paletted data written");
  close FH;
}

# 16-bit image
# we don't have 16-bit reads yet
SKIP:
{
  my $img16 = Imager::i_img_16_new(150, 150, 3);
  ok($img16, "make 16-bit/sample image")
    or skip("couldn't make 16 bit/sample image", 1);
  i_box_filled($img16,70,25,130,125,$green);
  i_box_filled($img16,20,25,80,125,$blue);
  i_arc($img16,75,75,30,0,361,$red);
  i_conv($img16,[0.1, 0.2, 0.4, 0.2, 0.1]);
  
  open FH, "> testout/t103_16.raw" 
    or die "Cannot create testout/t103_16.raw: $!";
  binmode FH;
  $IO = Imager::io_new_fd(fileno(FH));
  ok(i_writeraw_wiol($img16, $IO), "write low 16 bit image");
  close FH;
}

# try a simple virtual image
SKIP:
{
  my $maskimg = Imager::i_img_masked_new($img, undef, 0, 0, 150, 150);
  ok($maskimg, "make masked image")
    or skip("couldn't make masked image", 3);

  open FH, "> testout/t103_virt.raw" 
    or die "Cannot create testout/t103_virt.raw: $!";
  binmode FH;
  $IO = Imager::io_new_fd(fileno(FH));
  ok(i_writeraw_wiol($maskimg, $IO), "write virtual raw");
  close FH;

  open FH, "testout/t103_virt.raw"
    or die "Cannot open testout/t103_virt.raw: $!";
  binmode FH;
  $IO = Imager::io_new_fd(fileno(FH));
  my $cmpimgmask = i_readraw_wiol($IO, 150, 150, 3, 3, 0);
  ok($cmpimgmask, "read result of masked write");
  my $diff = i_img_diff($maskimg, $cmpimgmask);
  print "# difference for virtual image $diff\n";
  is($diff, 0, "compare masked to read");

  # check that i_format is set correctly
  my $index = Imager::i_tags_find($cmpimgmask, 'i_format', 0);
  if ($index) {
    my $value = Imager::i_tags_get($cmpimgmask, $index);
    is($value, 'raw', "check i_format value");
  }
  else {
    fail("couldn't find i_format tag");
  }
}

{ # error handling checks
  # should get an error writing to a open for read file
  # make a empty file
  open RAW, "> testout/t103_empty.raw"
    or die "Cannot create testout/t103_empty.raw: $!";
  close RAW;
  open RAW, "< testout/t103_empty.raw"
    or die "Cannot open testout/t103_empty.raw: $!";
  my $im = Imager->new(xsize => 50, ysize=>50);
  ok(!$im->write(fh => \*RAW, type => 'raw', buffered => 0),
     "write to open for read handle");
  cmp_ok($im->errstr, '=~', '^Could not write to file: write\(\) failure', 
	 "check error message");
  close RAW;

  # should get an error reading an empty file
  ok(!$im->read(file => 'testout/t103_empty.raw', xsize => 50, ysize=>50, type=>'raw', interleave => 1),
     'read an empty file');
  is($im->errstr, 'premature end of file', "check message");
 SKIP:
  {
    # see 862083f7e40bc2a9e3b94aedce56c1336e7bdb25 in perl5 git
    $] >= 5.010
      or skip "5.8.x and earlier don't treat a read on a WRONLY file as an error", 2;
    open RAW, "> testout/t103_empty.raw"
      or die "Cannot create testout/t103_empty.raw: $!";
    ok(!$im->read(fh => \*RAW, , xsize => 50, ysize=>50, type=>'raw', interleave => 1),
       'read a file open for write');
    cmp_ok($im->errstr, '=~', '^error reading file: read\(\) failure', "check message");
  }
}


{
  ok(grep($_ eq 'raw', Imager->read_types), "check raw in read types");
  ok(grep($_ eq 'raw', Imager->write_types), "check raw in write types");
}


{ # OO no interleave warning
  my $im = Imager->new;
  my $msg;
  local $SIG{__WARN__} = sub { $msg = "@_" };
  ok($im->read(file => "testout/t103_line_int.raw", xsize => 4, ysize => 4,
	       type => "raw"),
     "read without interleave parameter")
    or print "# ", $im->errstr, "\n";
  ok($msg, "should have warned");
  like($msg, qr/interleave/, "check warning is ok");
  # check we got the right value
  is_color3($im->getpixel(x => 0, y => 0), 0x00, 0x11, 0x22,
	    "check the image was read correctly");

  # check no warning if either is supplied
  $im = Imager->new;
  undef $msg;
  ok($im->read(file => "testout/t103_base.raw", xsize => 4, ysize => 4, type => "raw", interleave => 0), 
     "read with interleave 0");
  is($msg, undef, "no warning");
  is_color3($im->getpixel(x => 0, y => 0), 0x00, 0x11, 0x22,
	    "check read non-interleave");

  $im = Imager->new;
  undef $msg;
  ok($im->read(file => "testout/t103_base.raw", xsize => 4, ysize => 4, type => "raw", raw_interleave => 0), 
     "read with raw_interleave 0");
  is($msg, undef, "no warning");
  is_color3($im->getpixel(x => 1, y => 0), 0x01, 0x12, 0x23,
	    "check read non-interleave");

  # make sure set to 1 is sane
  $im = Imager->new;
  undef $msg;
  ok($im->read(file => "testout/t103_line_int.raw", xsize => 4, ysize => 4, type => "raw", raw_interleave => 1), 
     "read with raw_interleave 1");
  is($msg, undef, "no warning");
  is_color3($im->getpixel(x => 2, y => 0), 0x02, 0x13, 0x24,
	    "check read interleave = 1");
}

{ # invalid interleave error handling
  my $im = Imager->new;
  ok(!$im->read(file => "testout/t103_base.raw", raw_interleave => 2, type => "raw", xsize => 4, ysize => 4),
     "invalid interleave");
  is($im->errstr, "raw_interleave must be 0 or 1", "check message");
}

{ # store/data channel behaviour
  my $im = Imager->new;
  ok($im->read(file => "testout/t103_3to4.raw", xsize => 4, ysize => 4, 
	       raw_datachannels => 4, raw_interleave => 0, type => "raw"),
     "read 4 channel file as 3 channels")
    or print "# ", $im->errstr, "\n";
  is_color3($im->getpixel(x => 2, y => 1), 0x12, 0x23, 0x34,
	    "check read correctly");
}

{ # should fail to read with storechannels > 4
  my $im = Imager->new;
  ok(!$im->read(file => "testout/t103_line_int.raw", type => "raw",
		raw_interleave => 1, xsize => 4, ysize => 4,
		raw_storechannels => 5),
     "read with large storechannels");
  is($im->errstr, "raw_storechannels must be between 1 and 4", 
     "check error message");
}

{ # should zero spare channels if storechannels > datachannels
  my $im = Imager->new;
  ok($im->read(file => "testout/t103_base.raw", type => "raw",
		raw_interleave => 0, xsize => 4, ysize => 4,
		raw_storechannels => 4),
     "read with storechannels > datachannels");
  is($im->getchannels, 4, "should have 4 channels");
  is_color4($im->getpixel(x => 2, y => 1), 0x12, 0x23, 0x34, 0x00,
	    "check last channel zeroed");
}

{
  my @ims = ( basic => test_image(), mono => test_image_mono() );
  push @ims, masked => test_image()->masked();

  my $fail_close = sub {
    Imager::i_push_error(0, "synthetic close failure");
    return 0;
  };

  while (my ($type, $im) = splice(@ims, 0, 2)) {
    my $io = Imager::io_new_cb(sub { 1 }, undef, undef, $fail_close);
    ok(!$im->write(io => $io, type => "raw"),
       "write $type image with a failing close handler");
    like($im->errstr, qr/synthetic close failure/,
	 "check error message");
  }
}

Imager->close_log;

unless ($ENV{IMAGER_KEEP_FILES}) {
  unlink "testout/t103raw.log";
  unlink(qw(testout/t103_base.raw testout/t103_3to4.raw
	    testout/t103_line_int.raw testout/t103_img_int.raw))
}

sub read_test {
  my ($in, $xsize, $ysize, $data, $store, $intrl, $base) = @_;
  open FH, $in or die "Cannot open $in: $!";
  binmode FH;
  my $IO = Imager::io_new_fd( fileno(FH) );

  my $img = i_readraw_wiol($IO, $xsize, $ysize, $data, $store, $intrl);
 SKIP:
  {
    ok($img, "read_test $in read")
      or skip("couldn't read $in", 1);
    is(i_img_diff($img, $baseimg), 0, "read_test $in compare");
  }
}

sub save_data {
  my $outname = shift;
  my $data = load_data();
  open FH, "> $outname" or die "Cannot create $outname: $!";
  binmode FH;
  print FH $data;
  close FH;
}

sub load_data {
  my $hex = '';
  while (<DATA>) {
    next if /^#/;
    last if /^EOF/;
    chomp;
    $hex .= $_;
  }
  $hex =~ tr/ //d;
  my $result = pack("H*", $hex);
  #print unpack("H*", $result),"\n";
  return $result;
}

# FIXME: may need tests for 1,2,4 channel images

__DATA__
# we keep some packed raw images here
# we decode this in the code, ignoring lines starting with #, a subfile
# ends with EOF, data is HEX encoded (spaces ignored)

# basic 3 channel version of the image
001122 011223 021324 031425
102132 112233 122334 132435
203142 213243 223344 233445
304152 314253 324354 334455
EOF

# test image for reading a 4 channel image into a 3 channel image
# 4 x 4 pixels
00112233 01122334 02132435 03142536
10213243 11223344 12233445 13243546
20314253 21324354 22334455 23344556
30415263 31425364 32435465 33445566
EOF

# test image for line based interlacing
# 4 x 4 pixels
# first line
00 01 02 03
11 12 13 14
22 23 24 25

# second line
10 11 12 13
21 22 23 24
32 33 34 35

# third line
20 21 22 23
31 32 33 34
42 43 44 45

# fourth line
30 31 32 33
41 42 43 44
52 53 54 55

EOF

# test image for image based interlacing
# first channel
00 01 02 03
10 11 12 13
20 21 22 23
30 31 32 33

# second channel
11 12 13 14
21 22 23 24
31 32 33 34
41 42 43 44

# third channel
22 23 24 25
32 33 34 35
42 43 44 45
52 53 54 55

EOF
