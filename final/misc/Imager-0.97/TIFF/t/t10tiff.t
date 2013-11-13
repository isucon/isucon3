#!perl -w
use strict;
use Test::More tests => 247;
use Imager qw(:all);
use Imager::Test qw(is_image is_image_similar test_image test_image_16 test_image_double test_image_raw);

BEGIN { use_ok("Imager::File::TIFF"); }

-d "testout"
  or mkdir "testout";

$|=1;  # give us some progress in the test harness
init_log("testout/t106tiff.log",1);

my $green=i_color_new(0,255,0,255);
my $blue=i_color_new(0,0,255,255);
my $red=i_color_new(255,0,0,255);

my $img=test_image_raw();

my $ver_string = Imager::File::TIFF::i_tiff_libversion();
ok(my ($full, $major, $minor, $point) = 
   $ver_string =~ /Version +((\d+)\.(\d+).(\d+))/,
   "extract library version")
  or diag("Could not extract from:\n$ver_string");
diag("libtiff release $full") if $full;
# make something we can compare
my $cmp_ver = sprintf("%03d%03d%03d", $major, $minor, $point);
if ($cmp_ver lt '003007000') {
  diag("You have an old version of libtiff - $full, some tests will be skipped");
}

Imager::i_tags_add($img, "i_xres", 0, "300", 0);
Imager::i_tags_add($img, "i_yres", 0, undef, 250);
# resolutionunit is centimeters
Imager::i_tags_add($img, "tiff_resolutionunit", 0, undef, 3);
Imager::i_tags_add($img, "tiff_software", 0, "t106tiff.t", 0);
open(FH,">testout/t106.tiff") || die "cannot open testout/t106.tiff for writing\n";
binmode(FH); 
my $IO = Imager::io_new_fd(fileno(FH));
ok(Imager::File::TIFF::i_writetiff_wiol($img, $IO), "write low level")
  or print "# ", Imager->_error_as_msg, "\n";
close(FH);

open(FH,"testout/t106.tiff") or die "cannot open testout/t106.tiff\n";
binmode(FH);
$IO = Imager::io_new_fd(fileno(FH));
my $cmpimg = Imager::File::TIFF::i_readtiff_wiol($IO);
ok($cmpimg, "read low-level");

close(FH);

print "# tiff average mean square pixel difference: ",sqrt(i_img_diff($img,$cmpimg))/150*150,"\n";

ok(!i_img_diff($img, $cmpimg), "compare written and read image");

# check the tags are ok
my %tags = map { Imager::i_tags_get($cmpimg, $_) }
  0 .. Imager::i_tags_count($cmpimg) - 1;
ok(abs($tags{i_xres} - 300) < 0.5, "i_xres in range");
ok(abs($tags{i_yres} - 250) < 0.5, "i_yres in range");
is($tags{tiff_resolutionunit}, 3, "tiff_resolutionunit");
is($tags{tiff_software}, 't106tiff.t', "tiff_software");
is($tags{tiff_photometric}, 2, "tiff_photometric"); # PHOTOMETRIC_RGB is 2
is($tags{tiff_bitspersample}, 8, "tiff_bitspersample");

$IO = Imager::io_new_bufchain();

ok(Imager::File::TIFF::i_writetiff_wiol($img, $IO), "write to buffer chain");
my $tiffdata = Imager::io_slurp($IO);

open(FH,"testout/t106.tiff");
binmode FH;
my $odata;
{ local $/;
  $odata = <FH>;
}

is($odata, $tiffdata, "same data in file as in memory");

# test Micksa's tiff writer
# a shortish fax page
my $faximg = Imager::ImgRaw::new(1728, 2000, 1);
my $black = i_color_new(0,0,0,255);
my $white = i_color_new(255,255,255,255);
# vaguely test-patterny
i_box_filled($faximg, 0, 0, 1728, 2000, $white);
i_box_filled($faximg, 100,100,1628, 200, $black);
my $width = 1;
my $pos = 100;
while ($width+$pos < 1628) {
  i_box_filled($faximg, $pos, 300, $pos+$width-1, 400, $black);
  $pos += $width + 20;
  $width += 2;
}
open FH, "> testout/t106tiff_fax.tiff"
  or die "Cannot create testout/t106tiff_fax.tiff: $!";
binmode FH;
$IO = Imager::io_new_fd(fileno(FH));
ok(Imager::File::TIFF::i_writetiff_wiol_faxable($faximg, $IO, 1), "write faxable, low level");
close FH;

# test the OO interface
my $ooim = Imager->new;
ok($ooim->read(file=>'testout/t106.tiff'), "read OO");
ok($ooim->write(file=>'testout/t106_oo.tiff'), "write OO");

