#!perl -w

=pod

IF THIS TEST CRASHES

Giflib/libungif have a long history of bugs, so if this script crashes
and you aren't running version 4.1.4 of giflib or libungif then
UPGRADE.

=cut

use strict;
$|=1;
use Test::More;
use Imager qw(:all);
use Imager::Test qw(is_color3 test_image test_image_raw test_image_mono);
use Imager::File::GIF;

use Carp 'confess';
$SIG{__DIE__} = sub { confess @_ };

-d "testout" or mkdir "testout";

init_log("testout/t105gif.log",1);

plan tests => 146;

my $green=i_color_new(0,255,0,255);
my $blue=i_color_new(0,0,255,255);
my $red=i_color_new(255,0,0,255);

my $img=test_image_raw;

my $gifver = Imager::File::GIF::i_giflib_version();
diag("giflib version (from header) $gifver");

{
  open(FH,">testout/t105.gif") || die "Cannot open testout/t105.gif\n";
  binmode(FH);
  my $io = Imager::io_new_fd(fileno(FH));
  ok(Imager::File::GIF::i_writegif_wiol($io, {}, $img), "write low") or
    die "Cannot write testout/t105.gif\n";
  $io->close;
  close(FH);
}

{
  open(FH,"testout/t105.gif") || die "Cannot open testout/t105.gif\n";
  binmode(FH);
  my $io = Imager::io_new_fd(fileno(FH));
  ok($img=Imager::File::GIF::i_readgif_wiol($io), "read low")
    or die "Cannot read testout/t105.gif\n";
  close(FH);
}

{
  open(FH,"testout/t105.gif") || die "Cannot open testout/t105.gif\n";
  binmode(FH);
  my $io = Imager::io_new_fd(fileno(FH));
  ($img, my $palette)=Imager::File::GIF::i_readgif_wiol($io);
  ok($img, "read palette") or die "Cannot read testout/t105.gif\n";
  close(FH);
  $palette=''; # just to skip a warning.
}


# check that reading interlaced/non-interlaced versions of 
# the same GIF produce the same image
# I could replace this with code that used Imager's built-in
# image comparison code, but I know this code revealed the error
{
  open(FH, "<testimg/scalei.gif") || die "Cannot open testimg/scalei.gif";
  binmode FH;
  my $io = Imager::io_new_fd(fileno(FH));
  my ($imgi) = Imager::File::GIF::i_readgif_wiol($io);
  ok($imgi, "read interlaced") or die "Cannot read testimg/scalei.gif";
  close FH;

  open FH, "<testimg/scale.gif" or die "Cannot open testimg/scale.gif";
  binmode FH;
  $io = Imager::io_new_fd(fileno(FH));
  my ($imgni) = Imager::File::GIF::i_readgif_wiol($io);
  ok($imgni, "read normal") or die "Cannot read testimg/scale.gif";
  close FH;

  open FH, ">testout/t105i.ppm" or die "Cannot create testout/t105i.ppm";
  binmode FH;
  my $IO = Imager::io_new_fd( fileno(FH) );
  i_writeppm_wiol($imgi, $IO)
    or die "Cannot write testout/t105i.ppm";
  close FH;

  open FH, ">testout/t105ni.ppm" or die "Cannot create testout/t105ni.ppm";
  binmode FH;
  $IO = Imager::io_new_fd( fileno(FH) );
  i_writeppm_wiol($imgni, $IO)
    or die "Cannot write testout/t105ni.ppm";
  close FH;

  # compare them
  open FH, "<testout/t105i.ppm" or die "Cannot open testout/t105i.ppm";
  my $datai = do { local $/; <FH> };
  close FH;

  open FH, "<testout/t105ni.ppm" or die "Cannot open testout/t105ni.ppm";
  my $datani = do { local $/; <FH> };
  close FH;
  is($datai, $datani, "images match");
}

