#!perl -w
use strict;
use Imager;
use Test::More tests => 40;

sub get_data;

{ # test file limits are obeyed (paletted)
  Imager->set_file_limits(reset => 1, width => 10);
  my $im = Imager->new;
  ok(!$im->read(file => 'testimg/pal13232.ico'), "can't read overwide image");
  like($im->errstr, qr/image width/, "check message");
}

{ # test file limits are obeyed (direct)
  Imager->set_file_limits(reset => 1, width => 10);
  my $im = Imager->new;
  ok(!$im->read(file => 'testimg/rgba3232.ico'), "can't read overwide image");
  like($im->errstr, qr/image width/, "check message");
}

Imager->set_file_limits(reset => 1);

{ # file too short for magic
  my $im = Imager->new;
  ok(!$im->read(data=>"XXXX", type=>'ico'), "Can't read short image file");
  is($im->errstr, "error opening ICO/CUR file: Short read", 
     "check error message");
}

{ # read non-icon
  my $im = Imager->new;
  ok(!$im->read(file=>'t/t50readfail.t', type=>'ico'),
     "script isn't an icon");
  is($im->errstr, "error opening ICO/CUR file: Not an icon file", 
     "check message");
}

{ # file with not enough icon structures
  my $im = Imager->new;
  my $data = pack "H*", "00000100010000";
  ok(!$im->read(data => $data, type=>'ico'), 
     "ico file broken at resource entries");
  is($im->errstr, "error opening ICO/CUR file: Short read",
     "check error message");
}
{
  my $im = Imager->new;
  my $data = pack "H*", "00000200010000";
  ok(!$im->read(data => $data, type=>'cur'), 
     "cursor file broken at resource entries");
  is($im->errstr, "error opening ICO/CUR file: Short read",
     "check error message");
}

{ # read negative index image
  my $im = Imager->new;
  ok(!$im->read(file=>'testimg/pal13232.ico', type=>'ico', page=>-1),
     "read page -1");
  is($im->errstr, "error reading ICO/CUR image: Image index out of range", 
     "check error message");
}

{ # read too high image index
  my $im = Imager->new;
  ok(!$im->read(file=>'testimg/pal13232.ico', type=>'ico', page=>1),
     "read page 1");
  is($im->errstr, "error reading ICO/CUR image: Image index out of range",
     "check error message");
}

{ # image offset beyond end of file
  my $im = Imager->new;
  my $data = get_data <<EOS;
; header - icon with 1 image
0000 0100 0100
; image record 32 x 32, offset 0xFFFF
20 20 00 00 0000 0000 00200000 FFFF0000
EOS
  ok(!$im->read(data => $data, type=>'ico'), 
     "read from icon with bad offset");
  # bad offset causes the seek to fail on an in-memory "file"
  # it may not fail this way on a real file.
  is($im->errstr, "error reading ICO/CUR image: I/O error", 
     "check error message");
}

{ # short read on bmiheader
  my $im = Imager->new;
  my $data = get_data <<EOS;
; header - icon with 1 image
0000 0100 0100
; image record 32 x 32, offset 0xFFFF
20 20 00 00 0000 0000 00200000 16000000
; bmiheader for the first image
2800 0000 2000 0000 4000 0000 ; size, width, height
; short here
EOS
  ok(!$im->read(data => $data, type=>'ico'), 
     "read from icon with a short bitmap header");
  is($im->errstr, "error reading ICO/CUR image: Short read",
     "check error message");
}

{ # invalid bmiheader
  my $im = Imager->new;
  my $data = get_data <<EOS;
; header - icon with 1 image
0000 0100 0100
; image record 32 x 32, offset 0xFFFF
20 20 00 00 0000 0000 00200000 16000000
; bmiheader for the first image
2000 0000 2000 0000 4000 0000 ; size should be 0x28, width, height
0100 2000 ; planes, bit count
; data we read but ignore
0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000
EOS
  ok(!$im->read(data => $data, type=>'ico'), 
     "read from icon with an invalid sub-image header");
  is($im->errstr, "error reading ICO/CUR image: Not an icon file",
     "check error message");
}

{ # invalid bit count for "direct" image
  my $im = Imager->new;
  my $data = get_data <<EOS;
; header - icon with 1 image
0000 0100 0100
; image record 32 x 32, offset 0xFFFF
20 20 00 00 0000 0000 00200000 16000000
; bmiheader for the first image
2800 0000 2000 0000 4000 0000 ; size, width, height
0100 2100 ; planes, bit count
; data we read but ignore
0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000
EOS
  ok(!$im->read(data => $data, type=>'ico'), 
     "read from icon with an invalid 'direct' bits per pixel");
  is($im->errstr, "error reading ICO/CUR image: Unknown value for bits/pixel", 
     "check error message");
}

{ # short file reading palette
  my $im = Imager->new;
  my $data = get_data <<EOS;
; header - icon with 1 image
0000 0100 0100
; image record 32 x 32, offset 0xFFFF
20 20 00 00 0000 0000 00200000 16000000
; bmiheader for the first image
2800 0000 2000 0000 4000 0000 ; size, width, height
0100 0100 ; planes, bit count == 1
; data we read but ignore
0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000
; dummy palette - one color but 2 needed
FFFFFF00
EOS
  ok(!$im->read(data => $data, type=>'ico'), 
     "read from icon with short palette");
  is($im->errstr, "error reading ICO/CUR image: Short read",
     "check error message");
}