# OO with the fax image
my $oofim = Imager->new;
ok($oofim->read(file=>'testout/t106tiff_fax.tiff'),
   "read fax OO");

# this should have tags set for the resolution
%tags = map @$_, $oofim->tags;
is($tags{i_xres}, 204, "fax i_xres");
is($tags{i_yres}, 196, "fax i_yres");
ok(!$tags{i_aspect_only}, "i_aspect_only");
# resunit_inches
is($tags{tiff_resolutionunit}, 2, "tiff_resolutionunit");
is($tags{tiff_bitspersample}, 1, "tiff_bitspersample");
is($tags{tiff_photometric}, 0, "tiff_photometric");

ok($oofim->write(file=>'testout/t106_oo_fax.tiff', class=>'fax'),
   "write OO, faxable");

# the following should fail since there's no type and no filename
my $oodata;
ok(!$ooim->write(data=>\$oodata), "write with no type and no filename to guess with");

# OO to data
ok($ooim->write(data=>\$oodata, type=>'tiff'), "write to data")
  or print "# ",$ooim->errstr, "\n";
is($oodata, $tiffdata, "check data matches between memory and file");

# make sure we can write non-fine mode
ok($oofim->write(file=>'testout/t106_oo_faxlo.tiff', class=>'fax', fax_fine=>0), "write OO, fax standard mode");

# paletted reads
my $img4 = Imager->new;
ok($img4->read(file=>'testimg/comp4.tif'), "reading 4-bit paletted")
  or print "# ", $img4->errstr, "\n";
is($img4->type, 'paletted', "image isn't paletted");
print "# colors: ", $img4->colorcount,"\n";
  cmp_ok($img4->colorcount, '<=', 16, "more than 16 colors!");
#ok($img4->write(file=>'testout/t106_was4.ppm'),
#   "Cannot write img4");
# I know I'm using BMP before it's test, but comp4.tif started life 
# as comp4.bmp
my $bmp4 = Imager->new;
ok($bmp4->read(file=>'testimg/comp4.bmp'), "reading 4-bit bmp!");
my $diff = i_img_diff($img4->{IMG}, $bmp4->{IMG});
print "# diff $diff\n";
ok($diff == 0, "image mismatch");
my $img4t = Imager->new;
ok($img4t->read(file => 'testimg/comp4t.tif'), "read 4-bit paletted, tiled")
  or print "# ", $img4t->errstr, "\n";
is_image($bmp4, $img4t, "check tiled version matches");
my $img8 = Imager->new;
ok($img8->read(file=>'testimg/comp8.tif'), "reading 8-bit paletted");
is($img8->type, 'paletted', "image isn't paletted");
print "# colors: ", $img8->colorcount,"\n";
#ok($img8->write(file=>'testout/t106_was8.ppm'),
#   "Cannot write img8");
ok($img8->colorcount == 256, "more colors than expected");
my $bmp8 = Imager->new;
ok($bmp8->read(file=>'testimg/comp8.bmp'), "reading 8-bit bmp!");
$diff = i_img_diff($img8->{IMG}, $bmp8->{IMG});
print "# diff $diff\n";
ok($diff == 0, "image mismatch");
my $bad = Imager->new;
ok($bad->read(file=>'testimg/comp4bad.tif', 
	      allow_incomplete=>1), "bad image not returned");
ok(scalar $bad->tags(name=>'i_incomplete'), "incomplete tag not set");
ok($img8->write(file=>'testout/t106_pal8.tif'), "writing 8-bit paletted");
my $cmp8 = Imager->new;
ok($cmp8->read(file=>'testout/t106_pal8.tif'),
   "reading 8-bit paletted");
#print "# ",$cmp8->errstr,"\n";
is($cmp8->type, 'paletted', "pal8 isn't paletted");
is($cmp8->colorcount, 256, "pal8 bad colorcount");
$diff = i_img_diff($img8->{IMG}, $cmp8->{IMG});
print "# diff $diff\n";
ok($diff == 0, "written image doesn't match read");
ok($img4->write(file=>'testout/t106_pal4.tif'), "writing 4-bit paletted");
ok(my $cmp4 = Imager->new->read(file=>'testout/t106_pal4.tif'),
   "reading 4-bit paletted");
is($cmp4->type, 'paletted', "pal4 isn't paletted");
is($cmp4->colorcount, 16, "pal4 bad colorcount");
$diff = i_img_diff($img4->{IMG}, $cmp4->{IMG});
print "# diff $diff\n";
ok($diff == 0, "written image doesn't match read");

