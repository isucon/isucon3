#!perl -w
use strict;
use Test::More tests => 165;

use Imager ':handy';
use Imager::Fill;
use Imager::Color::Float;
use Imager::Test qw(is_image is_color4 is_fcolor4 is_color3);
use Config;

-d "testout" or mkdir "testout";

Imager::init_log("testout/t20fill.log", 1);

my $blue = NC(0,0,255);
my $red = NC(255, 0, 0);
my $redf = Imager::Color::Float->new(1, 0, 0);
my $bluef = Imager::Color::Float->new(0, 0, 1);
my $rsolid = Imager::i_new_fill_solid($blue, 0);
ok($rsolid, "building solid fill");
my $raw1 = Imager::ImgRaw::new(100, 100, 3);
# use the normal filled box
Imager::i_box_filled($raw1, 0, 0, 99, 99, $blue);
my $raw2 = Imager::ImgRaw::new(100, 100, 3);
Imager::i_box_cfill($raw2, 0, 0, 99, 99, $rsolid);
ok(1, "drawing with solid fill");
my $diff = Imager::i_img_diff($raw1, $raw2);
ok($diff == 0, "solid fill doesn't match");
Imager::i_box_filled($raw1, 0, 0, 99, 99, $red);
my $rsolid2 = Imager::i_new_fill_solidf($redf, 0);
ok($rsolid2, "creating float solid fill");
Imager::i_box_cfill($raw2, 0, 0, 99, 99, $rsolid2);
$diff = Imager::i_img_diff($raw1, $raw2);
ok($diff == 0, "float solid fill doesn't match");

# ok solid still works, let's try a hatch
# hash1 is a 2x2 checkerboard
my $rhatcha = Imager::i_new_fill_hatch($red, $blue, 0, 1, undef, 0, 0);
my $rhatchb = Imager::i_new_fill_hatch($blue, $red, 0, 1, undef, 2, 0);
ok($rhatcha && $rhatchb, "can't build hatched fill");

# the offset should make these match
Imager::i_box_cfill($raw1, 0, 0, 99, 99, $rhatcha);
Imager::i_box_cfill($raw2, 0, 0, 99, 99, $rhatchb);
ok(1, "filling with hatch");
$diff = Imager::i_img_diff($raw1, $raw2);
ok($diff == 0, "hatch images different");
$rhatchb = Imager::i_new_fill_hatch($blue, $red, 0, 1, undef, 4, 6);
Imager::i_box_cfill($raw2, 0, 0, 99, 99, $rhatchb);
$diff = Imager::i_img_diff($raw1, $raw2);
ok($diff == 0, "hatch images different");

# I guess I was tired when I originally did this - make sure it keeps
# acting the way it's meant to
# I had originally expected these to match with the red and blue swapped
$rhatchb = Imager::i_new_fill_hatch($red, $blue, 0, 1, undef, 2, 2);
Imager::i_box_cfill($raw2, 0, 0, 99, 99, $rhatchb);
$diff = Imager::i_img_diff($raw1, $raw2);
ok($diff == 0, "hatch images different");

# this shouldn't match
$rhatchb = Imager::i_new_fill_hatch($red, $blue, 0, 1, undef, 1, 1);
Imager::i_box_cfill($raw2, 0, 0, 99, 99, $rhatchb);
$diff = Imager::i_img_diff($raw1, $raw2);
ok($diff, "hatch images the same!");

# custom hatch
# the inverse of the 2x2 checkerboard
my $hatch = pack("C8", 0x33, 0x33, 0xCC, 0xCC, 0x33, 0x33, 0xCC, 0xCC);
my $rcustom = Imager::i_new_fill_hatch($blue, $red, 0, 0, $hatch, 0, 0);
Imager::i_box_cfill($raw2, 0, 0, 99, 99, $rcustom);
$diff = Imager::i_img_diff($raw1, $raw2);
ok(!$diff, "custom hatch mismatch");