{
  # reading with a callback
  # various sizes to make sure the buffering works
  # requested size
  open FH, "<testimg/scale.gif" or die "Cannot open testimg/scale.gif";
  binmode FH;
  my $io = Imager::io_new_cb
    (
     undef,
     sub { my $tmp; read(FH, $tmp, $_[0]) and $tmp },
     undef,
     undef
     );
  # no callback version in giflib3, so don't overwrite a good image
  my $img2 = Imager::File::GIF::i_readgif_wiol($io);
  close FH; 
  ok($img, "reading with a callback");
  
  ok(test_readgif_cb(1), "read callback 1 char buffer");
  ok(test_readgif_cb(512), "read callback 512 char buffer");
  ok(test_readgif_cb(1024), "read callback 1024 char buffer");
}
# new writegif_gen
# test webmap, custom errdiff map
# (looks fairly awful)
{
  open FH, ">testout/t105_gen.gif" or die $!;
  binmode FH;
  my $io = Imager::io_new_fd(fileno(FH));
  ok(Imager::File::GIF::i_writegif_wiol
     ($io, { make_colors=>'webmap',
	     translate=>'errdiff',
	     errdiff=>'custom',
	     errdiff_width=>2,
	     errdiff_height=>2,
	     errdiff_map=>[0, 1, 1, 0]}, $img),
     "webmap, custom errdif map");
  close FH;
}

print "# the following tests are fairly slow\n";

# test animation, mc_addi, error diffusion, ordered transparency
my @imgs;
my $sortagreen = i_color_new(0, 255, 0, 63);
for my $i (0..4) {
  my $im = Imager::ImgRaw::new(200, 200, 4);
  _add_tags($im, gif_delay=>50, gif_disposal=>2);
  for my $j (0..$i-1) {
    my $fill = i_color_new(0, 128, 0, 255 * ($i-$j)/$i);
    i_box_filled($im, 0, $j*40, 199, $j*40+40, $fill);
  }
  i_box_filled($im, 0, $i*40, 199, 199, $blue);
  push(@imgs, $im);
}
{
  my @gif_delays = (50) x 5;
  my @gif_disposal = (2) x 5;
  open FH, ">testout/t105_anim.gif" or die $!;
  binmode FH;
  my $io = Imager::io_new_fd(fileno(FH));
  ok(Imager::File::GIF::i_writegif_wiol
     ($io, { make_colors=>'addi',
	     translate=>'closest',
	     gif_delays=>\@gif_delays,
	     gif_disposal=>\@gif_disposal,
	     gif_positions=> [ map [ $_*10, $_*10 ], 0..4 ],
	     gif_user_input=>[ 1, 0, 1, 0, 1 ],
	     transp=>'ordered',
	     'tr_orddith'=>'dot8'}, @imgs),
     "write anim gif");
  close FH;
}

@imgs = ();
my $c = i_color_new(0,0,0,0);
for my $g (0..3) {
  my $im = Imager::ImgRaw::new(200, 200, 3);
  _add_tags($im, gif_local_map=>1, gif_delay=>150, gif_loop=>10);
  for my $x (0 .. 39) {
    for my $y (0 .. 39) {
      $c->set($x * 6, $y * 6, 32*$g+$x+$y, 255);
      i_box_filled($im, $x*5, $y*5, $x*5+4, $y*5+4, $c);
    }
  }
  push(@imgs, $im);
}
# test giflib with multiple palettes
# (it was meant to test the NS loop extension too, but that's broken)
# this looks better with make_colors=>'addi', translate=>'errdiff'
# this test aims to overload the palette for each image, so the
# output looks moderately horrible
{
  open FH, ">testout/t105_mult_pall.gif" or die "Cannot create file: $!";
  binmode FH;
  my $io = Imager::io_new_fd(fileno(FH));
  ok(Imager::File::GIF::i_writegif_wiol
     ($io, { #make_colors=>'webmap',
	    translate=>'giflib',
	   }, @imgs), "write multiple palettes")
    or print "# ", join(":", map $_->[1], Imager::i_errors()),"\n";
  close FH;
}