my $work;
my $seekpos;
sub io_writer {
  my ($what) = @_;
  if ($seekpos > length $work) {
    $work .= "\0" x ($seekpos - length $work);
  }
  substr($work, $seekpos, length $what) = $what;
  $seekpos += length $what;
  
  1;
}
sub io_reader {
  my ($size, $maxread) = @_;
  print "# io_reader($size, $maxread) pos $seekpos\n";
  if ($seekpos + $maxread > length $work) {
    $maxread = length($work) - $seekpos;
  }
  my $out = substr($work, $seekpos, $maxread);
  $seekpos += length $out;
  $out;
}
sub io_reader2 {
  my ($size, $maxread) = @_;
  print "# io_reader2($size, $maxread) pos $seekpos\n";
  my $out = substr($work, $seekpos, $size);
  $seekpos += length $out;
  $out;
}
use IO::Seekable;
sub io_seeker {
  my ($offset, $whence) = @_;
  print "# io_seeker($offset, $whence)\n";
  if ($whence == SEEK_SET) {
    $seekpos = $offset;
  }
  elsif ($whence == SEEK_CUR) {
    $seekpos += $offset;
  }
  else { # SEEK_END
    $seekpos = length($work) + $offset;
  }
  #print "-> $seekpos\n";
  $seekpos;
}
my $did_close;
sub io_closer {
  ++$did_close;
}

# read via cb
$work = $tiffdata;
$seekpos = 0;
my $IO2 = Imager::io_new_cb(undef, \&io_reader, \&io_seeker, undef);
ok($IO2, "new readcb obj");
my $img5 = Imager::File::TIFF::i_readtiff_wiol($IO2);
ok($img5, "read via cb");
ok(i_img_diff($img5, $img) == 0, "read from cb diff");

# read via cb2
$work = $tiffdata;
$seekpos = 0;
my $IO3 = Imager::io_new_cb(undef, \&io_reader2, \&io_seeker, undef);
ok($IO3, "new readcb2 obj");
my $img6 = Imager::File::TIFF::i_readtiff_wiol($IO3);
ok($img6, "read via cb2");
ok(i_img_diff($img6, $img) == 0, "read from cb2 diff");

# write via cb
$work = '';
$seekpos = 0;
my $IO4 = Imager::io_new_cb(\&io_writer, \&io_reader, \&io_seeker,
			    \&io_closer);
ok($IO4, "new writecb obj");
ok(Imager::File::TIFF::i_writetiff_wiol($img, $IO4), "write to cb");
is($work, $odata, "write cb match");
ok($did_close, "write cb did close");
open D1, ">testout/d1.tiff" or die;
print D1 $work;
close D1;
open D2, ">testout/d2.tiff" or die;
print D2 $tiffdata;
close D2;

# write via cb2
$work = '';
$seekpos = 0;
$did_close = 0;
my $IO5 = Imager::io_new_cb(\&io_writer, \&io_reader, \&io_seeker,
			    \&io_closer, 1);
ok($IO5, "new writecb obj 2");
ok(Imager::File::TIFF::i_writetiff_wiol($img, $IO5), "write to cb2");
is($work, $odata, "write cb2 match");
ok($did_close, "write cb2 did close");

open D3, ">testout/d3.tiff" or die;
print D3 $work;
close D3;


{ # check close failures are handled correctly
  { # single image
    my $im = test_image();
    my $fail_close = sub {
      Imager::i_push_error(0, "synthetic close failure");
      return 0;
    };
    $work = '';
    $seekpos = 0;
    ok(!$im->write(type => "tiff",
		   readcb => \&io_reader,
		   writecb => \&io_writer,
		   seekcb => \&io_seeker,
		   closecb => $fail_close),
       "check failing close fails");
    like($im->errstr, qr/synthetic close failure/,
	 "check error message");
  }
  { # multiple images
    my $im = test_image();
    my $fail_close = sub {
      Imager::i_push_error(0, "synthetic close failure");
      return 0;
    };
    $work = '';
    $seekpos = 0;
    ok(!Imager->write_multi({type => "tiff",
			     readcb => \&io_reader,
			     writecb => \&io_writer,
			     seekcb => \&io_seeker,
			     closecb => $fail_close}, $im, $im),
       "check failing close fails");
    like(Imager->errstr, qr/synthetic close failure/,
	 "check error message");
  }
}

# multi-image write/read
my @imgs;
push(@imgs, map $ooim->copy(), 1..3);
for my $i (0..$#imgs) {
  $imgs[$i]->addtag(name=>"tiff_pagename", value=>"Page ".($i+1));
}
my $rc = Imager->write_multi({file=>'testout/t106_multi.tif'}, @imgs);
ok($rc, "writing multiple images to tiff");
my @out = Imager->read_multi(file=>'testout/t106_multi.tif');
ok(@out == @imgs, "reading multiple images from tiff");
@out == @imgs or print "# ",scalar @out, " ",Imager->errstr,"\n";
for my $i (0..$#imgs) {
  ok(i_img_diff($imgs[$i]{IMG}, $out[$i]{IMG}) == 0,
     "comparing image $i");
  my ($tag) = $out[$i]->tags(name=>'tiff_pagename');
  is($tag, "Page ".($i+1),
     "tag doesn't match original image");
}