{
  # basic test of floating color hatch fills
  # this will exercise the code that the gcc shipped with OS X 10.4
  # forgets to generate
  # the float version is called iff we're working with a non-8-bit image
  # i_new_fill_hatchf() makes the same object as i_new_fill_hatch() but
  # we test the other construction code path here
  my $fraw1 = Imager::i_img_double_new(100, 100, 3);
  my $fhatch1 = Imager::i_new_fill_hatchf($redf, $bluef, 0, 1, undef, 0, 0);
  ok($fraw1, "making double image 1");
  ok($fhatch1, "making float hatch 1");
  Imager::i_box_cfill($fraw1, 0, 0, 99, 99, $fhatch1);
  my $fraw2 = Imager::i_img_double_new(100, 100, 3);
  my $fhatch2 = Imager::i_new_fill_hatchf($bluef, $redf, 0, 1, undef, 0, 2);
  ok($fraw2, "making double image 2");
  ok($fhatch2, "making float hatch 2");
  Imager::i_box_cfill($fraw2, 0, 0, 99, 99, $fhatch2);

  $diff = Imager::i_img_diff($fraw1, $fraw2);
  ok(!$diff, "float custom hatch mismatch");
  save($fraw1, "testout/t20hatchf1.ppm");
  save($fraw2, "testout/t20hatchf2.ppm");
}

# test the oo interface
my $im1 = Imager->new(xsize=>100, ysize=>100);
my $im2 = Imager->new(xsize=>100, ysize=>100);

my $solid = Imager::Fill->new(solid=>'#FF0000');
ok($solid, "creating oo solid fill");
ok($solid->{fill}, "bad oo solid fill");
$im1->box(fill=>$solid);
$im2->box(filled=>1, color=>$red);
$diff = Imager::i_img_diff($im1->{IMG}, $im2->{IMG});
ok(!$diff, "oo solid fill");

my $hatcha = Imager::Fill->new(hatch=>'check2x2');
my $hatchb = Imager::Fill->new(hatch=>'check2x2', dx=>2);
$im1->box(fill=>$hatcha);
$im2->box(fill=>$hatchb);
# should be different
$diff = Imager::i_img_diff($im1->{IMG}, $im2->{IMG});
ok($diff, "offset checks the same!");
$hatchb = Imager::Fill->new(hatch=>'check2x2', dx=>2, dy=>2);
$im2->box(fill=>$hatchb);
$diff = Imager::i_img_diff($im1->{IMG}, $im2->{IMG});
ok(!$diff, "offset into similar check should be the same");

# test dymanic build of fill
$im2->box(fill=>{hatch=>'check2x2', dx=>2, fg=>NC(255,255,255), 
                 bg=>NC(0,0,0)});
$diff = Imager::i_img_diff($im1->{IMG}, $im2->{IMG});
ok(!$diff, "offset and flipped should be the same");

# a simple demo
my $im = Imager->new(xsize=>200, ysize=>200);

$im->box(xmin=>10, ymin=>10, xmax=>190, ymax=>190,
         fill=>{ hatch=>'check4x4',
                 fg=>NC(128, 0, 0),
                 bg=>NC(128, 64, 0) })
  or print "# ",$im->errstr,"\n";
$im->arc(r=>80, d1=>45, d2=>75, 
           fill=>{ hatch=>'stipple2',
                   combine=>1,
                   fg=>[ 0, 0, 0, 255 ],
                   bg=>{ rgba=>[255,255,255,160] } })
  or print "# ",$im->errstr,"\n";
$im->arc(r=>80, d1=>75, d2=>135,
         fill=>{ fountain=>'radial', xa=>100, ya=>100, xb=>20, yb=>100 })
  or print "# ",$im->errstr,"\n";
$im->write(file=>'testout/t20_sample.ppm');

# flood fill tests
my $rffimg = Imager::ImgRaw::new(100, 100, 3);
# build a H 
Imager::i_box_filled($rffimg, 10, 10, 20, 90, $blue);
Imager::i_box_filled($rffimg, 80, 10, 90, 90, $blue);
Imager::i_box_filled($rffimg, 20, 45, 80, 55, $blue);
my $black = Imager::Color->new(0, 0, 0);
Imager::i_flood_fill($rffimg, 15, 15, $red);
my $rffcmp = Imager::ImgRaw::new(100, 100, 3);
# build a H 
Imager::i_box_filled($rffcmp, 10, 10, 20, 90, $red);
Imager::i_box_filled($rffcmp, 80, 10, 90, 90, $red);
Imager::i_box_filled($rffcmp, 20, 45, 80, 55, $red);
$diff = Imager::i_img_diff($rffimg, $rffcmp);
ok(!$diff, "flood fill difference");

