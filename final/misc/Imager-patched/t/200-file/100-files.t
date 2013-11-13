#!perl -w

# This file is for testing file functionality that is independent of
# the file format

use strict;
use Test::More tests => 89;
use Imager;

-d "testout" or mkdir "testout";

Imager->open_log(log => "testout/t1000files.log");

SKIP:
{
  # Test that i_test_format_probe() doesn't pollute stdout

  # Initally I tried to write this test using open to redirect files,
  # but there was a buffering problem that made it so the data wasn't
  # being written to the output file.  This external perl call avoids
  # that problem

  my $test_script = 'testout/t1000files_probe.pl';

  # build a temp test script to use
  ok(open(SCRIPT, "> $test_script"), "open test script")
    or skip("no test script $test_script: $!", 2);
  print SCRIPT <<'PERL';
#!perl
use Imager;
use strict;
my $file = shift or die "No file supplied";
open FH, "< $file" or die "Cannot open file: $!";
binmode FH;
my $io = Imager::io_new_fd(fileno(FH));
Imager::i_test_format_probe($io, -1);
PERL
  close SCRIPT;
  my $perl = $^X;
  $perl = qq/"$perl"/ if $perl =~ / /;
  
  print "# script: $test_script\n";
  my $cmd = "$perl -Mblib $test_script t/200-file/100-files.t";
  print "# command: $cmd\n";

  my $out = `$cmd`;
  is($?, 0, "command successful");
  is($out, '', "output should be empty");
}

# test the file limit functions
# by default the limits are zero (unlimited)
print "# image file limits\n";
is_deeply([ Imager->get_file_limits() ], [0, 0, 0x40000000 ],
	  "check defaults");
ok(Imager->set_file_limits(width=>100), "set only width");
is_deeply([ Imager->get_file_limits() ], [100, 0, 0x40000000 ],
	  "check width set");
ok(Imager->set_file_limits(height=>150, bytes=>10000),
   "set height and bytes");
is_deeply([ Imager->get_file_limits() ], [ 100, 150, 10000 ],
	  "check all values now set");
ok(Imager->check_file_limits(width => 100, height => 30),
   "check 100 x 30 (def channels, sample_size) ok")
  or diag(Imager->errstr);
ok(Imager->check_file_limits(width => 100, height => 100, channels => 1),
   "check 100 x 100 x 1 (def sample_size) ok")
  or diag(Imager->errstr);
ok(Imager->check_file_limits(width => 100, height => 100, channels => 1),
   "check 100 x 100 x 1 (def sample_size) ok")
  or diag(Imager->errstr);
ok(!Imager->check_file_limits(width => 100, height => 100, channels => 1, sample_size => "float"),
   "check 100 x 100 x 1 x float should fail");
ok(!Imager->check_file_limits(width => 100, height => 100, channels => 0),
   "0 channels should fail");
is(Imager->errstr, "file size limit - channels 0 out of range",
   "check error message");
ok(!Imager->check_file_limits(width => 0, height => 100),
   "0 width should fail");
is(Imager->errstr, "file size limit - image width of 0 is not positive",
   "check error message");
ok(!Imager->check_file_limits(width => 100, height => 0),
   "0 height should fail");
is(Imager->errstr, "file size limit - image height of 0 is not positive",
   "check error message");
ok(!Imager->check_file_limits(width => 10, height => 10, sample_size => 0),
   "0 sample_size should fail");
is(Imager->errstr, "file size limit - sample_size 0 out of range",
   "check error message");
ok(!Imager->check_file_limits(width => 10, height => 10, sample_size => 1000),
   "1000 sample_size should fail");
is(Imager->errstr, "file size limit - sample_size 1000 out of range",
   "check error message");
ok(Imager->set_file_limits(reset=>1, height => 99),
   "set height and reset");
is_deeply([ Imager->get_file_limits() ], [ 0, 99, 0x40000000 ],
	  "check only height is set");
