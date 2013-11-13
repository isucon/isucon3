#!perl -w
use Imager ':all';
use Test::More tests => 205;
use strict;
use Imager::Test qw(test_image_raw test_image_16 is_color3 is_color1 is_image test_image_named);

$| = 1;

-d "testout" or mkdir "testout";

Imager->open_log(log => "testout/t104ppm.log");

my $green = i_color_new(0,255,0,255);
my $blue  = i_color_new(0,0,255,255);
my $red   = i_color_new(255,0,0,255);

my @files;

my $img    = test_image_raw();

my $fh = openimage(">testout/t104.ppm");
push @files, "t104.ppm";
my $IO = Imager::io_new_fd(fileno($fh));
ok(i_writeppm_wiol($img, $IO), "write pnm low")
  or die "Cannot write testout/t104.ppm\n";
close($fh);

$IO = Imager::io_new_bufchain();
ok(i_writeppm_wiol($img, $IO), "write to bufchain")
  or die "Cannot write to bufchain";
my $data = Imager::io_slurp($IO);

$fh = openimage("testout/t104.ppm");
$IO = Imager::io_new_fd( fileno($fh) );
my $cmpimg = i_readpnm_wiol($IO,-1);
ok($cmpimg, "read image we wrote")
  or die "Cannot read testout/t104.ppm\n";
close($fh);

is(i_img_diff($img, $cmpimg), 0, "compare written and read images");

my $rdata = slurp("testout/t104.ppm");
is($data, $rdata, "check data read from file and bufchain data");

# build a grayscale image
my $gimg = Imager::ImgRaw::new(150, 150, 1);
my $gray = i_color_new(128, 0, 0, 255);
my $dgray = i_color_new(64, 0, 0, 255);
my $white = i_color_new(255, 0, 0, 255);
i_box_filled($gimg, 20, 20, 130, 130, $gray);
i_box_filled($gimg, 40, 40, 110, 110, $dgray);
i_arc($gimg, 75, 75, 30, 0, 361, $white);

push @files, "t104_gray.pgm";
open FH, "> testout/t104_gray.pgm" or die "Cannot create testout/t104_gray.pgm: $!\n";
binmode FH;
$IO = Imager::io_new_fd(fileno(FH));
ok(i_writeppm_wiol($gimg, $IO), "write grayscale");
close FH;

open FH, "< testout/t104_gray.pgm" or die "Cannot open testout/t104_gray.pgm: $!\n";
binmode FH;
$IO = Imager::io_new_fd(fileno(FH));
my $gcmpimg = i_readpnm_wiol($IO, -1);
ok($gcmpimg, "read grayscale");
is(i_img_diff($gimg, $gcmpimg), 0, 
   "compare written and read greyscale images");

my $ooim = Imager->new;
ok($ooim->read(file=>"testimg/simple.pbm"), "read simple pbm, via OO")
  or print "# ", $ooim->errstr, "\n";

check_gray(Imager::i_get_pixel($ooim->{IMG}, 0, 0), 0);
check_gray(Imager::i_get_pixel($ooim->{IMG}, 0, 1), 255);
check_gray(Imager::i_get_pixel($ooim->{IMG}, 1, 0), 255);
check_gray(Imager::i_get_pixel($ooim->{IMG}, 1, 1), 0);
is($ooim->type, 'paletted', "check pbm read as paletted");
is($ooim->tags(name=>'pnm_type'), 1, "check pnm_type tag");