my $ffim = Imager->new(xsize=>100, ysize=>100);
my $yellow = Imager::Color->new(255, 255, 0);
$ffim->box(xmin=>10, ymin=>10, xmax=>20, ymax=>90, color=>$blue, filled=>1);
$ffim->box(xmin=>20, ymin=>45, xmax=>80, ymax=>55, color=>$blue, filled=>1);
$ffim->box(xmin=>80, ymin=>10, xmax=>90, ymax=>90, color=>$blue, filled=>1);
ok($ffim->flood_fill('x'=>50, 'y'=>50, color=>$red), "flood fill");
$diff = Imager::i_img_diff($rffcmp, $ffim->{IMG});
ok(!$diff, "oo flood fill difference");
$ffim->flood_fill('x'=>50, 'y'=>50,
                  fill=> {
                          hatch => 'check2x2',
			  fg => '0000FF',
                         });
#                  fill=>{
#                         fountain=>'radial',
#                         xa=>50, ya=>50,
#                         xb=>10, yb=>10,
#                        });
$ffim->write(file=>'testout/t20_ooflood.ppm');

my $copy = $ffim->copy;
ok($ffim->flood_fill('x' => 50, 'y' => 50,
		     color => $red, border => '000000'),
   "border solid flood fill");
is(Imager::i_img_diff($ffim->{IMG}, $rffcmp), 0, "compare");
ok($ffim->flood_fill('x' => 50, 'y' => 50,
		     fill => { hatch => 'check2x2', fg => '0000FF', },
		     border => '000000'),
   "border cfill fill");
is(Imager::i_img_diff($ffim->{IMG}, $copy->{IMG}), 0,
   "compare");

# test combining modes
my $fill = NC(192, 128, 128, 128);
my $target = NC(64, 32, 64);
my $trans_target = NC(64, 32, 64, 128);
my %comb_tests =
  (
   none=>
   { 
    opaque => $fill,
    trans => $fill,
   },
   normal=>
   { 
    opaque => NC(128, 80, 96),
    trans => NC(150, 96, 107, 191),
   },
   multiply => 
   { 
    opaque => NC(56, 24, 48),
    trans => NC(101, 58, 74, 192),
   },
   dissolve => 
   { 
    opaque => [ $target, NC(192, 128, 128, 255) ],
    trans => [ $trans_target, NC(192, 128, 128, 255) ],
   },
   add => 
   { 
    opaque => NC(159, 96, 128),
    trans => NC(128, 80, 96, 255),
   },
   subtract => 
   { 
    opaque => NC(0, 0, 0),
    trans => NC(0, 0, 0, 255),
   },
   diff => 
   { 
    opaque => NC(96, 64, 64),
    trans => NC(127, 85, 85, 192),
   },
   lighten => 
   { 
    opaque => NC(128, 80, 96), 
    trans => NC(149, 95, 106, 192), 
   },
   darken => 
   { 
    opaque => $target,
    trans => NC(106, 63, 85, 192),
   },
   # the following results are based on the results of the tests and
   # are suspect for that reason (and were broken at one point <sigh>)
   # but trying to work them out manually just makes my head hurt - TC
   hue => 
   { 
    opaque => NC(64, 32, 47),
    trans => NC(64, 32, 42, 128),
   },
   saturation => 
   { 
    opaque => NC(63, 37, 64),
    trans => NC(64, 39, 64, 128),
   },
   value => 
   { 
    opaque => NC(127, 64, 128),
    trans => NC(149, 75, 150, 128),
   },
   color => 
   { 
    opaque => NC(64, 37, 52),
    trans => NC(64, 39, 50, 128),
   },
  );

