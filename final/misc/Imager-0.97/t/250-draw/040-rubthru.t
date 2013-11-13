#!perl -w
use strict;
use Test::More tests => 76;
use Imager qw(:all :handy);
use Imager::Test qw(is_image);

-d "testout" or mkdir "testout";

init_log("testout/t69rubthru.log", 1);

my $src_height = 80;
my $src_width = 80;

# raw interface
my $targ = Imager::ImgRaw::new(100, 100, 3);
my $src = Imager::ImgRaw::new($src_height, $src_width, 4);
my $halfred = NC(255, 0, 0, 128);
i_box_filled($src, 20, 20, 60, 60, $halfred);
ok(i_rubthru($targ, $src, 10, 10, 0, 0, $src_width, $src_height),
   "low level rubthrough");
my $c = Imager::i_get_pixel($targ, 10, 10);
ok($c, "get pixel at (10, 10)");
ok(color_cmp($c, NC(0, 0, 0)) == 0, "check for correct color");
$c = Imager::i_get_pixel($targ, 30, 30);
ok($c, "get pixel at (30, 30)");
ok(color_cmp($c, NC(128, 0, 0)) == 0, "check color");

my $black = NC(0, 0, 0);
# reset the target and try a grey+alpha source
i_box_filled($targ, 0, 0, 100, 100, $black);
my $gsrc = Imager::ImgRaw::new($src_width, $src_height, 2);
my $halfwhite = NC(255, 128, 0);
i_box_filled($gsrc, 20, 20, 60, 60, $halfwhite);
ok(i_rubthru($targ, $gsrc, 10, 10, 0, 0, $src_width, $src_height),
   "low level with grey/alpha source");
$c = Imager::i_get_pixel($targ, 15, 15);
ok($c, "get at (15, 15)");
ok(color_cmp($c, NC(0, 0, 0)) == 0, "check color");
$c = Imager::i_get_pixel($targ, 30, 30);
ok($c, "get pixel at (30, 30)");
ok(color_cmp($c, NC(128, 128, 128)) == 0, "check color");

# try grey target and grey alpha source
my $gtarg = Imager::ImgRaw::new(100, 100, 1);
ok(i_rubthru($gtarg, $gsrc, 10, 10, 0, 0, $src_width, $src_height), 
   "low level with grey target and gray/alpha source");
$c = Imager::i_get_pixel($gtarg, 10, 10);
ok($c, "get pixel at 10, 10");
is(($c->rgba)[0], 0, "check grey level");
is((Imager::i_get_pixel($gtarg, 30, 30)->rgba)[0], 128,
   "check grey level at 30, 30");

# simple test for 16-bit/sample images
my $targ16 = Imager::i_img_16_new(100, 100, 3);
ok(i_rubthru($targ16, $src, 10, 10, 0, 0, $src_width, $src_height),
   "smoke test vs 16-bit/sample image");
$c = Imager::i_get_pixel($targ16, 30, 30);
ok($c, "get pixel at 30, 30");
ok(color_cmp($c, NC(128, 0, 0)) == 0, "check color");

# check the OO interface
my $ootarg = Imager->new(xsize=>100, ysize=>100);
my $oosrc = Imager->new(xsize=>80, ysize=>80, channels=>4);
$oosrc->box(color=>$halfred, xmin=>20, ymin=>20, xmax=>60, ymax=>60,
            filled=>1);
ok($ootarg->rubthrough(src=>$oosrc, tx=>10, ty=>10),
   "oo rubthrough");
ok(color_cmp(Imager::i_get_pixel($ootarg->{IMG}, 10, 10), NC(0, 0, 0)) == 0,
   "check pixel at 10, 10");
ok(color_cmp(Imager::i_get_pixel($ootarg->{IMG}, 30, 30), NC(128, 0, 0)) == 0,
   "check pixel at 30, 30");

my $oogtarg = Imager->new(xsize=>100, ysize=>100, channels=>1);

{ # check empty image errors
  my $empty = Imager->new;
  ok(!$empty->rubthrough(src => $oosrc), "check empty target");
  is($empty->errstr, 'rubthrough: empty input image', "check error message");
  ok(!$oogtarg->rubthrough(src=>$empty), "check empty source");
  is($oogtarg->errstr, 'rubthrough: empty input image (for src)',
     "check error message");
}