{
  # https://rt.cpan.org/Ticket/Display.html?id=7465
  # the pnm reader ignores the maxval that it reads from the pnm file
  my $maxval = Imager->new;
  ok($maxval->read(file=>"testimg/maxval.ppm"),
     "read testimg/maxval.ppm");
  
  # this image contains three pixels, with each sample from 0 to 63
  # the pixels are (63, 63, 63), (32, 32, 32) and (31, 31, 0)
  
  # check basic parameters
  is($maxval->getchannels, 3, "channel count");
  is($maxval->getwidth, 3, "width");
  is($maxval->getheight, 1, "height");
  
  # check the pixels
  ok(my ($white, $grey, $green) = $maxval->getpixel('x'=>[0,1,2], 'y'=>[0,0,0]), "fetch pixels");
  is_color3($white, 255, 255, 255, "white pixel");
  is_color3($grey,  130, 130, 130, "grey  pixel");
  is_color3($green, 125, 125, 0,   "green pixel");
  is($maxval->tags(name=>'pnm_type'), 6, "check pnm_type tag on maxval");

  # and do the same for ASCII images
  my $maxval_asc = Imager->new;
  ok($maxval_asc->read(file=>"testimg/maxval_asc.ppm"),
     "read testimg/maxval_asc.ppm");
  
  # this image contains three pixels, with each sample from 0 to 63
  # the pixels are (63, 63, 63), (32, 32, 32) and (31, 31, 0)
  
  # check basic parameters
  is($maxval_asc->getchannels, 3, "channel count");
  is($maxval_asc->getwidth, 3, "width");
  is($maxval_asc->getheight, 1, "height");

  is($maxval->tags(name=>'pnm_type'), 6, "check pnm_type tag on maxval");
  
  # check the pixels
  ok(my ($white_asc, $grey_asc, $green_asc) = $maxval_asc->getpixel('x'=>[0,1,2], 'y'=>[0,0,0]), "fetch pixels");
  is_color3($white_asc, 255, 255, 255, "white asc pixel");
  is_color3($grey_asc,  130, 130, 130, "grey  asc pixel");
  is_color3($green_asc, 125, 125, 0,   "green asc pixel");
}

{ # previously we didn't validate maxval at all, make sure it's
  # validated now
  my $maxval0 = Imager->new;
  ok(!$maxval0->read(file=>'testimg/maxval_0.ppm'),
     "should fail to read maxval 0 image");
  print "# ", $maxval0->errstr, "\n";
  like($maxval0->errstr, qr/maxval is zero - invalid pnm file/,
       "error expected from reading maxval_0.ppm");

  my $maxval65536 = Imager->new;
  ok(!$maxval65536->read(file=>'testimg/maxval_65536.ppm'),
     "should fail reading maxval 65536 image");
  print "# ",$maxval65536->errstr, "\n";
  like($maxval65536->errstr, qr/maxval of 65536 is over 65535 - invalid pnm file/,
       "error expected from reading maxval_65536.ppm");

  # maxval of 256 is valid, and handled as of 0.56
  my $maxval256 = Imager->new;
  ok($maxval256->read(file=>'testimg/maxval_256.ppm'),
     "should succeed reading maxval 256 image");
  is_color3($maxval256->getpixel(x => 0, 'y' => 0),
            0, 0, 0, "check black in maxval_256");
  is_color3($maxval256->getpixel(x => 0, 'y' => 1),
            255, 255, 255, "check white in maxval_256");
  is($maxval256->bits, 16, "check bits/sample on maxval 256");

  # make sure we handle maxval > 255 for ascii
  my $maxval4095asc = Imager->new;
  ok($maxval4095asc->read(file=>'testimg/maxval_4095_asc.ppm'),
     "read maxval_4095_asc.ppm");
  is($maxval4095asc->getchannels, 3, "channels");
  is($maxval4095asc->getwidth, 3, "width");
  is($maxval4095asc->getheight, 1, "height");
  is($maxval4095asc->bits, 16, "check bits/sample on maxval 4095");

  ok(my ($white, $grey, $green) = $maxval4095asc->getpixel('x'=>[0,1,2], 'y'=>[0,0,0]), "fetch pixels");
  is_color3($white, 255, 255, 255, "white 4095 pixel");
  is_color3($grey,  128, 128, 128, "grey  4095 pixel");
  is_color3($green, 127, 127, 0,   "green 4095 pixel");
}

{ # check i_format is set when reading a pnm file
  # doesn't really matter which file.
  my $maxval = Imager->new;
  ok($maxval->read(file=>"testimg/maxval.ppm"),
      "read test file");
  my ($type) = $maxval->tags(name=>'i_format');
  is($type, 'pnm', "check i_format");
}