for my $comb (Imager::Fill->combines) {
  my $test = $comb_tests{$comb};
  my $fillobj = Imager::Fill->new(solid=>$fill, combine=>$comb);

  for my $bits (qw(8 double)) {
    {
      my $targim = Imager->new(xsize=>4, ysize=>4, bits => $bits);
      $targim->box(filled=>1, color=>$target);
      $targim->box(fill=>$fillobj);
      my $c = Imager::i_get_pixel($targim->{IMG}, 1, 1);
      my $allowed = $test->{opaque};
      $allowed =~ /ARRAY/ or $allowed = [ $allowed ];
      ok(scalar grep(color_close($_, $c), @$allowed), 
	 "opaque '$comb' $bits bits")
	or print "# got:",join(",", $c->rgba),"  allowed: ", 
	  join("|", map { join(",", $_->rgba) } @$allowed),"\n";
    }
    
    {
      # make sure the alpha path in the combine function produces the same
      # or at least as sane a result as the non-alpha path
      my $targim = Imager->new(xsize=>4, ysize=>4, channels => 4, bits => $bits);
      $targim->box(filled=>1, color=>$target);
      $targim->box(fill=>$fillobj);
      my $c = Imager::i_get_pixel($targim->{IMG}, 1, 1);
      my $allowed = $test->{opaque};
      $allowed =~ /ARRAY/ or $allowed = [ $allowed ];
      ok(scalar grep(color_close4($_, $c), @$allowed), 
	 "opaque '$comb' 4-channel $bits bits")
	or print "# got:",join(",", $c->rgba),"  allowed: ", 
	  join("|", map { join(",", $_->rgba) } @$allowed),"\n";
    }
    
    {
      my $transim = Imager->new(xsize => 4, ysize => 4, channels => 4, bits => $bits);
      $transim->box(filled=>1, color=>$trans_target);
      $transim->box(fill => $fillobj);
      my $c = $transim->getpixel(x => 1, 'y' => 1);
      my $allowed = $test->{trans};
      $allowed =~ /ARRAY/ or $allowed = [ $allowed ];
      ok(scalar grep(color_close4($_, $c), @$allowed), 
	 "translucent '$comb' $bits bits")
	or print "# got:",join(",", $c->rgba),"  allowed: ", 
	  join("|", map { join(",", $_->rgba) } @$allowed),"\n";
    }
  }
}

ok($ffim->arc(r=>45, color=>$blue, aa=>1), "aa circle");
$ffim->write(file=>"testout/t20_aacircle.ppm");

# image based fills
my $green = NC(0, 255, 0);
my $fillim = Imager->new(xsize=>40, ysize=>40, channels=>4);
$fillim->box(filled=>1, xmin=>5, ymin=>5, xmax=>35, ymax=>35, 
             color=>NC(0, 0, 255, 128));
$fillim->arc(filled=>1, r=>10, color=>$green, aa=>1);
my $ooim = Imager->new(xsize=>150, ysize=>150);
$ooim->box(filled=>1, color=>$green, xmin=>70, ymin=>25, xmax=>130, ymax=>125);
$ooim->box(filled=>1, color=>$blue, xmin=>20, ymin=>25, xmax=>80, ymax=>125);
$ooim->arc(r=>30, color=>$red, aa=>1);

my $oocopy = $ooim->copy();
ok($oocopy->arc(fill=>{image=>$fillim, 
                       combine=>'normal',
                       xoff=>5}, r=>40),
   "image based fill");
$oocopy->write(file=>'testout/t20_image.ppm');

# a more complex version
use Imager::Matrix2d ':handy';
$oocopy = $ooim->copy;
ok($oocopy->arc(fill=>{
                       image=>$fillim,
                       combine=>'normal',
                       matrix=>m2d_rotate(degrees=>30),
                       xoff=>5
                       }, r=>40),
   "transformed image based fill");
$oocopy->write(file=>'testout/t20_image_xform.ppm');

ok(!$oocopy->arc(fill=>{ hatch=>"not really a hatch" }, r=>20),
   "error handling of automatic fill conversion");
ok($oocopy->errstr =~ /Unknown hatch type/,
   "error message for automatic fill conversion");

# previous box fills to float images, or using the fountain fill
# got into a loop here

SKIP:
{
  skip("can't test without alarm()", 1) unless $Config{d_alarm};
  skip("Your signals are misconfigured", 1) unless exists $SIG{ALRM};
  local $SIG{ALRM} = sub { die; };

  eval {
    alarm(2);
    ok($ooim->box(xmin=>20, ymin=>20, xmax=>80, ymax=>40,
                  fill=>{ fountain=>'linear', xa=>20, ya=>20, xb=>80, 
                          yb=>20 }), "linear box fill");
    alarm 0;
  };
  $@ and ok(0, "linear box fill $@");
}

# test that passing in a non-array ref returns an error
{
  my $fill = Imager::Fill->new(fountain=>'linear',
                               xa => 20, ya=>20, xb=>20, yb=>40,
                               segments=>"invalid");
  ok(!$fill, "passing invalid segments produces an error");
  cmp_ok(Imager->errstr, '=~', 'array reference',
         "check the error message");
}