{
  # regression test: giflib doesn't like 1 colour images
  my $img1 = Imager::ImgRaw::new(100, 100, 3);
  i_box_filled($img1, 0, 0, 100, 100, $red);
  open FH, ">testout/t105_onecol.gif" or die $!;
  binmode FH;
  my $io = Imager::io_new_fd(fileno(FH));
  ok(Imager::File::GIF::i_writegif_wiol($io, { translate=>'giflib'}, $img1),
     "single colour write regression");
  close FH;
}

{
  # transparency test
  # previously it was harder do write transparent images
  # tests the improvements
  my $timg = Imager::ImgRaw::new(20, 20, 4);
  my $trans = i_color_new(255, 0, 0, 127);
  i_box_filled($timg, 0, 0, 20, 20, $green);
  i_box_filled($timg, 2, 2, 18, 18, $trans);
  open FH, ">testout/t105_trans.gif" or die $!;
  binmode FH;
  my $io = Imager::io_new_fd(fileno(FH));
  ok(Imager::File::GIF::i_writegif_wiol
     ($io, { make_colors=>'addi',
	     translate=>'closest',
	     transp=>'ordered',
	   }, $timg), "write transparent");
  close FH;
}

# some error handling tests
# open a file handle for read and try to save to it
# is this idea portable?
# whether or not it is, giflib segfaults on this <sigh>
#open FH, "<testout/t105_trans.gif" or die $!;
#binmode FH; # habit, I suppose
#if (i_writegif_gen(fileno(FH), {}, $timg)) {
#  # this is meant to _fail_
#  print "not ok 18 # writing to read-only should fail";
#}
#else {
#  print "ok 18 # ",Imager::_error_as_msg(),"\n";
#}
#close FH;

{
  # try to read a file of the wrong format - the script will do
  open FH, "<t/t10gif.t"
    or die "Cannot open this script!: $!";
  binmode FH;
  my $io = Imager::io_new_fd(fileno(FH));
  ok(!Imager::File::GIF::i_readgif_wiol($io), 
     "read test script as gif should fail ". Imager::_error_as_msg());
  close FH;
}

{
  # try to save no images :)
  open FH, ">testout/t105_none.gif"
    or die "Cannot open testout/t105_none.gif: $!";
  binmode FH;
  my $io = Imager::io_new_fd(fileno(FH));
  if (ok(!Imager::File::GIF::i_writegif_wiol($io, {}, "hello"), "shouldn't be able to write a string as a gif")) {
    print "# ",Imager::_error_as_msg(),"\n";
  }
}

# try to read a truncated gif (no image descriptors)
read_failure('testimg/trimgdesc.gif');
# file truncated just after the image descriptor tag
read_failure('testimg/trmiddesc.gif');
# image has no colour map
read_failure('testimg/nocmap.gif');

{
  # image has a local colour map
  open FH, "< testimg/loccmap.gif"
    or die "Cannot open testimg/loccmap.gif: $!";
  binmode FH;
  my $io = Imager::io_new_fd(fileno(FH));
  ok(Imager::File::GIF::i_readgif_wiol($io),
     "read an image with only a local colour map");
  close FH;
}

{
  # image has global and local colour maps
  open FH, "< testimg/screen2.gif"
    or die "Cannot open testimg/screen2.gif: $!";
  binmode FH;
  my $io = Imager::io_new_fd(fileno(FH));
  my $ims = Imager::File::GIF::i_readgif_wiol($io);
  unless (ok($ims, "read an image with global and local colour map")) {
    print "# ",Imager::_error_as_msg(),"\n";
  }
  close FH;
  
  open FH, "< testimg/expected.gif"
    or die "Cannot open testimg/expected.gif: $!";
  binmode FH;
  $io = Imager::io_new_fd(fileno(FH));
  my $ime = Imager::File::GIF::i_readgif_wiol($io);
  close FH;
  ok($ime, "reading testimg/expected.gif");
 SKIP:
  {
    skip("could not read one or both of expected.gif or loccamp.gif", 1)
      unless $ims and $ime;
    unless (is(i_img_diff($ime, $ims), 0, 
	       "compare loccmap and expected")) {
      # save the bad one
      open FH, "> testout/t105_screen2.gif"
	or die "Cannot create testout/t105_screen.gif: $!";
      binmode FH;
      my $io = Imager::io_new_fd(fileno(FH));
      Imager::File::GIF::i_writegif_wiol($io, {}, $ims)
	or print "# could not save t105_screen.gif\n";
      close FH;
    }
  }
}

