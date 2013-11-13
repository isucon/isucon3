#!perl -w
use strict;
use Test::More tests => 60;

use Imager;
use Imager::Test qw(is_image);

#$Imager::DEBUG=1;

-d "testout" or mkdir "testout";

Imager::init('log'=>'testout/t66paste.log');

# the original smoke tests
my $img=Imager->new() || die "unable to create image object\n";

ok($img->open(file=>'testimg/scale.ppm',type=>'pnm'), "load test img");

my $nimg=Imager->new() or die "Unable to create image object\n";
ok($nimg->open(file=>'testimg/scale.ppm',type=>'pnm'), "load test img again");

ok($img->paste(img=>$nimg, top=>30, left=>30), "paste it")
  or print "# ", $img->errstr, "\n";;

ok($img->write(type=>'pnm',file=>'testout/t66.ppm'), "save it")
  or print "# ", $img->errstr, "\n";

{
  my $empty = Imager->new;
  ok(!$empty->paste(src => $nimg), "paste into empty image");
  is($empty->errstr, "paste: empty input image",
     "check error message");

  ok(!$img->paste(src => $empty), "paste from empty image");
  is($img->errstr, "paste: empty input image (for src)",
     "check error message");

  ok(!$img->paste(), "no source image");
  is($img->errstr, "no source image");
}