# test that colors in segments are converted
{
  my @segs =
    (
     [ 0.0, 0.5, 1.0, '000000', '#FFF', 0, 0 ],
    );
  my $fill = Imager::Fill->new(fountain=>'linear',
                               xa => 0, ya=>20, xb=>49, yb=>20,
                               segments=>\@segs);
  ok($fill, "check that color names are converted")
    or print "# ",Imager->errstr,"\n";
  my $im = Imager->new(xsize=>50, ysize=>50);
  $im->box(fill=>$fill);
  my $left = $im->getpixel('x'=>0, 'y'=>20);
  ok(color_close($left, Imager::Color->new(0,0,0)),
     "check black converted correctly");
  my $right = $im->getpixel('x'=>49, 'y'=>20);
  ok(color_close($right, Imager::Color->new(255,255,255)),
     "check white converted correctly");

  # check that invalid colors handled correctly
  
  my @segs2 =
    (
     [ 0.0, 0.5, 1.0, '000000', 'FxFxFx', 0, 0 ],
    );
  my $fill2 = Imager::Fill->new(fountain=>'linear',
                               xa => 0, ya=>20, xb=>49, yb=>20,
                               segments=>\@segs2);
  ok(!$fill2, "check handling of invalid color names");
  cmp_ok(Imager->errstr, '=~', 'No color named', "check error message");
}

{ # RT #35278
  # hatch fills on a grey scale image don't adapt colors
  for my $bits (8, 'double') {
    my $im_g = Imager->new(xsize => 10, ysize => 10, channels => 1, bits => $bits);
    $im_g->box(filled => 1, color => 'FFFFFF');
    my $fill = Imager::Fill->new
      (
       combine => 'normal', 
       hatch => 'weave', 
       fg => '000000', 
       bg => 'FFFFFF'
      );
    $im_g->box(fill => $fill);
    my $im_c = Imager->new(xsize => 10, ysize => 10, channels => 3, bits => $bits);
    $im_c->box(filled => 1, color => 'FFFFFF');
    $im_c->box(fill => $fill);
    my $im_cg = $im_g->convert(preset => 'rgb');
    is_image($im_c, $im_cg, "check hatch is the same between color and greyscale (bits $bits)");

    # check the same for image fills
    my $grey_fill = Imager::Fill->new
      (
       image => $im_g, 
       combine => 'normal'
      );
    my $im_cfg = Imager->new(xsize => 20, ysize => 20, bits => $bits);
    $im_cfg->box(filled => 1, color => '808080');
    $im_cfg->box(fill => $grey_fill);
    my $rgb_fill = Imager::Fill->new
      (
       image => $im_cg, 
       combine => 'normal'
      );
    my $im_cfc = Imager->new(xsize => 20, ysize => 20, bits => $bits);
    $im_cfc->box(filled => 1, color => '808080');
    $im_cfc->box(fill => $rgb_fill);
    is_image($im_cfg, $im_cfc, "check filling from grey image matches filling from rgb (bits = $bits)");

    my $im_gfg = Imager->new(xsize => 20, ysize => 20, channels => 1, bits => $bits);
    $im_gfg->box(filled => 1, color => '808080');
    $im_gfg->box(fill => $grey_fill);
    my $im_gfg_c = $im_gfg->convert(preset => 'rgb');
    is_image($im_gfg_c, $im_cfg, "check grey filled with grey against base (bits = $bits)");

    my $im_gfc = Imager->new(xsize => 20, ysize => 20, channels => 1, bits => $bits);
    $im_gfc->box(filled => 1, color => '808080');
    $im_gfc->box(fill => $rgb_fill);
    my $im_gfc_c = $im_gfc->convert(preset => 'rgb');
    is_image($im_gfc_c, $im_cfg, "check grey filled with color against base (bits = $bits)");
  }
}