{
  # test reading a multi-image file into multiple images
  open FH, "< testimg/screen2.gif"
    or die "Cannot open testimg/screen2.gif: $!";
  binmode FH;
  my $io = Imager::io_new_fd(fileno(FH));
  @imgs = Imager::File::GIF::i_readgif_multi_wiol($io);
  ok(@imgs, "read multi-image file into multiple images");
  close FH;
  is(@imgs, 2, "should be 2 images");
  my $paletted = 1;
  for my $img (@imgs) {
    unless (Imager::i_img_type($img) == 1) {
      $paletted = 0;
      last;
    }
  }
  ok($paletted, "both images should be paletted");
  is(Imager::i_colorcount($imgs[0]), 4, "4 colours in first image");
  is(Imager::i_colorcount($imgs[1]), 2, "2 colours in second image");
  ok(Imager::i_tags_find($imgs[0], "gif_left", 0), 
     "gif_left tag should be there");
  my @tags = map {[ Imager::i_tags_get($imgs[1], $_) ]} 0..Imager::i_tags_count($imgs[1])-1;
  my ($left) = grep $_->[0] eq 'gif_left', @tags;
  ok($left && $left->[1] == 3, "check gif_left value");
}

{
  # screen3.gif was saved with 
  open FH, "< testimg/screen3.gif"
    or die "Cannot open testimg/screen3.gif: $!";
  binmode FH;
  my $io = Imager::io_new_fd(fileno(FH));
  @imgs = Imager::File::GIF::i_readgif_multi_wiol($io);
  ok(@imgs, "read screen3.gif");
  close FH;
  eval {
    require 'Data/Dumper.pm';
    Data::Dumper->import();
  };

  unless ($@) {
    # build a big map of all tags for all images
    my @tags = 
      map { 
	my $im = $_; 
	[ 
	 map { join ",", map { defined() ? $_ : "undef" } Imager::i_tags_get($im, $_) } 
	 0..Imager::i_tags_count($_)-1 
	] 
      } @imgs;
    my $dump = Dumper(\@tags);
    $dump =~ s/^/# /mg;
    print "# tags from gif\n", $dump;
  }

  # at this point @imgs should contain only paletted images
  ok(Imager::i_img_type($imgs[0]) == 1, "imgs[0] paletted");
  ok(Imager::i_img_type($imgs[1]) == 1, "imgs[1] paletted");

  # see how we go saving it
  open FH, ">testout/t105_pal.gif" or die $!;
  binmode FH;
  $io = Imager::io_new_fd(fileno(FH));
  ok(Imager::File::GIF::i_writegif_wiol
     ($io, { make_colors=>'addi',
	     translate=>'closest',
	     transp=>'ordered',
	   }, @imgs), "write from paletted")
    or diag(Imager->_error_as_msg());
  close FH;
  
  # make sure nothing bad happened
  open FH, "< testout/t105_pal.gif" or die $!;
  binmode FH;
  $io = Imager::io_new_fd(fileno(FH));
  ok((my @imgs2 = Imager::File::GIF::i_readgif_multi_wiol($io)) == 2,
     "re-reading saved paletted images");
  ok(i_img_diff($imgs[0], $imgs2[0]) == 0, "imgs[0] mismatch");
  ok(i_img_diff($imgs[1], $imgs2[1]) == 0, "imgs[1] mismatch");
}