# writing even more images to tiff - we weren't handling more than five
# correctly on read
@imgs = map $ooim->copy(), 1..40;
$rc = Imager->write_multi({file=>'testout/t106_multi2.tif'}, @imgs);
ok($rc, "writing 40 images to tiff")
  or diag("writing 40 images: " . Imager->errstr);
@out = Imager->read_multi(file=>'testout/t106_multi2.tif');
ok(@imgs == @out, "reading 40 images from tiff")
  or diag("reading 40 images:" . Imager->errstr);
# force some allocation activity - helps crash here if it's the problem
@out = @imgs = ();

# multi-image fax files
ok(Imager->write_multi({file=>'testout/t106_faxmulti.tiff', class=>'fax'},
		       $oofim, $oofim), "write multi fax image")
  or diag("writing 40 fax pages: " . Imager->errstr);
@imgs = Imager->read_multi(file=>'testout/t106_faxmulti.tiff');
ok(@imgs == 2, "reading multipage fax")
  or diag("reading 40 fax pages: " . Imager->errstr);
ok(Imager::i_img_diff($imgs[0]{IMG}, $oofim->{IMG}) == 0,
   "compare first fax image");
ok(Imager::i_img_diff($imgs[1]{IMG}, $oofim->{IMG}) == 0,
   "compare second fax image");

my ($format) = $imgs[0]->tags(name=>'i_format');
is($format, 'tiff', "check i_format tag");

my $unit = $imgs[0]->tags(name=>'tiff_resolutionunit');
ok(defined $unit && $unit == 2, "check tiff_resolutionunit tag");
my $unitname = $imgs[0]->tags(name=>'tiff_resolutionunit_name');
is($unitname, 'inch', "check tiff_resolutionunit_name tag");

my $warned = Imager->new;
ok($warned->read(file=>"testimg/tiffwarn.tif"), "read tiffwarn.tif");
my ($warning) = $warned->tags(name=>'i_warning');
ok(defined $warning, "check warning is set");
like($warning, qr/[Uu]nknown field with tag 28712/,
     "check that warning tag correct");

{ # support for reading a given page
  # first build a simple test image
  my $im1 = Imager->new(xsize=>50, ysize=>50);
  $im1->box(filled=>1, color=>$blue);
  $im1->addtag(name=>'tiff_pagename', value => "Page One");
  my $im2 = Imager->new(xsize=>60, ysize=>60);
  $im2->box(filled=>1, color=>$green);
  $im2->addtag(name=>'tiff_pagename', value=>"Page Two");
  
  # read second page
  my $page_file = 'testout/t106_pages.tif';
  ok(Imager->write_multi({ file=> $page_file}, $im1, $im2),
     "build simple multiimage for page tests");
  my $imwork = Imager->new;
  ok($imwork->read(file=>$page_file, page=>1),
     "read second page");
  is($im2->getwidth, $imwork->getwidth, "check width");
  is($im2->getwidth, $imwork->getheight, "check height");
  is(i_img_diff($imwork->{IMG}, $im2->{IMG}), 0,
     "check image content");
  my ($page_name) = $imwork->tags(name=>'tiff_pagename');
  is($page_name, 'Page Two', "check tag we set");
  
  # try an out of range page
  ok(!$imwork->read(file=>$page_file, page=>2),
     "check out of range page");
  is($imwork->errstr, "could not switch to page 2", "check message");
}

{ # test writing returns an error message correctly
  # open a file read only and try to write to it
  open TIFF, "> testout/t106_empty.tif" or die;
  close TIFF;
  open TIFF, "< testout/t106_empty.tif"
    or skip "Cannot open testout/t106_empty.tif for reading", 8;
  binmode TIFF;
  my $im = Imager->new(xsize=>100, ysize=>100);
  ok(!$im->write(fh => \*TIFF, type=>'tiff', buffered => 0),
     "fail to write to read only handle");
  cmp_ok($im->errstr, '=~', 'Could not create TIFF object: Error writing TIFF header: write\(\)',
	 "check error message");
  ok(!Imager->write_multi({ type => 'tiff', fh => \*TIFF, buffered => 0 }, $im),
     "fail to write multi to read only handle");
  cmp_ok(Imager->errstr, '=~', 'Could not create TIFF object: Error writing TIFF header: write\(\)',
	 "check error message");
  ok(!$im->write(fh => \*TIFF, type=>'tiff', class=>'fax', buffered => 0),
     "fail to write to read only handle (fax)");
  cmp_ok($im->errstr, '=~', 'Could not create TIFF object: Error writing TIFF header: write\(\)',
	 "check error message");
  ok(!Imager->write_multi({ type => 'tiff', fh => \*TIFF, class=>'fax', buffered => 0 }, $im),
     "fail to write multi to read only handle (fax)");
  cmp_ok(Imager->errstr, '=~', 'Could not create TIFF object: Error writing TIFF header: write\(\)',
	 "check error message");
}