{ # check file limits are checked
  my $limit_file = "testout/t104.ppm";
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

{
  # check we correctly sync with the data stream
  my $im = Imager->new;
  ok($im->read(file => 'testimg/pgm.pgm', type => 'pnm'),
     "read pgm.pgm")
    or print "# cannot read pgm.pgm: ", $im->errstr, "\n";
  print "# ", $im->getsamples('y' => 0), "\n";
  is_color1($im->getpixel(x=>0, 'y' => 0), 254, "check top left");
}

{ # check error messages set correctly
  my $im = Imager->new;
  ok(!$im->read(file=>'t/200-file/310-pnm.t', type=>'pnm'),
     'should fail to read script as an image file');
  is($im->errstr, 'unable to read pnm image: bad header magic, not a PNM file',
     "check error message");
}

{
  # RT #30074
  # give 4/2 channel images a background color when saving to pnm
  my $im = Imager->new(xsize=>16, ysize=>16, channels=>4);
  $im->box(filled => 1, xmin => 8, color => '#FFE0C0');
  $im->box(filled => 1, color => NC(0, 192, 192, 128),
	   ymin => 8, xmax => 7);
  push @files, "t104_alpha.ppm";
  ok($im->write(file=>"testout/t104_alpha.ppm", type=>'pnm'),
     "should succeed writing 4 channel image");
  my $imread = Imager->new;
  ok($imread->read(file => 'testout/t104_alpha.ppm'), "read it back")
    or print "# ", $imread->errstr, "\n";
  is_color3($imread->getpixel('x' => 0, 'y' => 0), 0, 0, 0, 
	    "check transparent became black");
  is_color3($imread->getpixel('x' => 8, 'y' => 0), 255, 224, 192,
	    "check color came through");
  is_color3($imread->getpixel('x' => 0, 'y' => 15), 0, 96, 96,
	    "check translucent came through");
  my $data;
  ok($im->write(data => \$data, type => 'pnm', i_background => '#FF0000'),
     "write with red background");
  ok($imread->read(data => $data, type => 'pnm'),
     "read it back");
  is_color3($imread->getpixel('x' => 0, 'y' => 0), 255, 0, 0, 
	    "check transparent became red");
  is_color3($imread->getpixel('x' => 8, 'y' => 0), 255, 224, 192,
	    "check color came through");
  is_color3($imread->getpixel('x' => 0, 'y' => 15), 127, 96, 96,
	    "check translucent came through");
}

{
  # more RT #30074 - 16 bit images
  my $im = Imager->new(xsize=>16, ysize=>16, channels=>4, bits => 16);
  $im->box(filled => 1, xmin => 8, color => '#FFE0C0');
  $im->box(filled => 1, color => NC(0, 192, 192, 128),
	   ymin => 8, xmax => 7);
  push @files, "t104_alp16.ppm";
  ok($im->write(file=>"testout/t104_alp16.ppm", type=>'pnm', 
		pnm_write_wide_data => 1),
     "should succeed writing 4 channel image");
  my $imread = Imager->new;
  ok($imread->read(file => 'testout/t104_alp16.ppm'), "read it back");
  is($imread->bits, 16, "check we did produce a 16 bit image");
  is_color3($imread->getpixel('x' => 0, 'y' => 0), 0, 0, 0, 
	    "check transparent became black");
  is_color3($imread->getpixel('x' => 8, 'y' => 0), 255, 224, 192,
	    "check color came through");
  is_color3($imread->getpixel('x' => 0, 'y' => 15), 0, 96, 96,
	    "check translucent came through");
  my $data;
  ok($im->write(data => \$data, type => 'pnm', i_background => '#FF0000',
		pnm_write_wide_data => 1),
     "write with red background");
  ok($imread->read(data => $data, type => 'pnm'),
     "read it back");
  is($imread->bits, 16, "check it's 16-bit");
  is_color3($imread->getpixel('x' => 0, 'y' => 0), 255, 0, 0, 
	    "check transparent became red");
  is_color3($imread->getpixel('x' => 8, 'y' => 0), 255, 224, 192,
	    "check color came through");
  is_color3($imread->getpixel('x' => 0, 'y' => 15), 127, 96, 96,
	    "check translucent came through");
}

# various bad input files
print "# check error handling\n";
{
  my $im = Imager->new;
  ok(!$im->read(file => 'testimg/short_bin.ppm', type=>'pnm'),
     "fail to read short bin ppm");
  cmp_ok($im->errstr, '=~', 'short read - file truncated', 
         "check error message");
}

{
  my $im = Imager->new;
  ok(!$im->read(file => 'testimg/short_bin16.ppm', type=>'pnm'),
     "fail to read short bin ppm (maxval 65535)");
  cmp_ok($im->errstr, '=~', 'short read - file truncated', 
         "check error message");
}

{
  my $im = Imager->new;
  ok(!$im->read(file => 'testimg/short_bin.pgm', type=>'pnm'),
     "fail to read short bin pgm");
  cmp_ok($im->errstr, '=~', 'short read - file truncated', 
         "check error message");
}

{
  my $im = Imager->new;
  ok(!$im->read(file => 'testimg/short_bin16.pgm', type=>'pnm'),
     "fail to read short bin pgm (maxval 65535)");
  cmp_ok($im->errstr, '=~', 'short read - file truncated', 
         "check error message");
}

{
  my $im = Imager->new;
  ok(!$im->read(file => 'testimg/short_bin.pbm', type => 'pnm'),
     "fail to read a short bin pbm");
  cmp_ok($im->errstr, '=~', 'short read - file truncated', 
         "check error message");
}

{
  my $im = Imager->new;
  ok(!$im->read(file => 'testimg/short_asc.ppm', type => 'pnm'),
     "fail to read a short asc ppm");
  cmp_ok($im->errstr, '=~', 'short read - file truncated', 
         "check error message");
}

{
  my $im = Imager->new;
  ok(!$im->read(file => 'testimg/short_asc.pgm', type => 'pnm'),
     "fail to read a short asc pgm");
  cmp_ok($im->errstr, '=~', 'short read - file truncated', 
         "check error message");
}

{
  my $im = Imager->new;
  ok(!$im->read(file => 'testimg/short_asc.pbm', type => 'pnm'),
     "fail to read a short asc pbm");
  cmp_ok($im->errstr, '=~', 'short read - file truncated', 
         "check error message");
}

{
  my $im = Imager->new;
  ok(!$im->read(file => 'testimg/bad_asc.ppm', type => 'pnm'),
     "fail to read a bad asc ppm");
  cmp_ok($im->errstr, '=~', 'invalid data for ascii pnm', 
         "check error message");
}

{
  my $im = Imager->new;
  ok(!$im->read(file => 'testimg/bad_asc.pgm', type => 'pnm'),
     "fail to read a bad asc pgm");
  cmp_ok($im->errstr, '=~', 'invalid data for ascii pnm', 
         "check error message");
}

{
  my $im = Imager->new;
  ok(!$im->read(file => 'testimg/bad_asc.pbm', type => 'pnm'),
     "fail to read a bad asc pbm");
  cmp_ok($im->errstr, '=~', 'invalid data for ascii pnm', 
         "check error message");
}

{
  my $im = Imager->new;
  ok($im->read(file => 'testimg/short_bin.ppm', type => 'pnm',
                allow_incomplete => 1),
     "partial read bin ppm");
  is($im->tags(name => 'i_incomplete'), 1, "partial flag set");
  is($im->tags(name => 'i_lines_read'), 1, "lines_read set");
}

{
  my $im = Imager->new;
  ok($im->read(file => 'testimg/short_bin16.ppm', type => 'pnm',
                allow_incomplete => 1),
     "partial read bin16 ppm");
  is($im->tags(name => 'i_incomplete'), 1, "partial flag set");
  is($im->tags(name => 'i_lines_read'), 1, "lines_read set");
  is($im->bits, 16, "check correct bits");
}

{
  my $im = Imager->new;
  ok($im->read(file => 'testimg/short_bin.pgm', type => 'pnm',
                allow_incomplete => 1),
     "partial read bin pgm");
  is($im->tags(name => 'i_incomplete'), 1, "partial flag set");
  is($im->tags(name => 'i_lines_read'), 1, "lines_read set");
}

{
  my $im = Imager->new;
  ok($im->read(file => 'testimg/short_bin16.pgm', type => 'pnm',
                allow_incomplete => 1),
     "partial read bin16 pgm");
  is($im->tags(name => 'i_incomplete'), 1, "partial flag set");
  is($im->tags(name => 'i_lines_read'), 1, "lines_read set");
}

{
  my $im = Imager->new;
  ok($im->read(file => 'testimg/short_bin.pbm', type => 'pnm',
                allow_incomplete => 1),
     "partial read bin pbm");
  is($im->tags(name => 'i_incomplete'), 1, "partial flag set");
  is($im->tags(name => 'i_lines_read'), 1, "lines_read set");
}

{
  my $im = Imager->new;
  ok($im->read(file => 'testimg/short_asc.ppm', type => 'pnm',
                allow_incomplete => 1),
     "partial read asc ppm");
  is($im->tags(name => 'i_incomplete'), 1, "partial flag set");
  is($im->tags(name => 'i_lines_read'), 1, "lines_read set");
}

{
  my $im = Imager->new;
  ok($im->read(file => 'testimg/short_asc.pgm', type => 'pnm',
                allow_incomplete => 1),
     "partial read asc pgm");
  is($im->tags(name => 'i_incomplete'), 1, "partial flag set");
  is($im->tags(name => 'i_lines_read'), 1, "lines_read set");
}

{
  my $im = Imager->new;
  ok($im->read(file => 'testimg/short_asc.pbm', type => 'pnm',
                allow_incomplete => 1),
     "partial read asc pbm");
  is($im->tags(name => 'i_incomplete'), 1, "partial flag set");
  is($im->tags(name => 'i_lines_read'), 1, "lines_read set");
}

{
  my @imgs = Imager->read_multi(file => 'testimg/multiple.ppm');
  is( 0+@imgs, 3, "Read 3 images");
  is( $imgs[0]->tags( name => 'pnm_type' ), 1, "Image 1 is type 1" );
  is( $imgs[0]->getwidth, 2, " ... width=2" );
  is( $imgs[0]->getheight, 2, " ... width=2" );
  is( $imgs[1]->tags( name => 'pnm_type' ), 6, "Image 2 is type 6" );
  is( $imgs[1]->getwidth, 164, " ... width=164" );
  is( $imgs[1]->getheight, 180, " ... width=180" );
  is( $imgs[2]->tags( name => 'pnm_type' ), 5, "Image 3 is type 5" );
  is( $imgs[2]->getwidth, 2, " ... width=2" );
  is( $imgs[2]->getheight, 2, " ... width=2" );
}

{
  my $im = Imager->new;
  ok($im->read(file => 'testimg/bad_asc.ppm', type => 'pnm',
                allow_incomplete => 1),
     "partial read bad asc ppm");
  is($im->tags(name => 'i_incomplete'), 1, "partial flag set");
  is($im->tags(name => 'i_lines_read'), 1, "lines_read set");
}

{
  my $im = Imager->new;
  ok($im->read(file => 'testimg/bad_asc.pgm', type => 'pnm',
                allow_incomplete => 1),
     "partial read bad asc pgm");
  is($im->tags(name => 'i_incomplete'), 1, "partial flag set");
  is($im->tags(name => 'i_lines_read'), 1, "lines_read set");
}

{
  my $im = Imager->new;
  ok($im->read(file => 'testimg/bad_asc.pbm', type => 'pnm',
                allow_incomplete => 1),
     "partial read bad asc pbm");
  is($im->tags(name => 'i_incomplete'), 1, "partial flag set");
  is($im->tags(name => 'i_lines_read'), 1, "lines_read set");
}

{
  print "# monochrome output\n";
  my $im = Imager->new(xsize => 10, ysize => 10, channels => 1, type => 'paletted');
  ok($im->addcolors(colors => [ '#000000', '#FFFFFF' ]),
     "add black and white");
  $im->box(filled => 1, xmax => 4, color => '#000000');
  $im->box(filled => 1, xmin => 5, color => '#FFFFFF');
  is($im->type, 'paletted', 'mono still paletted');
  push @files, "t104_mono.pbm";
  ok($im->write(file => 'testout/t104_mono.pbm', type => 'pnm'),
     "save as pbm");

  # check it
  my $imread = Imager->new;
  ok($imread->read(file => 'testout/t104_mono.pbm', type=>'pnm'),
     "read it back in")
    or print "# ", $imread->errstr, "\n";
  is($imread->type, 'paletted', "check result is paletted");
  is($imread->tags(name => 'pnm_type'), 4, "check type");
  is_image($im, $imread, "check image matches");
}

{
  print "# monochrome output - reversed palette\n";
  my $im = Imager->new(xsize => 10, ysize => 10, channels => 1, type => 'paletted');
  ok($im->addcolors(colors => [ '#FFFFFF', '#000000' ]),
     "add white and black");
  $im->box(filled => 1, xmax => 4, color => '#000000');
  $im->box(filled => 1, xmin => 5, color => '#FFFFFF');
  is($im->type, 'paletted', 'mono still paletted');
  push @files, "t104_mono2.pbm";
  ok($im->write(file => 'testout/t104_mono2.pbm', type => 'pnm'),
     "save as pbm");

  # check it
  my $imread = Imager->new;
  ok($imread->read(file => 'testout/t104_mono2.pbm', type=>'pnm'),
     "read it back in")
    or print "# ", $imread->errstr, "\n";
  is($imread->type, 'paletted', "check result is paletted");
  is($imread->tags(name => 'pnm_type'), 4, "check type");
  is_image($im, $imread, "check image matches");
}

{
  print "# 16-bit output\n";
  my $data;
  my $im = test_image_16();
  
  # without tag, it should do 8-bit output
  ok($im->write(data => \$data, type => 'pnm'),
     "write 16-bit image as 8-bit/sample ppm");
  my $im8 = Imager->new;
  ok($im8->read(data => $data), "read it back");
  is($im8->tags(name => 'pnm_maxval'), 255, "check maxval");
  is_image($im, $im8, "check image matches");

  # try 16-bit output
  $im->settag(name => 'pnm_write_wide_data', value => 1);
  $data = '';
  ok($im->write(data => \$data, type => 'pnm'),
     "write 16-bit image as 16-bit/sample ppm");
  push @files, "t104_16.ppm";
  $im->write(file=>'testout/t104_16.ppm');
  my $im16 = Imager->new;
  ok($im16->read(data => $data), "read it back");
  is($im16->tags(name => 'pnm_maxval'), 65535, "check maxval");
  push @files, "t104_16b.ppm";
  $im16->write(file=>'testout/t104_16b.ppm');
  is_image($im, $im16, "check image matches");
}

{
  ok(grep($_ eq 'pnm', Imager->read_types), "check pnm in read types");
  ok(grep($_ eq 'pnm', Imager->write_types), "check pnm in write types");
}

{ # test new() loading an image
  my $im = Imager->new(file => "testimg/penguin-base.ppm");
  ok($im, "received an image");
  is($im->getwidth, 164, "check width matches image");

  # fail to load an image
  my $im2 = Imager->new(file => "Imager.pm", filetype => "pnm");
  ok(!$im2, "no image when file failed to load");
  cmp_ok(Imager->errstr, '=~', "bad header magic, not a PNM file",
	 "check error message transferred");

  # load from data
 SKIP:
  {
    ok(open(FH, "< testimg/penguin-base.ppm"), "open test file")
      or skip("couldn't open data source", 4);
    binmode FH;
    my $imdata = do { local $/; <FH> };
    close FH;
    ok(length $imdata, "we got the data");
    my $im3 = Imager->new(data => $imdata);
    ok($im3, "read the file data");
    is($im3->getwidth, 164, "check width matches image");
  }
}

{ # image too large handling
  {
    ok(!Imager->new(file => "testimg/toowide.ppm", filetype => "pnm"),
       "fail to read a too wide image");
    is(Imager->errstr, "unable to read pnm image: could not read image width: integer overflow",
       "check error message");
  }
  {
    ok(!Imager->new(file => "testimg/tootall.ppm", filetype => "pnm"),
       "fail to read a too wide image");
    is(Imager->errstr, "unable to read pnm image: could not read image height: integer overflow",
       "check error message");
  }
}

{ # make sure close is checked for each image type
  my $fail_close = sub {
    Imager::i_push_error(0, "synthetic close failure");
    return 0;
  };

  for my $type (qw(basic basic16 gray gray16 mono)) {
    my $im = test_image_named($type);
    my $io = Imager::io_new_cb(sub { 1 }, undef, undef, $fail_close);
    ok(!$im->write(io => $io, type => "pnm"),
       "write $type image with a failing close handler");
    like($im->errstr, qr/synthetic close failure/,
	 "check error message");
  }
}

Imager->close_log;

unless ($ENV{IMAGER_KEEP_FILES}) {
  unlink "testout/t104ppm.log";
  unlink map "testout/$_", @files;
}

sub openimage {
  my $fname = shift;
  local(*FH);
  open(FH, $fname) or die "Cannot open $fname: $!\n";
  binmode(FH);
  return *FH;
}

sub slurp {
  my $fh = openimage(shift);
  local $/;
  my $data = <$fh>;
  close($fh);
  return $data;
}

sub check_gray {
  my ($c, $gray) = @_;

  my ($g) = $c->rgba;
  is($g, $gray, "compare gray");
}