# test that the OO interface warns when we supply old options
{
  my @warns;
  local $SIG{__WARN__} = sub { push(@warns, "@_") };
  
  my $ooim = Imager->new;
  ok($ooim->read(file=>"testout/t105.gif"), "read into object");
  ok($ooim->write(file=>"testout/t105_warn.gif", interlace=>1),
     "save from object")
    or print "# ", $ooim->errstr, "\n";
  ok(grep(/Obsolete .* interlace .* gif_interlace/, @warns),
     "check for warning");
  init(warn_obsolete=>0);
  @warns = ();
  ok($ooim->write(file=>"testout/t105_warn.gif", interlace=>1),
     "save from object");
  ok(!grep(/Obsolete .* interlace .* gif_interlace/, @warns),
     "check for warning");
}

# test that we get greyscale from 1 channel images
# we check for each makemap, and for each translate
print "# test writes of grayscale images - ticket #365\n"; 
my $ooim = Imager->new(xsize=>50, ysize=>50, channels=>1);
for (my $y = 0; $y < 50; $y += 10) {
  $ooim->box(box=>[ 0, $y, 49, $y+9], color=>NC($y*5,0,0), filled=>1);
}
my $ooim3 = $ooim->convert(preset=>'rgb');
#$ooim3->write(file=>'testout/t105gray.ppm');
my %maxerror = ( mediancut => 51000, 
		 addi => 0,
		 closest => 0,
		 perturb => 0,
		 errdiff => 0 );
for my $makemap (qw(mediancut addi)) {
  print "# make_colors => $makemap\n";
  ok( $ooim->write(file=>"testout/t105gray-$makemap.gif",
		   make_colors=>$makemap,
		   gifquant=>'gen'),
      "writing gif with makemap $makemap");
  my $im2 = Imager->new;
  if (ok($im2->read(file=>"testout/t105gray-$makemap.gif"),
	 "reading written grayscale gif")) {
    my $diff = i_img_diff($ooim3->{IMG}, $im2->{IMG});
    ok($diff <= $maxerror{$makemap}, "comparing images $diff");
    #$im2->write(file=>"testout/t105gray-$makemap.ppm");
  }
  else {
  SKIP: { skip("could not get test image", 1); }
  }
}
for my $translate (qw(closest perturb errdiff)) {
  print "# translate => $translate\n";
  my @colors = map NC($_*50, $_*50, $_*50), 0..4;
  ok($ooim->write(file=>"testout/t105gray-$translate.gif",
		  translate=>$translate,
		  make_colors=>'none',
		  colors=>\@colors,
		  gifquant=>'gen'),
     "writing gif with translate $translate");
  my $im2 = Imager->new;
  if (ok($im2->read(file=>"testout/t105gray-$translate.gif"),
	 "reading written grayscale gif")) {
    my $diff = i_img_diff($ooim3->{IMG}, $im2->{IMG});
    ok($diff <= $maxerror{$translate}, "comparing images $diff");
    #$im2->write(file=>"testout/t105gray-$translate.ppm");
  }
  else {
  SKIP: { skip("could not load test image", 1) }
  }
    }

# try to write an image with no colors - should error
ok(!$ooim->write(file=>"testout/t105nocolors.gif",
		 make_colors=>'none',
		 colors=>[], gifquant=>'gen'),
   "write with no colors");

# try to write multiple with no colors, with separate maps
# I don't see a way to test this, since we don't have a mechanism
# to give the second image different quant options, we can't trigger
# a failure just for the second image

# check that the i_format tag is set for both multiple and single
# image reads
{
  my @anim = Imager->read_multi(file=>"testout/t105_anim.gif");
  ok(@anim == 5, "check we got all the images");
  for my $frame (@anim) {
    my ($type) = $frame->tags(name=>'i_format');
    is($type, 'gif', "check i_format for animation frame");
  }
  
  my $im = Imager->new;
  ok($im->read(file=>"testout/t105.gif"), "read some gif");
  my ($type) = $im->tags(name=>'i_format');
  is($type, 'gif', 'check i_format for single image read');
}