{ # alpha modifying fills
  { # 8-bit/sample
    my $base_img = Imager->new(xsize => 4, ysize => 2, channels => 4);
    $base_img->setscanline
      (
       x => 0, 
       y => 0, 
       pixels => 
       [
	map Imager::Color->new($_),
	qw/FF000020 00FF0080 00008040 FFFF00FF/,
       ],
      );
    $base_img->setscanline
      (
       x => 0, 
       y => 1, 
       pixels => 
       [
	map Imager::Color->new($_),
	qw/FFFF00FF FF000000 00FF0080 00008040/
       ]
      );
    my $base_fill = Imager::Fill->new
      (
       image => $base_img,
       combine => "normal",
      );
    ok($base_fill, "make the base image fill");
    my $fill50 = Imager::Fill->new(type => "opacity", opacity => 0.5, other => $base_fill)
      or print "# ", Imager->errstr, "\n";
    ok($fill50, "make 50% alpha translation fill");

    { # 4 channel image
      my $out = Imager->new(xsize => 10, ysize => 10, channels => 4);
      $out->box(fill => $fill50);
      is_color4($out->getpixel(x => 0, y => 0),
		255, 0, 0, 16, "check alpha output");
      is_color4($out->getpixel(x => 2, y => 1),
		0, 255, 0, 64, "check alpha output");
      $out->box(filled => 1, color => "000000");
      is_color4($out->getpixel(x => 0, y => 0),
		0, 0, 0, 255, "check after clear");
      $out->box(fill => $fill50);
      is_color4($out->getpixel(x => 4, y => 2),
		16, 0, 0, 255, "check drawn against background");
      is_color4($out->getpixel(x => 6, y => 3),
		0, 64, 0, 255, "check drawn against background");
    }
    { # 3 channel image
      my $out = Imager->new(xsize => 10, ysize => 10, channels => 3);
      $out->box(fill => $fill50);
      is_color3($out->getpixel(x => 0, y => 0),
		16, 0, 0, "check alpha output");
      is_color3($out->getpixel(x => 2, y => 1),
		0, 64, 0, "check alpha output");
      is_color3($out->getpixel(x => 0, y => 1),
		128, 128, 0, "check alpha output");
    }
  }
  { # double/sample
    use Imager::Color::Float;
    my $base_img = Imager->new(xsize => 4, ysize => 2, channels => 4, bits => "double");
    $base_img->setscanline
      (
       x => 0, 
       y => 0, 
       pixels => 
       [
	map Imager::Color::Float->new(@$_),
	[ 1, 0, 0, 0.125 ],
	[ 0, 1, 0, 0.5 ],
	[ 0, 0, 0.5, 0.25 ],
	[ 1, 1, 0, 1 ],
       ],
      );
    $base_img->setscanline
      (
       x => 0, 
       y => 1, 
       pixels => 
       [
	map Imager::Color::Float->new(@$_),
	[ 1, 1, 0, 1 ],
	[ 1, 0, 0, 0 ],
	[ 0, 1, 0, 0.5 ],
	[ 0, 0, 0.5, 0.25 ],
       ]
      );
    my $base_fill = Imager::Fill->new
      (
       image => $base_img,
       combine => "normal",
      );
    ok($base_fill, "make the base image fill");
    my $fill50 = Imager::Fill->new(type => "opacity", opacity => 0.5, other => $base_fill)
      or print "# ", Imager->errstr, "\n";
    ok($fill50, "make 50% alpha translation fill");
    my $out = Imager->new(xsize => 10, ysize => 10, channels => 4, bits => "double");
    $out->box(fill => $fill50);
    is_fcolor4($out->getpixel(x => 0, y => 0, type => "float"),
	      1, 0, 0, 0.0625, "check alpha output at 0,0");
    is_fcolor4($out->getpixel(x => 2, y => 1, type => "float"),
	      0, 1, 0, 0.25, "check alpha output at 2,1");
    $out->box(filled => 1, color => "000000");
    is_fcolor4($out->getpixel(x => 0, y => 0, type => "float"),
	      0, 0, 0, 1, "check after clear");
    $out->box(fill => $fill50);
    is_fcolor4($out->getpixel(x => 4, y => 2, type => "float"),
	      0.0625, 0, 0, 1, "check drawn against background at 4,2");
    is_fcolor4($out->getpixel(x => 6, y => 3, type => "float"),
	      0, 0.25, 0, 1, "check drawn against background at 6,3");
  }
  ok(!Imager::Fill->new(type => "opacity"),
     "should fail to make an opacity fill with no other fill object");
  is(Imager->errstr, "'other' parameter required to create opacity fill",
     "check error message");
  ok(!Imager::Fill->new(type => "opacity", other => "xx"),
     "should fail to make an opacity fill with a bad other parameter");
  is(Imager->errstr, "'other' parameter must be an Imager::Fill object to create an opacity fill", 
	 "check error message");

  # check auto conversion of hashes
  ok(Imager::Fill->new(type => "opacity", other => { solid => "FF0000" }),
     "check we auto-create fills")
    or print "# ", Imager->errstr, "\n";

  {
    # fill with combine none was modifying the wrong channel for a
    # no-alpha target image
    my $fill = Imager::Fill->new(solid => "#FFF", combine => "none");
    my $fill2 = Imager::Fill->new
      (
       type => "opacity", 
       opacity => 0.5,
       other => $fill
      );
    my $im = Imager->new(xsize => 1, ysize => 1);
    ok($im->box(fill => $fill2), "fill with replacement opacity fill");
    is_color3($im->getpixel(x => 0, y => 0), 255, 255, 255,
	      "check for correct colour");
  }

  {
    require Imager::Fountain;
    my $fount = Imager::Fountain->new;
    $fount->add(c1 => "FFFFFF"); # simple white to black
    # base fill is a fountain
    my $base_fill = Imager::Fill->new
      (
       fountain => "linear",
       segments => $fount,
       xa => 0, 
       ya => 0,
       xb => 100,
       yb => 100,
      );
    ok($base_fill, "made fountain fill base");
    my $op_fill = Imager::Fill->new
      (
       type => "opacity",
       other => $base_fill,
       opacity => 0.5,
      );
    ok($op_fill, "made opacity fountain fill");
    my $im = Imager->new(xsize => 100, ysize => 100);
    ok($im->box(fill => $op_fill), "draw with it");
  }
}