{ # test reading returns an error correctly - use test script as an
  # invalid TIFF file
  my $im = Imager->new;
  ok(!$im->read(file=>'t/t10tiff.t', type=>'tiff'),
     "fail to read script as image");
  # we get different magic number values depending on the platform
  # byte ordering
  cmp_ok($im->errstr, '=~',
	 "Error opening file: Not a TIFF (?:or MDI )?file, bad magic number (8483 \\(0x2123\\)|8993 \\(0x2321\\))", 
	 "check error message");
  my @ims = Imager->read_multi(file =>'t/t106tiff.t', type=>'tiff');
  ok(!@ims, "fail to read_multi script as image");
  cmp_ok($im->errstr, '=~',
	 "Error opening file: Not a TIFF (?:or MDI )?file, bad magic number (8483 \\(0x2123\\)|8993 \\(0x2321\\))", 
	 "check error message");
}

{ # write_multi to data
  my $data;
  my $im = Imager->new(xsize => 50, ysize => 50);
  ok(Imager->write_multi({ data => \$data, type=>'tiff' }, $im, $im),
     "write multi to in memory");
  ok(length $data, "make sure something written");
  my @im = Imager->read_multi(data => $data);
  is(@im, 2, "make sure we can read it back");
  is(Imager::i_img_diff($im[0]{IMG}, $im->{IMG}), 0,
     "check first image");
  is(Imager::i_img_diff($im[1]{IMG}, $im->{IMG}), 0,
     "check second image");
}

{ # handling of an alpha channel for various images
  my $photo_rgb = 2;
  my $photo_cmyk = 5;
  my $photo_cielab = 8;
  my @alpha_images =
    (
     [ 'srgb.tif',    3, $photo_rgb,    '003005005' ],
     [ 'srgba.tif',   4, $photo_rgb,    '003005005' ],
     [ 'srgbaa.tif',  4, $photo_rgb,    '003005005' ],
     [ 'scmyk.tif',   3, $photo_cmyk,   '003005005' ],
     [ 'scmyka.tif',  4, $photo_cmyk,   '003005005' ],
     [ 'scmykaa.tif', 4, $photo_cmyk,   '003005005' ],
     [ 'slab.tif',    3, $photo_cielab, '003006001' ],
    );
  
  for my $test (@alpha_images) {
    my ($input, $channels, $photo, $need_ver) = @$test;
    
  SKIP: {
      my $skipped = $channels == 4 ? 4 : 3;
      $need_ver le $cmp_ver
	or skip("Your ancient tifflib is buggy/limited for this test", $skipped);
      my $im = Imager->new;
      ok($im->read(file => "testimg/$input"),
	 "read alpha test $input")
	or print "# ", $im->errstr, "\n";
      is($im->getchannels, $channels, "channels for $input match");
      is($im->tags(name=>'tiff_photometric'), $photo,
	 "photometric for $input match");
      $channels == 4
	or next;
      my $c = $im->getpixel(x => 0, 'y' => 7);
      is(($c->rgba)[3], 0, "bottom row should have 0 alpha");
    }
  }
}

{
  ok(grep($_ eq 'tiff', Imager->read_types), "check tiff in read types");
  ok(grep($_ eq 'tiff', Imager->write_types), "check tiff in write types");
}

{ # reading tile based images
  my $im = Imager->new;
  ok($im->read(file => 'testimg/pengtile.tif'), "read tiled image")
    or print "# ", $im->errstr, "\n";
  # compare it
  my $comp = Imager->new;
  ok($comp->read(file => 'testimg/penguin-base.ppm'), 'read comparison image');
  is_image($im, $comp, 'compare them');
}