{ # check file limits are checked
  my $limit_file = "testout/t105.gif";
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
  print "# test OO interface reading of consolidated images\n";
  my $im = Imager->new;
  ok($im->read(file=>'testimg/screen2.gif', gif_consolidate=>1),
     "read image to consolidate");
  my $expected = Imager->new;
  ok($expected->read(file=>'testimg/expected.gif'),
     "read expected via OO");
  is(i_img_diff($im->{IMG}, $expected->{IMG}), 0,
     "compare them");
  
  # check the default read doesn't match
  ok($im->read(file=>'testimg/screen2.gif'),
     "read same image without consolidate");
  isnt(i_img_diff($im->{IMG}, $expected->{IMG}), 0,
       "compare them - shouldn't include the overlayed second image");
}
{
  print "# test the reading of single pages\n";
  # build a test file
  my $test_file = 'testout/t105_multi_sing.gif';
  my $im1 = Imager->new(xsize=>100, ysize=>100);
  $im1->box(filled=>1, color=>$blue);
  $im1->addtag(name=>'gif_left', value=>10);
  $im1->addtag(name=>'gif_top', value=>15);
  $im1->addtag(name=>'gif_comment', value=>'First page');
  my $im2 = Imager->new(xsize=>50, ysize=>50);
  $im2->box(filled=>1, color=>$red);
  $im2->addtag(name=>'gif_left', value=>30);
  $im2->addtag(name=>'gif_top', value=>25);
  $im2->addtag(name=>'gif_comment', value=>'Second page');
  my $im3 = Imager->new(xsize=>25, ysize=>25);
  $im3->box(filled=>1, color=>$green);
  $im3->addtag(name=>'gif_left', value=>35);
  $im3->addtag(name=>'gif_top', value=>45);
  # don't set comment for $im3
  ok(Imager->write_multi({ file=> $test_file}, $im1, $im2, $im3),
     "write test file for single page reads");
  
  my $res = Imager->new;
  # check we get the first image
  ok($res->read(file=>$test_file), "read default (first) page");
  is(i_img_diff($im1->{IMG}, $res->{IMG}), 0, "compare against first");
  # check tags
  is($res->tags(name=>'gif_left'), 10, "gif_left");
  is($res->tags(name=>'gif_top'), 15, "gif_top");
  is($res->tags(name=>'gif_comment'), 'First page', "gif_comment");
  
  # get the second image
  ok($res->read(file=>$test_file, page=>1), "read second page")
    or print "# ",$res->errstr, "\n";
  is(i_img_diff($im2->{IMG}, $res->{IMG}), 0, "compare against second");
  # check tags
  is($res->tags(name=>'gif_left'), 30, "gif_left");
  is($res->tags(name=>'gif_top'), 25, "gif_top");
  is($res->tags(name=>'gif_comment'), 'Second page', "gif_comment");
  
  # get the third image
  ok($res->read(file=>$test_file, page=>2), "read third page")
    or print "# ",$res->errstr, "\n";
  is(i_img_diff($im3->{IMG}, $res->{IMG}), 0, "compare against third");
  is($res->tags(name=>'gif_left'), 35, "gif_left");
  is($res->tags(name=>'gif_top'), 45, "gif_top");
  is($res->tags(name=>'gif_comment'), undef, 'gif_comment undef');
  
  # try to read a fourth page
    ok(!$res->read(file=>$test_file, page=>3), "fail reading fourth page");
  cmp_ok($res->errstr, "=~", 'page 3 not found',
	 "check error message");
}
SKIP:
{
  skip("gif_loop not supported on giflib before 4.1", 6) 
    unless $gifver >= 4.1;
  # testing writing the loop extension
  my $im1 = Imager->new(xsize => 100, ysize => 100);
  $im1->box(filled => 1, color => '#FF0000');
  my $im2 = Imager->new(xsize => 100, ysize => 100);
  $im2->box(filled => 1, color => '#00FF00');
  ok(Imager->write_multi({
			  gif_loop => 5, 
			  gif_delay => 50, 
			  file => 'testout/t105loop.gif'
			 }, $im1, $im2),
     "write with loop extension");
  
  my @im = Imager->read_multi(file => 'testout/t105loop.gif');
  is(@im, 2, "read loop images back");
  is($im[0]->tags(name => 'gif_loop'), 5, "first loop read back");
  is($im[1]->tags(name => 'gif_loop'), 5, "second loop read back");
  is($im[0]->tags(name => 'gif_delay'), 50, "first delay read back");
  is($im[1]->tags(name => 'gif_delay'), 50, "second delay read back");
}
SKIP:
{ # check graphic control extension and ns loop tags are read correctly
  print "# check GCE and netscape loop extension tag values\n";
  my @im = Imager->read_multi(file => 'testimg/screen3.gif');
  is(@im, 2, "read 2 images from screen3.gif")
    or skip("Could not load testimg/screen3.gif:".Imager->errstr, 11);
  is($im[0]->tags(name => 'gif_delay'),          50, "0 - gif_delay");
  is($im[0]->tags(name => 'gif_disposal'),        2, "0 - gif_disposal");
  is($im[0]->tags(name => 'gif_trans_index'), undef, "0 - gif_trans_index");
  is($im[0]->tags(name => 'gif_user_input'),      0, "0 - gif_user_input");
  is($im[0]->tags(name => 'gif_loop'),            0, "0 - gif_loop");
  is($im[1]->tags(name => 'gif_delay'),          50, "1 - gif_delay");
  is($im[1]->tags(name => 'gif_disposal'),        2, "1 - gif_disposal");
  is($im[1]->tags(name => 'gif_trans_index'),     7, "1 - gif_trans_index");
  is($im[1]->tags(name => 'gif_trans_color'), 'color(255,255,255,0)',
     "1 - gif_trans_index");
  is($im[1]->tags(name => 'gif_user_input'),      0, "1 - gif_user_input");
  is($im[1]->tags(name => 'gif_loop'),            0, "1 - gif_loop");
}