{ # short file reading 1 bit image data
  my $im = Imager->new;
  my $data = get_data <<EOS;
; header - icon with 1 image
0000 0100 0100
; image record 32 x 32, offset 0x20
20 20 00 00 0000 0000 00200000 16000000
; bmiheader for the first image
2800 0000 2000 0000 4000 0000 ; size, width, height
0100 0100 ; planes, bit count == 1
; data we read but ignore
0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000
; palette
00000000
FFFFFF00
; image data - short
00 ff
EOS
  ok(!$im->read(data => $data, type=>'ico'), 
     "read from icon with short image data (1 bit)");
  is($im->errstr, "error reading ICO/CUR image: Short read",
     "check error message");
}

{ # short file reading 32 bit image data
  my $im = Imager->new;
  my $data = get_data <<EOS;
; header - icon with 1 image
0000 0100 0100
; image record 32 x 32, offset 0x20
20 20 00 00 0000 0000 00200000 16000000
; bmiheader for the first image
2800 0000 2000 0000 4000 0000 ; size, width, height
0100 2000 ; planes, bit count == 32
; data we read but ignore
0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000
; nopalette
; image data - short
FFFFFFFF 
EOS
  ok(!$im->read(data => $data, type=>'ico'), 
     "read from icon with short image data (32 bit)");
  is($im->errstr, "error reading ICO/CUR image: Short read",
     "check error message");
}

{ # short file reading 4 bit image data
  my $im = Imager->new;
  my $data = get_data <<EOS;
; header - icon with 1 image
0000 0100 0100
; image record 32 x 32, offset 0x20
20 20 00 00 0000 0000 00200000 16000000
; bmiheader for the first image
2800 0000 2000 0000 4000 0000 ; size, width, height
0100 0400 ; planes, bit count == 4
; data we read but ignore
0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000
; 16-color palette
00000000 FFFFFF00 00000000 FFFFFF00
00000000 FFFFFF00 00000000 FFFFFF00
00000000 FFFFFF00 00000000 FFFFFF00
00000000 FFFFFF00 00000000 FFFFFF00
; image data - short
FFFFFFFF 
EOS
  ok(!$im->read(data => $data, type=>'ico'), 
     "read from icon with short image data (4 bit)");
  is($im->errstr, "error reading ICO/CUR image: Short read",
     "check error message");
}

{ # short file reading 8 bit image data
  my $im = Imager->new;
  # base image header + palette + a little data
  my $data = get_data <<EOS . "FFFFFFFF" x 256 . "FFFF FFFF";
; header - icon with 1 image
0000 0100 0100
; image record 32 x 32, offset 0x20
20 20 00 00 0000 0000 00200000 16000000
; bmiheader for the first image
2800 0000 2000 0000 4000 0000 ; size, width, height
0100 0800 ; planes, bit count == 8
; data we read but ignore
0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000
EOS;
; palette and data above
EOS
  ok(!$im->read(data => $data, type=>'ico'), 
     "read from icon with short image data (8 bit)");
  is($im->errstr, "error reading ICO/CUR image: Short read",
     "check error message");
}

{ # short file reading mask data
  my $im = Imager->new;
  my $data = get_data <<EOS;
; header - icon with 1 image
0000 0100 0100
; image record 16 x 16, 2 colors, reserved=0, planes=1,
; sizeinbytes (ignored), offset 0x16
10 10 02 00 0100 0100 00000000 16000000
; bmiheader for the first image
2800 0000 1000 0000 2000 0000 ; size, width, height
0100 0100 ; planes, bit count == 1
; data we read but ignore
0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000
; palette
00000000
FFFFFF00
; image data - 16 x 16 bits
; note that each line needs to be aligned on a 32-bit boundary
00ff00ff 00000000
00ff00ff 00000000
00ff00ff 00000000
00ff00ff 00000000
00ff00ff 00000000
00ff00ff 00000000
00ff00ff 00000000
00ff00ff 00000000
00ff00ff 00000000
00ff00ff 00000000
00ff00ff 00000000
00ff00ff 00000000
00ff00ff 00000000
00ff00ff 00000000
00ff00ff 00000000
00ff00ff 00000000
; mask, short
0ff0
EOS
  ok(!$im->read(data => $data, type=>'ico'), 
     "read from icon with short mask data");
  is($im->errstr, "error reading ICO/CUR image: Short read",
     "check error message");
}

{ # fail opening on a multi-read
  ok(!Imager->read_multi(file=>'t/t50readfail.t', type=>'ico'),
     "multi-read on non-icon");
  is(Imager->errstr, "error opening ICO/CUR file: Not an icon file", 
     "check message");
}

{ # invalid bit count for "direct" image (read_multi)
  my $data = get_data <<EOS;
; header - icon with 1 image
0000 0100 0100
; image record 32 x 32, offset 0xFFFF
20 20 00 00 0000 0000 00200000 16000000
; bmiheader for the first image
2800 0000 2000 0000 4000 0000 ; size, width, height
0100 2100 ; planes, bit count
; data we read but ignore
0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000
EOS
  ok(!Imager->read_multi(data => $data, type=>'ico'), 
     "read from icon with an invalid 'direct' bits per pixel (multi)");
  is(Imager->errstr, 
     "error reading ICO/CUR image: Unknown value for bits/pixel", 
     "check error message");
}


# extract hex data from text
# allows comments
sub get_data {
  my ($src) = @_;

  $src =~ s/[\#;].*//mg;
  $src =~ tr/0-9A-F//cd;

  pack("H*", $src);
}