SKIP:
{ # failing to read tile based images
  # we grab our tiled image and patch a tile offset to nowhere
  ok(open(TIFF, '< testimg/pengtile.tif'), 'open pengtile.tif')
    or skip 'cannot open testimg/pengtile.tif', 4;
  
  $cmp_ver ge '003005007'
    or skip("Your ancient tifflib has bad error handling", 4);
  binmode TIFF;
  my $data = do { local $/; <TIFF>; };
  
  # patch a tile offset
  substr($data, 0x1AFA0, 4) = pack("H*", "00000200");
  
  #open PIPE, "| bytedump -a | less" or die;
  #print PIPE $data;
  #close PIPE;
  
  my $allow = Imager->new;
  ok($allow->read(data => $data, allow_incomplete => 1),
     "read incomplete tiled");
  ok($allow->tags(name => 'i_incomplete'), 'i_incomplete set');
  is($allow->tags(name => 'i_lines_read'), 173, 
     'check i_lines_read set appropriately');
  
  my $fail = Imager->new;
  ok(!$fail->read(data => $data), "read fail tiled");
}

{ # read 16-bit/sample
  my $im16 = Imager->new;
  ok($im16->read(file => 'testimg/rgb16.tif'), "read 16-bit rgb");
  is($im16->bits, 16, 'got a 16-bit image');
  my $im16t = Imager->new;
  ok($im16t->read(file => 'testimg/rgb16t.tif'), "read 16-bit rgb tiled");
  is($im16t->bits, 16, 'got a 16-bit image');
  is_image($im16, $im16t, 'check they match');
  
  my $grey16 = Imager->new;
  ok($grey16->read(file => 'testimg/grey16.tif'), "read 16-bit grey")
    or print "# ", $grey16->errstr, "\n";
  is($grey16->bits, 16, 'got a 16-bit image');
  is($grey16->getchannels, 1, 'and its grey');
  my $comp16 = $im16->convert(matrix => [ [ 0.299, 0.587, 0.114 ] ]);
  is_image($grey16, $comp16, 'compare grey to converted');
  
  my $grey32 = Imager->new;
  ok($grey32->read(file => 'testimg/grey32.tif'), "read 32-bit grey")
    or print "# ", $grey32->errstr, "\n";
  is($grey32->bits, 'double', 'got a double image');
  is($grey32->getchannels, 2, 'and its grey + alpha');
  is($grey32->tags(name => 'tiff_bitspersample'), 32, 
     "check bits per sample");
  my $base = test_image_double->convert(preset =>'grey')
    ->convert(preset => 'addalpha');
  is_image($grey32, $base, 'compare to original');
}

{ # read 16, 32-bit/sample and compare to the original
  my $rgba = Imager->new;
  ok($rgba->read(file => 'testimg/srgba.tif'),
     "read base rgba image");
  my $rgba16 = Imager->new;
  ok($rgba16->read(file => 'testimg/srgba16.tif'),
     "read 16-bit/sample rgba image");
  is_image($rgba, $rgba16, "check they match");
  is($rgba16->bits, 16, 'check we got the right type');
  
  my $rgba32 = Imager->new;
  ok($rgba32->read(file => 'testimg/srgba32.tif'),
     "read 32-bit/sample rgba image");
  is_image($rgba, $rgba32, "check they match");
  is($rgba32->bits, 'double', 'check we got the right type');
  
  my $cmyka16 = Imager->new;
  ok($cmyka16->read(file => 'testimg/scmyka16.tif'),
     "read cmyk 16-bit")
    or print "# ", $cmyka16->errstr, "\n";
  is($cmyka16->bits, 16, "check we got the right type");
  is_image_similar($rgba, $cmyka16, 10, "check image data");

  # tiled, non-contig, should fallback to RGBA code
  my $rgbatsep = Imager->new;
  ok($rgbatsep->read(file => 'testimg/rgbatsep.tif'),
     "read tiled, separated rgba image")
    or diag($rgbatsep->errstr);
  is_image($rgba, $rgbatsep, "check they match");
}
{ # read bi-level
  my $pbm = Imager->new;
  ok($pbm->read(file => 'testimg/imager.pbm'), "read original pbm");
  my $tif = Imager->new;
  ok($tif->read(file => 'testimg/imager.tif'), "read mono tif");
  is_image($pbm, $tif, "compare them");
  is($tif->type, 'paletted', 'check image type');
  is($tif->colorcount, 2, 'check we got a "mono" image');
}