ok(Imager->set_file_limits(reset=>1),
   "just reset");
is_deeply([ Imager->get_file_limits() ], [ 0, 0, 0x40000000 ],
	  "check all are reset");

# bad parameters
is_deeply([ Imager->check_file_limits() ], [],
	  "missing size paramaters");
is(Imager->errstr, "check_file_limits: width must be defined",
   "check message");
is_deeply([ Imager->check_file_limits(width => 100.5) ], [],
	  "non-integer parameter");
is(Imager->errstr, "check_file_limits: width must be a positive integer",
   "check message");

# test error handling for loading file handers
{
  # first, no module at all
  {
    my $data = "abc";
    ok(!Imager->new(data => $data, filetype => "unknown"),
       "try to read an unknown file type");
   like(Imager->errstr, qr(^format 'unknown' not supported - formats .* - Can't locate Imager/File/UNKNOWN.pm or Imager/File/UNKNOWNReader.pm$),
	"check error message");
  }
  {
    my $data;
    my $im = Imager->new(xsize => 10, ysize => 10);
    ok(!$im->write(data => \$data, type => "unknown"),
       "try to write an unknown file type");
   like($im->errstr, qr(^format 'unknown' not supported - formats .* - Can't locate Imager/File/UNKNOWN.pm or Imager/File/UNKNOWNWriter.pm$),
	"check error message");
  }
  push @INC, "t/t1000lib";
  {
    my $data = "abc";
    ok(!Imager->new(data => $data, filetype => "bad"),
       "try to read an bad (other load failure) file type");
   like(Imager->errstr, qr(^format 'bad' not supported - formats .* available for reading - This module fails to load loading Imager/File/BAD.pm$),
	"check error message");
  }
  {
    my $data;
    my $im = Imager->new(xsize => 10, ysize => 10);
    ok(!$im->write(data => \$data, type => "bad"),
       "try to write an bad file type");
   like($im->errstr, qr(^format 'bad' not supported - formats .* available for writing - This module fails to load loading Imager/File/BAD.pm$),
	"check error message");
  }
}

{ # test empty image handling for write()/write_multi()
  my $empty = Imager->new;
  my $data;
  ok(!$empty->write(data => \$data, type => "pnm"),
     "fail to write an empty image");
  is($empty->errstr, "write: empty input image", "check error message");
  my $good = Imager->new(xsize => 1, ysize => 1);
  ok(!Imager->write_multi({ data => \$data, type => "pnm" }, $good, $empty),
     "fail to write_multi an empty image");
  is(Imager->errstr, "write_multi: empty input image (image 2)");
}

# check file type probe
probe_ok("49492A41", undef, "not quite tiff");
probe_ok("4D4D0041", undef, "not quite tiff");
probe_ok("49492A00", "tiff", "tiff intel");
probe_ok("4D4D002A", "tiff", "tiff motorola");
probe_ok("474946383961", "gif", "gif 89");
probe_ok("474946383761", "gif", "gif 87");
probe_ok(<<TGA, "tga", "TGA");
00 00 0A 00 00 00 00 00 00 00 00 00 96 00 96 00
18 20 FF 00 00 00 95 00 00 00 FF 00 00 00 95 00
00 00 FF 00 00 00 95 00 00 00 FF 00 00 00 95 00
00 00 FF 00 00 00 95 00 00 00 FF 00 00 00 95 00
TGA

probe_ok(<<TGA, "tga", "TGA 32-bit");
00 00 0A 00 00 00 00 00 00 00 00 00 0A 00 0A 00
20 08 84 00 00 00 00 84 FF FF FF FF 84 00 00 00
00 84 FF FF FF FF 84 00 00 00 00 84 FF FF FF FF
TGA

probe_ok(<<ICO, "ico", "Windows Icon");
00 00 01 00 02 00 20 20 10 00 00 00 00 00 E8 02
00 00 26 00 00 00 20 20 00 00 00 00 00 00 A8 08
00 00 0E 03 00 00 28 00 00 00 20 00 00 00 40 00
ICO

probe_ok(<<ICO, "cur", "Windows Cursor");
00 00 02 00 02 00 20 20 10 00 00 00 00 00 E8 02
00 00 26 00 00 00 20 20 00 00 00 00 00 00 A8 08
00 00 0E 03 00 00 28 00 00 00 20 00 00 00 40 00
ICO

probe_ok(<<SGI, "sgi", "SGI RGB");
01 DA 01 01 00 03 00 96 00 96 00 03 00 00 00 00 
00 00 00 FF 00 00 00 00 6E 6F 20 6E 61 6D 65 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
SGI

probe_ok(<<ILBM, "ilbm", "ILBM");
46 4F 52 4D 00 00 60 7A 49 4C 42 4D 42 4D 48 44
00 00 00 14 00 96 00 96 00 00 00 00 18 00 01 80
00 00 0A 0A 00 96 00 96 42 4F 44 59 00 00 60 51
ILBM

probe_ok(<<XPM, "xpm", "XPM");
2F 2A 20 58 50 4D 20 2A 2F 0A 73 74 61 74 69 63
20 63 68 61 72 20 2A 6E 6F 6E 61 6D 65 5B 5D 20
3D 20 7B 0A 2F 2A 20 77 69 64 74 68 20 68 65 69
XPM

probe_ok(<<PCX, "pcx", 'PCX');
0A 05 01 08 00 00 00 00 95 00 95 00 96 00 96 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
PCX

probe_ok(<<FITS, "fits", "FITS");
53 49 4D 50 4C 45 20 20 3D 20 20 20 20 20 20 20 
20 20 20 20 20 20 20 20 20 20 20 20 20 54 20 20 
20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 
FITS

probe_ok(<<PSD, "psd", "Photoshop");
38 42 50 53 00 01 00 00 00 00 00 00 00 06 00 00
00 3C 00 00 00 96 00 08 00 03 00 00 00 00 00 00
0B E6 38 42 49 4D 03 ED 00 00 00 00 00 10 00 90
PSD

probe_ok(<<EPS, "eps", "Encapsulated Postscript");
25 21 50 53 2D 41 64 6F 62 65 2D 32 2E 30 20 45
50 53 46 2D 32 2E 30 0A 25 25 43 72 65 61 74 6F
72 3A 20 70 6E 6D 74 6F 70 73 0A 25 25 54 69 74
EPS

probe_ok(<<UTAH, "utah", "Utah RLE");
52 CC 00 00 00 00 0A 00 0A 00 0A 03 08 00 08 00 
2F 00 48 49 53 54 4F 52 59 3D 70 6E 6D 74 6F 72 
6C 65 20 6F 6E 20 54 68 75 20 4D 61 79 20 31 31 
20 31 36 3A 33 35 3A 34 33 20 32 30 30 36 0A 09 
UTAH

probe_ok(<<XWD, "xwd", "X Window Dump");
00 00 00 69 00 00 00 07 00 00 00 02 00 00 00 18
00 00 01 E4 00 00 01 3C 00 00 00 00 00 00 00 00
00 00 00 20 00 00 00 00 00 00 00 20 00 00 00 20
00 00 07 90 00 00 00 04 00 FF 00 00 00 00 FF 00
XWD

probe_ok(<<GZIP, "gzip", "gzip compressed");
1F 8B 08 08 C2 81 BD 44 02 03 49 6D 61 67 65 72
2D 30 2E 35 31 5F 30 33 2E 74 61 72 00 EC 5B 09
40 53 C7 BA 9E 24 AC 01 D9 44 04 44 08 8B B2 8A
C9 C9 42 92 56 41 50 20 A0 02 41 41 01 17 48 80
GZIP

probe_ok(<<BZIP2, "bzip2", "bzip2 compressed");
42 5A 68 39 31 41 59 26 53 59 0F D8 8C 09 00 03
28 FF FF FF FF FB 7F FB 77 FF EF BF 6B 7F BE FF
FF DF EE C8 0F FF F3 FF FF FF FC FF FB B1 FF FB
F4 07 DF D0 03 B8 03 60 31 82 05 2A 6A 06 83 20
BZIP2

probe_ok(<<WEBP, "webp", "Google WEBP");
52 49 46 46 2C 99 00 00 57 45 42 50 56 50 38 20
20 99 00 00 70 7A 02 9D 01 2A E0 01 80 02 00 87
08 85 85 88 85 84 88 88 83 AF E2 F7 64 1F 98 55
1B 6A 70 F5 8A 45 09 95 0C 09 7E 25 D9 2E 46 44
07 84 FB 01 FD 2C 8A 2F 97 CC ED DB 50 0F 11 3B
WEBP

probe_ok(<<JPEG2K, "jp2", "JPEG 2000");
00 00 00 0C 6A 50 20 20 0D 0A 87 0A 00 00 00 14
66 74 79 70 6A 70 32 20 00 00 00 00 6A 70 32 20
00 00 00 2D 6A 70 32 68 00 00 00 16 69 68 64 72
00 00 02 80 00 00 01 E0 00 03 07 07 00 00 00 00
00 0F 63 6F 6C 72 01 00 00 00 00 00 10 00 00 00
00 6A 70 32 63 FF 4F FF 51 00 2F 00 00 00 00 01
JPEG2K

{ # RT 72475
  # check error messages from read/read_multi
  my $data = "nothing useful";
  my @mult_data = Imager->read_multi(data => $data);
  is(@mult_data, 0, "read_multi with non-image input data should fail");
  is(Imager->errstr,
     "type parameter missing and it couldn't be determined from the file contents",
     "check the error message");

  my @mult_file = Imager->read_multi(file => "t/200-file/100-files.t");
  is(@mult_file, 0, "read_multi with non-image filename should fail");
  is(Imager->errstr,
     "type parameter missing and it couldn't be determined from the file contents or file name",
     "check the error message");

  my $im = Imager->new;
  ok(!$im->read(data => $data), "read from non-image data should fail");
  is($im->errstr,
     "type parameter missing and it couldn't be determined from the file contents",
     "check the error message");

  ok(!$im->read(file => "t/200-file/100-files.t"),
     "read from non-image file should fail");
  is($im->errstr,
     "type parameter missing and it couldn't be determined from the file contents or file name",
     "check the error message");
}

{
  # test def_guess_type
  my @tests =
    (
     pnm => "pnm",
     GIF => "gif",
     tif => "tiff",
     TIFF => "tiff",
     JPG => "jpeg",
     rle => "utah",
     bmp => "bmp",
     dib => "bmp",
     rgb => "sgi",
     BW => "sgi",
     TGA => "tga",
     CUR => "cur",
     ico => "ico",
     ILBM => "ilbm",
     pcx => "pcx",
     psd => "psd",
    );

  while (my ($ext, $expect) = splice(@tests, 0, 2)) {
    my $filename = "foo.$ext";
    is(Imager::def_guess_type($filename), $expect,
       "type for $filename should be $expect");
  }
}

Imager->close_log;

unless ($ENV{IMAGER_KEEP_FILES}) {
  unlink "testout/t1000files.log";
}

sub probe_ok {
  my ($packed, $exp_type, $name) = @_;

  my $builder = Test::Builder->new;
  $packed =~ tr/ \r\n//d; # remove whitespace used for layout
  my $data = pack("H*", $packed);

  my $io = Imager::io_new_buffer($data);
  my $result = Imager::i_test_format_probe($io, -1);

  return $builder->is_eq($result, $exp_type, $name)
}