# more stringent tests
{
  my $src = Imager->new(xsize => 100, ysize => 110);
  $src->box(filled=>1, color=>'FF0000');

  $src->box(filled=>1, color=>'0000FF', xmin => 20, ymin=>20,
            xmax=>79, ymax=>79);

  my $targ = Imager->new(xsize => 100, ysize => 110);
  $targ->box(filled=>1, color =>'00FFFF');
  $targ->box(filled=>1, color=>'00FF00', xmin=>20, ymin=>20, xmax=>79,
             ymax=>79);
  my $work = $targ->copy;
  ok($work->paste(src=>$src, left => 15, top => 10), "paste whole image");
  # build comparison image
  my $cmp = $targ->copy;
  $cmp->box(filled=>1, xmin=>15, ymin => 10, color=>'FF0000');
  $cmp->box(filled=>1, xmin=>35, ymin => 30, xmax=>94, ymax=>89, 
            color=>'0000FF');

  is(Imager::i_img_diff($work->{IMG}, $cmp->{IMG}), 0,
     "compare pasted and expected");

  $work = $targ->copy;
  ok($work->paste(src=>$src, left=>2, top=>7, src_minx => 10, src_miny => 15),
     "paste from inside src");
  $cmp = $targ->copy;
  $cmp->box(filled=>1, xmin=>2, ymin=>7, xmax=>91, ymax=>101, color=>'FF0000');
  $cmp->box(filled=>1, xmin=>12, ymin=>12, xmax=>71, ymax=>71, 
            color=>'0000FF');
  is(Imager::i_img_diff($work->{IMG}, $cmp->{IMG}), 0,
     "compare pasted and expected");

  # paste part source
  $work = $targ->copy;
  ok($work->paste(src=>$src, left=>15, top=>20, 
                  src_minx=>10, src_miny=>15, src_maxx=>80, src_maxy =>70),
     "paste src cropped all sides");
  $cmp = $targ->copy;
  $cmp->box(filled=>1, xmin=>15, ymin=>20, xmax=>84, ymax=>74, 
            color=>'FF0000');
  $cmp->box(filled=>1, xmin=>25, ymin=>25, xmax=>84, ymax=>74,
            color=>'0000FF');
  is(Imager::i_img_diff($work->{IMG}, $cmp->{IMG}), 0,
     "compare pasted and expected");

  # go by width instead
  $work = $targ->copy;
  ok($work->paste(src=>$src, left=>15, top=>20,
                  src_minx=>10, src_miny => 15, width => 70, height => 55),
     "same but specify width/height instead");
  is(Imager::i_img_diff($work->{IMG}, $cmp->{IMG}), 0,
     "compare pasted and expected");

  # use src_coords
  $work = $targ->copy;
  ok($work->paste(src=>$src, left => 15, top => 20,
                  src_coords => [ 10, 15, 80, 70 ]),
     "using src_coords");
  is(Imager::i_img_diff($work->{IMG}, $cmp->{IMG}), 0,
     "compare pasted and expected");

  {
    # Issue #18712
    # supplying just src_maxx would set the internal maxy to undef
    # supplying just src_maxy would be ignored
    # src_maxy (or it's derived value) was being bounds checked against 
    # the image width instead of the image height
    $work = $targ->copy;
    my @warns;
    local $SIG{__WARN__} = sub { push @warns, "@_"; print "# @_"; };
    
    ok($work->paste(src=>$src, left => 15, top => 20,
		    src_maxx => 50),
       "paste with just src_maxx");
    ok(!@warns, "shouldn't warn");
    my $cmp = $targ->copy;
    $cmp->box(filled=>1, color => 'FF0000', xmin => 15, ymin => 20,
	      xmax => 64, ymax => 109);
    $cmp->box(filled=>1, color => '0000FF', xmin => 35, ymin => 40,
	      xmax => 64, ymax => 99);
    is(Imager::i_img_diff($work->{IMG}, $cmp->{IMG}), 0,
       "check correctly pasted");

    $work = $targ->copy;
    @warns = ();
    ok($work->paste(src=>$src, left=>15, top=>20,
		    src_maxy => 60),
       "paste with just src_maxy");
    ok(!@warns, "shouldn't warn");
    $cmp = $targ->copy;
    $cmp->box(filled => 1, color => 'FF0000', xmin => 15, ymin => 20,
	      xmax => 99, ymax => 79);
    $cmp->box(filled => 1, color => '0000FF', xmin => 35, ymin => 40,
	      xmax => 94, ymax => 79);
    is(Imager::i_img_diff($work->{IMG}, $cmp->{IMG}), 0,
       "check pasted correctly");

    $work = $targ->copy;
    @warns = ();
    ok($work->paste(src=>$src, left=>15, top=>20,
		    src_miny => 20, src_maxy => 105),
       "paste with src_maxy > source width");

    $cmp = $targ->copy;
    $cmp->box(filled => 1, color => 'FF0000', xmin => 15, ymin => 20,
	      ymax => 104);
    $cmp->box(filled => 1, color => '0000FF', xmin => 35, ymin => 20,
	      xmax => 94, ymax => 79);
    is(Imager::i_img_diff($work->{IMG}, $cmp->{IMG}), 0,
       "check pasted correctly");
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
    ok($work->paste(left => 25, top => 25, src => $src1), "paste 1 to 1");
    my $comp = $base->copy;
    $comp->box(filled => 1, color => $g_grey_full, @left_box);
    $comp->box(filled => 1, color => [ 0, 0, 0, 0 ], @right_box);
    is_image($work, $comp, "compare paste target to expected");

    $work = $base->copy;
    ok($work->paste(left => 25, top => 25, src => $src2), "paste 2 to 1");
    $comp = $base->copy;
    $comp->box(filled => 1, @left_box, color => $g_grey_full);
    $comp->box(filled => 1, @right_box, color => [ 128, 0, 0, 0 ]);
    is_image($work, $comp, "compare paste target to expected");

    $work = $base->copy;
    ok($work->paste(left => 25, top => 25, src => $src3), "paste 3 to 1");
     $comp = $base->copy;
    $comp->box(filled => 1, @left_box, color => [ 57, 255, 0, 0 ]);
    $comp->box(filled => 1, @right_box, color => [ 18, 255, 0, 0 ]);
    is_image($work, $comp, "compare paste target to expected");

    $work = $base->copy;
    ok($work->paste(left => 25, top => 25, src => $src4), "paste 4 to 1");
    $comp = $base->copy;
    $comp->box(filled => 1, color => [ 18, 255, 0, 0 ], @left_box);
    $comp->box(filled => 1, color => [ 90, 255, 0, 0 ], @right_box);
    is_image($work, $comp, "compare paste target to expected");
  }

  { # 2 channel output
    my $base = Imager->new(xsize => 100, ysize => 100, channels => 2);
    $base->box(filled => 1, color => [ 128, 128, 0, 0 ]);
    
    my $work = $base->copy;
    ok($work->paste(top => 25, left => 25, src => $src1), "paste 1 to 2");
    my $comp = $base->copy;
    $comp->box(filled => 1, color => $g_grey_full, @left_box);
    $comp->box(filled => 1, color => [ 0, 255, 0, 0 ], @right_box);
    is_image($work, $comp, "compare paste target to expected");

    $work = $base->copy;
    ok($work->paste(top => 25, left => 25, src => $src2), "paste 2 to 2");
    $comp = $base->copy;
    $comp->box(filled => 1, color => $g_grey_full, @left_box);
    $comp->box(filled => 1, color => $g_white_50, @right_box);
    is_image($work, $comp, "compare paste target to expected");

    $work = $base->copy;
    ok($work->paste(top => 25, left => 25, src => $src3), "paste 3 to 2");
    $comp = $base->copy;
    $comp->box(filled => 1, color => [ 57, 255, 0, 0 ], @left_box);
    $comp->box(filled => 1, color => [ 18, 255, 0, 0 ], @right_box);
    is_image($work, $comp, "compare paste target to expected");

    $work = $base->copy;
    ok($work->paste(top => 25, left => 25, src => $src4), "paste 4 to 2");
    $comp = $base->copy;
    $comp->box(filled => 1, color => [ 18, 255, 0, 0 ], @left_box);
    $comp->box(filled => 1, color => [ 180, 127, 0, 0 ], @right_box);
    is_image($work, $comp, "compare paste target to expected");
  }

  { # 3 channel output
    my $base = Imager->new(xsize => 100, ysize => 100, channels => 3);
    $base->box(filled => 1, color => [ 128, 255, 0, 0 ]);
    
    my $work = $base->copy;
    ok($work->paste(top => 25, left => 25, src => $src1), "paste 1 to 3");
    my $comp = $base->copy;
    $comp->box(filled => 1, color => [ 128, 128, 128, 255 ], @left_box);
    $comp->box(filled => 1, color => [ 0, 0, 0, 0 ], @right_box);
    is_image($work, $comp, "compare paste target to expected");

    $work = $base->copy;
    ok($work->paste(top => 25, left => 25, src => $src2), "paste 2 to 3");
    $comp = $base->copy;
    $comp->box(filled => 1, color => [ 128, 128, 128, 255 ], @left_box);
    $comp->box(filled => 1, color => [ 128, 128, 128, 255 ], @right_box);
    is_image($work, $comp, "compare paste target to expected");

    $work = $base->copy;
    ok($work->paste(top => 25, left => 25, src => $src3), "paste 3 to 3");
    $comp = $base->copy;
    $comp->box(filled => 1, color => [ 255, 0, 0 ], @left_box);
    $comp->box(filled => 1, color => [ 0, 0, 255 ], @right_box);
    is_image($work, $comp, "compare paste target to expected");

    $work = $base->copy;
    ok($work->paste(top => 25, left => 25, src => $src4), "paste 4 to 3");
    $comp = $base->copy;
    $comp->box(filled => 1, color => [ 0, 0, 255 ], @left_box);
    $comp->box(filled => 1, color => [ 0, 127, 0 ], @right_box);
    is_image($work, $comp, "compare paste target to expected");
  }

  { # 4 channel output
    my $base = Imager->new(xsize => 100, ysize => 100, channels => 4);
    $base->box(filled => 1, color => [ 128, 255, 64, 128 ]);
    
    my $work = $base->copy;
    ok($work->paste(top => 25, left => 25, src => $src1), "paste 1 to 4");
    my $comp = $base->copy;
    $comp->box(filled => 1, color => [ 128, 128, 128, 255 ], @left_box);
    $comp->box(filled => 1, color => [ 0, 0, 0, 255 ], @right_box);
    is_image($work, $comp, "compare paste target to expected");

    $work = $base->copy;
    ok($work->paste(top => 25, left => 25, src => $src2), "paste 2 to 4");
    $comp = $base->copy;
    $comp->box(filled => 1, color => [ 128, 128, 128, 255 ], @left_box);
    $comp->box(filled => 1, color => [ 255, 255, 255, 128 ], @right_box);
    is_image($work, $comp, "compare paste target to expected");

    $work = $base->copy;
    ok($work->paste(top => 25, left => 25, src => $src3), "paste 3 to 4");
    $comp = $base->copy;
    $comp->box(filled => 1, color => [ 255, 0, 0 ], @left_box);
    $comp->box(filled => 1, color => [ 0, 0, 255 ], @right_box);
    is_image($work, $comp, "compare paste target to expected");

    $work = $base->copy;
    ok($work->paste(top => 25, left => 25, src => $src4), "paste 4 to 4");
    $comp = $base->copy;
    $comp->box(filled => 1, color => $c_blue_full, @left_box);
    $comp->box(filled => 1, color => $c_green_50, @right_box);
    is_image($work, $comp, "compare paste target to expected");
  }
}