{ # check alpha channels scaled correctly for fallback handler
  my $im = Imager->new;
  ok($im->read(file=>'testimg/alpha.tif'), 'read alpha check image');
  my @colors =
    (
     [ 0, 0, 0 ],
     [ 255, 255, 255 ],
     [ 127, 0, 127 ],
     [ 127, 127, 0 ],
    );
  my @alphas = ( 255, 191, 127, 63 );
  my $ok = 1;
  my $msg = 'alpha check ok';
 CHECKER:
  for my $y (0 .. 3) {
    for my $x (0 .. 3) {
      my $c = $im->getpixel(x => $x, 'y' => $y);
      my @c = $c->rgba;
      my $alpha = pop @c;
      if ($alpha != $alphas[$y]) {
	$ok = 0;
	$msg = "($x,$y) alpha mismatch $alpha vs $alphas[$y]";
	last CHECKER;
      }
      my $expect = $colors[$x];
      for my $ch (0 .. 2) {
	if (abs($expect->[$ch]-$c[$ch]) > 3) {
	  $ok = 0;
	  $msg = "($x,$y)[$ch] color mismatch got $c[$ch] vs expected $expect->[$ch]";
	  last CHECKER;
	}
      }
    }
  }
  ok($ok, $msg);
}

{ # check alpha channels scaled correctly for greyscale
  my $im = Imager->new;
  ok($im->read(file=>'testimg/gralpha.tif'), 'read alpha check grey image');
  my @greys = ( 0, 255, 52, 112 );
  my @alphas = ( 255, 191, 127, 63 );
  my $ok = 1;
  my $msg = 'alpha check ok';
 CHECKER:
  for my $y (0 .. 3) {
    for my $x (0 .. 3) {
      my $c = $im->getpixel(x => $x, 'y' => $y);
      my ($grey, $alpha) = $c->rgba;
      if ($alpha != $alphas[$y]) {
	$ok = 0;
	$msg = "($x,$y) alpha mismatch $alpha vs $alphas[$y]";
	last CHECKER;
      }
      if (abs($greys[$x] - $grey) > 3) {
	$ok = 0;
	$msg = "($x,$y) grey mismatch $grey vs $greys[$x]";
	last CHECKER;
      }
    }
  }
  ok($ok, $msg);
}

{ # 16-bit writes
  my $orig = test_image_16();
  my $data;
  ok($orig->write(data => \$data, type => 'tiff', 
		  tiff_compression => 'none'), "write 16-bit/sample");
  my $im = Imager->new;
  ok($im->read(data => $data), "read it back");
  is_image($im, $orig, "check read data matches");
  is($im->tags(name => 'tiff_bitspersample'), 16, "correct bits");
  is($im->bits, 16, 'check image bits');
  is($im->tags(name => 'tiff_photometric'), 2, "correct photometric");
    is($im->tags(name => 'tiff_compression'), 'none', "no compression");
  is($im->getchannels, 3, 'correct channels');
}

{ # 8-bit writes
  # and check compression
  my $compress = Imager::File::TIFF::i_tiff_has_compression('lzw') ? 'lzw' : 'packbits';
  my $orig = test_image()->convert(preset=>'grey')
    ->convert(preset => 'addalpha');
  my $data;
  ok($orig->write(data => \$data, type => 'tiff',
		  tiff_compression=> $compress),
     "write 8 bit")
    or print "# ", $orig->errstr, "\n";
  my $im = Imager->new;
  ok($im->read(data => $data), "read it back");
  is_image($im, $orig, "check read data matches");
  is($im->tags(name => 'tiff_bitspersample'), 8, 'correct bits');
  is($im->bits, 8, 'check image bits');
  is($im->tags(name => 'tiff_photometric'), 1, 'correct photometric');
  is($im->tags(name => 'tiff_compression'), $compress,
     "$compress compression");
  is($im->getchannels, 2, 'correct channels');
}

{ # double writes
  my $orig = test_image_double()->convert(preset=>'addalpha');
  my $data;
  ok($orig->write(data => \$data, type => 'tiff', 
		  tiff_compression => 'none'), 
     "write 32-bit/sample from double")
    or print "# ", $orig->errstr, "\n";
  my $im = Imager->new;
  ok($im->read(data => $data), "read it back");
  is_image($im, $orig, "check read data matches");
  is($im->tags(name => 'tiff_bitspersample'), 32, "correct bits");
  is($im->bits, 'double', 'check image bits');
  is($im->tags(name => 'tiff_photometric'), 2, "correct photometric");
  is($im->tags(name => 'tiff_compression'), 'none', "no compression");
  is($im->getchannels, 4, 'correct channels');
}

{ # bilevel
  my $im = test_image()->convert(preset => 'grey')
    ->to_paletted(make_colors => 'mono',
		  translate => 'errdiff');
  my $faxdata;
  
  # fax compression is written as miniswhite
  ok($im->write(data => \$faxdata, type => 'tiff', 
		tiff_compression => 'fax3'),
     "write bilevel fax compressed");
  my $fax = Imager->new;
  ok($fax->read(data => $faxdata), "read it back");
  ok($fax->is_bilevel, "got a bi-level image back");
  is($fax->tags(name => 'tiff_compression'), 'fax3',
     "check fax compression used");
  is_image($fax, $im, "compare to original");
  
  # other compresion written as minisblack
  my $packdata;
  ok($im->write(data => \$packdata, type => 'tiff',
		tiff_compression => 'jpeg'),
     "write bilevel packbits compressed");
  my $packim = Imager->new;
  ok($packim->read(data => $packdata), "read it back");
  ok($packim->is_bilevel, "got a bi-level image back");
  is($packim->tags(name => 'tiff_compression'), 'packbits',
     "check fallback compression used");
  is_image($packim, $im, "compare to original");
}