{
  # manually modified from a small gif, this had the palette
  # size changed to half the size, leaving an index out of range
  my $im = Imager->new;
  ok($im->read(file => 'testimg/badindex.gif', type => 'gif'), 
     "read bad index gif")
    or print "# ", $im->errstr, "\n";
  my @indexes = $im->getscanline('y' => 0, type => 'index');
  is_deeply(\@indexes, [ 0..4 ], "check for correct indexes");
  is($im->colorcount, 5, "check the palette was adjusted");
  is_color3($im->getpixel('y' => 0, x => 4), 0, 0, 0, 
	    "check it was black added");
  is($im->tags(name => 'gif_colormap_size'), 4, 'color map size tag');
}

{
  ok(grep($_ eq 'gif', Imager->read_types), "check gif in read types");
  ok(grep($_ eq 'gif', Imager->write_types), "check gif in write types");
}

{
  # check screen tags handled correctly note the screen size
  # supplied is larger than the box covered by the images
  my $im1 = Imager->new(xsize => 10, ysize => 8);
  $im1->settag(name => 'gif_top', value => 4);
  $im1->settag(name => 'gif_screen_width', value => 18);
  $im1->settag(name => 'gif_screen_height', value => 16);
  my $im2 = Imager->new(xsize => 7, ysize => 10);
  $im2->settag(name => 'gif_left', value => 3);
  my @im = ( $im1, $im2 );
  
  my $data;
  ok(Imager->write_multi({ data => \$data, type => 'gif' }, @im),
     "write with screen settings")
    or print "# ", Imager->errstr, "\n";
  my @result = Imager->read_multi(data => $data);
  is(@result, 2, "got 2 images back");
  is($result[0]->tags(name => 'gif_screen_width'), 18,
     "check result screen width");
  is($result[0]->tags(name => 'gif_screen_height'), 16,
     "check result screen height");
  is($result[0]->tags(name => 'gif_left'), 0,
     "check first gif_left");
  is($result[0]->tags(name => 'gif_top'), 4,
     "check first gif_top");
  is($result[1]->tags(name => 'gif_left'), 3,
     "check second gif_left");
  is($result[1]->tags(name => 'gif_top'), 0,
     "check second gif_top");
}