{
  # alpha source and target
  for my $method (qw/rubthrough compose/) {

    my $src = Imager->new(xsize => 10, ysize => 1, channels => 4);
    my $targ = Imager->new(xsize => 10, ysize => 2, channels => 4);

    # simple initialization
    $targ->setscanline('y' => 1, x => 1,
		       pixels =>
		       [
			NC(255, 128, 0, 255),
			NC(255, 128, 0, 128),
			NC(255, 128, 0, 0),
			NC(255, 128, 0, 255),
			NC(255, 128, 0, 128),
			NC(255, 128, 0, 0),
			NC(255, 128, 0, 255),
			NC(255, 128, 0, 128),
			NC(255, 128, 0, 0),
		       ]);
    $src->setscanline('y' => 0,
		      pixels =>
		      [
		       NC(0, 128, 255, 0),
		       NC(0, 128, 255, 0),
		       NC(0, 128, 255, 0),
		       NC(0, 128, 255, 128),
		       NC(0, 128, 255, 128),
		       NC(0, 128, 255, 128),
		       NC(0, 128, 255, 255),
		       NC(0, 128, 255, 255),
		       NC(0, 128, 255, 255),
		      ]);
    ok($targ->$method(src => $src, combine => 'normal',
		      tx => 1, ty => 1), "do 4 on 4 $method");
    iscolora($targ->getpixel(x => 1, 'y' => 1), NC(255, 128, 0, 255),
	     "check at zero source coverage on full targ coverage");
    iscolora($targ->getpixel(x => 2, 'y' => 1), NC(255, 128, 0, 128),
	     "check at zero source coverage on half targ coverage");
    iscolora($targ->getpixel(x => 3, 'y' => 1), NC(255, 128, 0, 0),
	     "check at zero source coverage on zero targ coverage");
    iscolora($targ->getpixel(x => 4, 'y' => 1), NC(127, 128, 128, 255),
	     "check at half source_coverage on full targ coverage");
    iscolora($targ->getpixel(x => 5, 'y' => 1), NC(85, 128, 170, 191),
	     "check at half source coverage on half targ coverage");
    iscolora($targ->getpixel(x => 6, 'y' => 1), NC(0, 128, 255, 128),
	     "check at half source coverage on zero targ coverage");
    iscolora($targ->getpixel(x => 7, 'y' => 1), NC(0, 128, 255, 255),
	     "check at full source_coverage on full targ coverage");
    iscolora($targ->getpixel(x => 8, 'y' => 1), NC(0, 128, 255, 255),
	     "check at full source coverage on half targ coverage");
    iscolora($targ->getpixel(x => 9, 'y' => 1), NC(0, 128, 255, 255),
	     "check at full source coverage on zero targ coverage");
  }
}