{ # fallback handling of tiff
  is(Imager::File::TIFF::i_tiff_has_compression('none'), 1, "can always do uncompresed");
  is(Imager::File::TIFF::i_tiff_has_compression('xxx'), '', "can't do xxx compression");
}


{ # check file limits are checked
  my $limit_file = "testout/t106.tiff";
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
  # this image has an IFD loop, which sends some TIFF readers into a
  # loop, including Corel PhotoPaint and the GIMP's tiff reader.
  my $ifdloop_hex = <<HEX;
49 49 2A 00 0A 00 00 00 FE 00 0A 00 00 01 03 00
01 00 00 00 01 00 00 00 01 01 03 00 01 00 00 00
01 00 00 00 02 01 03 00 03 00 00 00 88 00 00 00
03 01 03 00 01 00 00 00 05 80 00 00 06 01 03 00
01 00 00 00 02 00 00 00 11 01 04 00 01 00 00 00
08 00 00 00 12 01 03 00 01 00 00 00 01 00 00 00
15 01 03 00 01 00 00 00 03 00 00 00 17 01 04 00
01 00 00 00 02 00 00 00 1C 01 03 00 01 00 00 00
01 00 00 00 90 00 00 00 08 00 08 00 08 00 FE 00
0A 00 00 01 03 00 01 00 00 00 01 00 00 00 01 01
03 00 01 00 00 00 01 00 00 00 02 01 03 00 03 00
00 00 0E 01 00 00 03 01 03 00 01 00 00 00 05 80
00 00 06 01 03 00 01 00 00 00 02 00 00 00 11 01
04 00 01 00 00 00 8E 00 00 00 12 01 03 00 01 00
00 00 01 00 00 00 15 01 03 00 01 00 00 00 03 00
00 00 17 01 04 00 01 00 00 00 02 00 00 00 1C 01
03 00 01 00 00 00 01 00 00 00 0A 00 00 00 08 00
08 00 08 00
HEX
  $ifdloop_hex =~ tr/0-9A-F//cd;
  my $ifdloop = pack("H*", $ifdloop_hex);

  my $im = Imager->new;
  ok($im->read(data => $ifdloop, type => "tiff", page => 1),
     "read what should be valid");
  ok(!$im->read(data => $ifdloop, type => "tiff", page => 2),
     "third page is after looping back to the start, if this fails, upgrade tifflib")
    or skip("tifflib is broken", 1);
  print "# ", $im->errstr, "\n";
  my @im = Imager->read_multi(type => "tiff", data => $ifdloop);
  is(@im, 2, "should be only 2 images");
}

SKIP:
{ # sample format
  Imager::File::TIFF::i_tiff_has_compression("lzw")
      or skip "No LZW support", 8;
  Imager::File::TIFF::i_tiff_ieeefp()
      or skip "No IEEE FP type", 8;

 SKIP:
  { # signed
    my $cmp = Imager->new(file => "testimg/grey16.tif", filetype => "tiff")
      or skip "Cannot read grey16.tif: ". Imager->errstr, 4;
    my $im = Imager->new(file => "testimg/grey16sg.tif", filetype => "tiff");
    ok($im, "read image with SampleFormat = signed int")
      or skip "Couldn't read the file", 3;
    is_image($im, $cmp, "check the images match");
    my %tags = map @$_, $im->tags;
    is($tags{tiff_sample_format}, 2, "check sample format");
    is($tags{tiff_sample_format_name}, "int", "check sample format name");
  }

 SKIP:
  { # float
    my $cmp = Imager->new(file => "testimg/srgba32.tif", filetype => "tiff")
      or skip "Cannot read srgaba32f.tif: ". Imager->errstr, 4;
    my $im = Imager->new(file => "testimg/srgba32f.tif", filetype => "tiff");
    ok($im, "read image with SampleFormat = float")
      or skip "Couldn't read the file", 3;
    is_image($im, $cmp, "check the images match");
    my %tags = map @$_, $im->tags;
    is($tags{tiff_sample_format}, 3, "check sample format");
    is($tags{tiff_sample_format_name}, "ieeefp", "check sample format name");
  }
}