{ # test colors array returns colors
  my $data;
  my $im = test_image();
  my @colors;
  ok($im->write(data => \$data, 
		colors => \@colors, 
		make_colors => 'webmap', 
		translate => 'closest',
		gifquant => 'gen',
		type => 'gif'),
     "write using webmap to check color table");
  is(@colors, 216, "should be 216 colors in the webmap");
  is_color3($colors[0], 0, 0, 0, "first should be 000000");
  is_color3($colors[1], 0, 0, 0x33, "second should be 000033");
  is_color3($colors[8], 0, 0x33, 0x66, "9th should be 003366");
}

{ # a zero length extension could make read_/read_multi crash
  my ($im) = Imager->read_multi(file => "testimg/zerocomm.gif");
  ok($im, "read image with zero-length extension");
}


{ # check close failures are handled correctly
  my $im = test_image_mono();
  my $fail_close = sub {
    Imager::i_push_error(0, "synthetic close failure");
    return 0;
  };
  ok(!$im->write(type => "gif", callback => sub { 1 },
		 closecb => $fail_close),
     "check failing close fails");
    like($im->errstr, qr/synthetic close failure/,
	 "check error message");
}


sub test_readgif_cb {
  my ($size) = @_;

  open FH, "<testimg/scale.gif" or die "Cannot open testimg/scale.gif";
  binmode FH;
  my $io = Imager::io_new_cb
    (
     undef,
     sub { my $tmp; read(FH, $tmp, $size) and $tmp },
     undef,
     undef
     );
  my $img = Imager::File::GIF::i_readgif_wiol($io);
  close FH; 
  return $img;
}

# tests for reading bad gif files
sub read_failure {
  my ($filename) = @_;

  open FH, "< $filename"
    or die "Cannot open $filename: $!";
  binmode FH;
  my $io = Imager::io_new_fd(fileno(FH));
  my ($result, $map) = Imager::File::GIF::i_readgif_wiol($io);
  ok(!$result, "attempt to read invalid image $filename ".Imager::_error_as_msg());
  close FH;
}

sub _clear_tags {
  my (@imgs) = @_;

  for my $img (@imgs) {
    $img->deltag(code=>0);
  }
}

sub _add_tags {
  my ($img, %tags) = @_;

  for my $key (keys %tags) {
    Imager::i_tags_add($img, $key, 0, $tags{$key}, 0);
  }
}

sub ext_test {
  my ($testnum, $code, $count, $name) = @_;

  $count ||= 1;
  $name ||= "gif$testnum";

  # build our code
  my $script = "testout/$name.pl";
  if (open SCRIPT, "> $script") {
    print SCRIPT <<'PROLOG';
#!perl -w
if (lc $^O eq 'mswin32') {
  # avoid the dialog box that window's pops up on a GPF
  # if you want to debug this stuff, I suggest you comment out the 
  # following
  eval {
    require Win32API::File;
    Win32API::File::SetErrorMode( Win32API::File::SEM_NOGPFAULTERRORBOX());
  };
}
PROLOG

    print SCRIPT $code;
    close SCRIPT;

    my $perl = $^X;
    $perl = qq/"$perl"/ if $perl =~ / /;

    print "# script: $script\n";
    my $cmd = "$perl -Mblib $script";
    print "# command: $cmd\n";

    my $ok = 1;
    my @out = `$cmd`; # should work on DOS and Win32
    my $found = 0;
    for (@out) {
      if (/^not ok\s+(?:\d+\s*)?#(.*)/ || /^not ok/) {
        my $msg = $1 || '';
        ok(0, $msg);
	$ok = 0;
	++$found;
      }
      elsif (/^ok\s+(?:\d+\s*)?#(.*)/ || /^ok/) {
        my $msg = $1 || '';
        ok(1, $msg);
	++$found;
      }
    }
    unless ($count == $found) {
      print "# didn't see enough ok/not ok\n";
      $ok = 0;
    }
    return $ok;
  }
  else {
    return skip("could not create test script $script: $!");
    return 0;
  }
}