{ # RT 71309
  my $fount = Imager::Fountain->simple(colors => [ '#804041', '#804041' ],
				       positions => [ 0, 1 ]);
  my $im = Imager->new(xsize => 40, ysize => 40);
  $im->box(filled => 1, color => '#804040');
  my $fill = Imager::Fill->new
    (
     combine => 0,
     fountain => "linear",
     segments => $fount,
     xa => 0, ya => 0,
     xb => 40, yb => 40,
    );
  $im->polygon(fill => $fill,
	       points => 
	       [
		[ 0, 0 ],
		[ 40, 20 ],
		[ 20, 40 ],
	       ]
	      );
  # the bug magnified the differences between the source and destination
  # color, blending between the background and fill colors here only allows
  # for those 2 colors in the result.
  # with the bug extra colors appeared along the edge of the polygon.
  is($im->getcolorcount, 2, "only original and fill color");
}

SKIP:
{
  # the wrong image dimension was used for adjusting vs yoff,
  # producing uncovered parts of the output image
  my $tx = Imager->new(xsize => 30, ysize => 20);
  ok($tx, "create texture image")
    or diag "create texture image", Imager->errstr;
  $tx or skip "no texture image", 7;
  ok($tx->box(filled => 1, color => "ff0000"), "fill texture image")
    or diag "fill texture image", $tx->errstr;
  my $cmp = Imager->new(xsize => 100, ysize => 100);
  ok($cmp, "create comparison image")
    or diag "create comparison image: ", Imager->errstr;
  $cmp or skip "no comparison image", 5;
  ok($cmp->box(filled => 1, color => "FF0000"), "fill compare image")
    or diag "fill compare image: ", $cmp->errstr;
  my $im = Imager->new(xsize => 100, ysize => 100);
  ok($im, "make test image")
    or diag "make test image: ", Imager->errstr;
  $im or skip "no test image", 3;
  my $fill = Imager::Fill->new(image => $tx, yoff => 10);
  ok($fill, "make xoff=10 image fill")
    or diag "make fill: ", Imager->errstr;
  $fill or skip "no fill", 2;
  ok($im->box(fill => $fill), "fill test image")
    or diag "fill test image: ", $im->errstr;
  is_image($im, $cmp, "check test image");
}

sub color_close {
  my ($c1, $c2) = @_;

  my @c1 = $c1->rgba;
  my @c2 = $c2->rgba;

  for my $i (0..2) {
    if (abs($c1[$i]-$c2[$i]) > 2) {
      return 0;
    }
  }
  return 1;
}

sub color_close4 {
  my ($c1, $c2) = @_;

  my @c1 = $c1->rgba;
  my @c2 = $c2->rgba;

  for my $i (0..3) {
    if (abs($c1[$i]-$c2[$i]) > 2) {
      return 0;
    }
  }
  return 1;
}

# for use during testing
sub save {
  my ($im, $name) = @_;

  open FH, "> $name" or die "Cannot create $name: $!";
  binmode FH;
  my $io = Imager::io_new_fd(fileno(FH));
  Imager::i_writeppm_wiol($im, $io) or die "Cannot save to $name";
  undef $io;
  close FH;
}