{ # https://rt.cpan.org/Ticket/Display.html?id=30908
  # we now adapt the source channels to the target
  # check each combination works as expected

  # various source images
  my $src1 = Imager->new(xsize => 50, ysize => 50, channels => 1);
  my $g_grey_full = Imager::Color->new(128, 255, 0, 0);
  my $g_white_50 = Imager::Color->new(255, 128, 0, 0);
  $src1->box(filled => 1, xmax => 24, color => $g_grey_full);

  my $src2 = Imager->new(xsize => 50, ysize => 50, channels => 2);
  $src2->box(filled => 1, xmax => 24, color => $g_grey_full);
  $src2->box(filled => 1, xmin => 25, color => $g_white_50);

  my $c_red_full = Imager::Color->new(255, 0, 0);
  my $c_blue_full = Imager::Color->new(0, 0, 255);
  my $src3 = Imager->new(xsize => 50, ysize => 50, channels => 3);
  $src3->box(filled => 1, xmax => 24, color => $c_red_full);
  $src3->box(filled => 1, xmin => 25, color => $c_blue_full);

  my $c_green_50 = Imager::Color->new(0, 255, 0, 127);
  my $src4 = Imager->new(xsize => 50, ysize => 50, channels => 4);
  $src4->box(filled => 1, xmax => 24, color => $c_blue_full);
  $src4->box(filled => 1, xmin => 25, color => $c_green_50);

  my @left_box = ( box => [ 25, 25, 49, 74 ] );
  my @right_box = ( box => [ 50, 25, 74, 74 ] );

  { # 1 channel output
    my $base = Imager->new(xsize => 100, ysize => 100, channels => 1);
    $base->box(filled => 1, color => Imager::Color->new(64, 255, 0, 0));

    my $work = $base->copy;
    ok($work->rubthrough(left => 25, top => 25, src => $src1), "rubthrough 1 to 1");
    my $comp = $base->copy;
    $comp->box(filled => 1, color => $g_grey_full, @left_box);
    $comp->box(filled => 1, color => [ 0, 0, 0, 0 ], @right_box);
    is_image($work, $comp, "compare rubthrough target to expected");

    $work = $base->copy;
    ok($work->rubthrough(left => 25, top => 25, src => $src2), "rubthrough 2 to 1");
    $comp = $base->copy;
    $comp->box(filled => 1, @left_box, color => $g_grey_full);
    $comp->box(filled => 1, @right_box, color => [ 159, 0, 0, 0 ]);
    is_image($work, $comp, "compare rubthrough target to expected");

    $work = $base->copy;
    ok($work->rubthrough(left => 25, top => 25, src => $src3), "rubthrough 3 to 1");
     $comp = $base->copy;
    $comp->box(filled => 1, @left_box, color => [ 57, 255, 0, 0 ]);
    $comp->box(filled => 1, @right_box, color => [ 18, 255, 0, 0 ]);
    is_image($work, $comp, "compare rubthrough target to expected");

    $work = $base->copy;
    ok($work->rubthrough(left => 25, top => 25, src => $src4), "rubthrough 4 to 1");
    $comp = $base->copy;
    $comp->box(filled => 1, color => [ 18, 255, 0, 0 ], @left_box);
    $comp->box(filled => 1, color => [ 121, 255, 0, 0 ], @right_box);
    is_image($work, $comp, "compare rubthrough target to expected");
  }

  { # 2 channel output
    my $base = Imager->new(xsize => 100, ysize => 100, channels => 2);
    $base->box(filled => 1, color => [ 128, 128, 0, 0 ]);
    
    my $work = $base->copy;
    ok($work->rubthrough(top => 25, left => 25, src => $src1), "rubthrough 1 to 2");
    my $comp = $base->copy;
    $comp->box(filled => 1, color => $g_grey_full, @left_box);
    $comp->box(filled => 1, color => [ 0, 255, 0, 0 ], @right_box);
    is_image($work, $comp, "compare rubthrough target to expected");

    $work = $base->copy;
    ok($work->rubthrough(top => 25, left => 25, src => $src2), "rubthrough 2 to 2");
    $comp = $base->copy;
    $comp->box(filled => 1, color => $g_grey_full, @left_box);
    $comp->box(filled => 1, color => [ 213, 191, 0, 0 ], @right_box);
    is_image($work, $comp, "compare rubthrough target to expected");

    $work = $base->copy;
    ok($work->rubthrough(top => 25, left => 25, src => $src3), "rubthrough 3 to 2");
    $comp = $base->copy;
    $comp->box(filled => 1, color => [ 57, 255, 0, 0 ], @left_box);
    $comp->box(filled => 1, color => [ 18, 255, 0, 0 ], @right_box);
    is_image($work, $comp, "compare rubthrough target to expected");

    $work = $base->copy;
    ok($work->rubthrough(top => 25, left => 25, src => $src4), "rubthrough 4 to 2");
    $comp = $base->copy;
    $comp->box(filled => 1, color => [ 18, 255, 0, 0 ], @left_box);
    $comp->box(filled => 1, color => [ 162, 191, 0, 0 ], @right_box);
    is_image($work, $comp, "compare rubthrough target to expected");
  }

  { # 3 channel output
    my $base = Imager->new(xsize => 100, ysize => 100, channels => 3);
    $base->box(filled => 1, color => [ 128, 255, 0, 0 ]);
    
    my $work = $base->copy;
    ok($work->rubthrough(top => 25, left => 25, src => $src1), "rubthrough 1 to 3");
    my $comp = $base->copy;
    $comp->box(filled => 1, color => [ 128, 128, 128, 255 ], @left_box);
    $comp->box(filled => 1, color => [ 0, 0, 0, 0 ], @right_box);
    is_image($work, $comp, "compare rubthrough target to expected");

    $work = $base->copy;
    ok($work->rubthrough(top => 25, left => 25, src => $src2), "rubthrough 2 to 3");
    $comp = $base->copy;
    $comp->box(filled => 1, color => [ 128, 128, 128, 255 ], @left_box);
    $comp->box(filled => 1, color => [ 191, 255, 128, 255 ], @right_box);
    is_image($work, $comp, "compare rubthrough target to expected");

    $work = $base->copy;
    ok($work->rubthrough(top => 25, left => 25, src => $src3), "rubthrough 3 to 3");
    $comp = $base->copy;
    $comp->box(filled => 1, color => [ 255, 0, 0 ], @left_box);
    $comp->box(filled => 1, color => [ 0, 0, 255 ], @right_box);
    is_image($work, $comp, "compare rubthrough target to expected");

    $work = $base->copy;
    ok($work->rubthrough(top => 25, left => 25, src => $src4), "rubthrough 4 to 3");
    $comp = $base->copy;
    $comp->box(filled => 1, color => [ 0, 0, 255 ], @left_box);
    $comp->box(filled => 1, color => [ 64, 255, 0 ], @right_box);
    is_image($work, $comp, "compare rubthrough target to expected");
  }

  { # 4 channel output
    my $base = Imager->new(xsize => 100, ysize => 100, channels => 4);
    $base->box(filled => 1, color => [ 128, 255, 64, 128 ]);
    
    my $work = $base->copy;
    ok($work->rubthrough(top => 25, left => 25, src => $src1), "rubthrough 1 to 4");
    my $comp = $base->copy;
    $comp->box(filled => 1, color => [ 128, 128, 128, 255 ], @left_box);
    $comp->box(filled => 1, color => [ 0, 0, 0, 255 ], @right_box);
    is_image($work, $comp, "compare rubthrough target to expected");

    $work = $base->copy;
    ok($work->rubthrough(top => 25, left => 25, src => $src2), "rubthrough 2 to 4");
    $comp = $base->copy;
    $comp->box(filled => 1, color => [ 128, 128, 128, 255 ], @left_box);
    $comp->box(filled => 1, color => [ 213, 255, 192, 191 ], @right_box);
    is_image($work, $comp, "compare rubthrough target to expected");

    $work = $base->copy;
    ok($work->rubthrough(top => 25, left => 25, src => $src3), "rubthrough 3 to 4");
    $comp = $base->copy;
    $comp->box(filled => 1, color => [ 255, 0, 0 ], @left_box);
    $comp->box(filled => 1, color => [ 0, 0, 255 ], @right_box);
    is_image($work, $comp, "compare rubthrough target to expected");

    $work = $base->copy;
    ok($work->rubthrough(top => 25, left => 25, src => $src4), "rubthrough 4 to 4");
    $comp = $base->copy;
    $comp->box(filled => 1, color => $c_blue_full, @left_box);
    $comp->box(filled => 1, color => [ 43, 255, 21, 191], @right_box);
    is_image($work, $comp, "compare rubthrough target to expected");
  }
}

sub color_cmp {
  my ($l, $r) = @_;
  my @l = $l->rgba;
  my @r = $r->rgba;
  print "# (",join(",", @l[0..2]),") <=> (",join(",", @r[0..2]),")\n";
  return $l[0] <=> $r[0]
    || $l[1] <=> $r[1]
      || $l[2] <=> $r[2];
}

sub iscolora {
  my ($c1, $c2, $msg) = @_;

  my $builder = Test::Builder->new;
  my @c1 = $c1->rgba;
  my @c2 = $c2->rgba;
  if (!$builder->ok($c1[0] == $c2[0] && $c1[1] == $c2[1] && $c1[2] == $c2[2]
                    && $c1[3] == $c2[3],
                    $msg)) {
    $builder->diag(<<DIAG);
      got color: [ @c1 ]
 expected color: [ @c2 ]
DIAG
  }
}

