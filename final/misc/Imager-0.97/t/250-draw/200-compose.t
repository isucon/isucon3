#!perl -w
use strict;
use Imager qw(:handy);
use Test::More tests => 120;
use Imager::Test qw(is_image is_imaged);

-d "testout" or mkdir "testout";

Imager::init_log("testout/t62compose.log", 1);

my @files;

my %types =
  (
   double =>
   {
    blue => NCF(0, 0, 1),
    red =>  NCF(1, 0, 0),
    green2 => NCF(0, 1, 0, 0.5),
    green2_on_blue => NCF(0, 0.5, 0.5),
    red3_on_blue => NCF(1/3, 0, 2/3),
    green6_on_blue => NCF(0, 1/6, 5/6),
    red2_on_blue => NCF(0.5, 0, 0.5),
    green4_on_blue => NCF(0, 0.25, 0.75),
    gray100 => NCF(1.0, 0, 0),
    gray50 => NCF(0.5, 0, 0),
    is_image => \&is_imaged,
   },
   8 =>
   {
    blue => NC(0, 0, 255),
    red =>  NC(255, 0, 0),
    green2 => NC(0, 255, 0, 128),
    green2_on_blue => NC(0, 128, 127),
    red3_on_blue => NC(85, 0, 170),
    green6_on_blue => NC(0, 42, 213),
    red2_on_blue => NC(128, 0, 127),
    green4_on_blue => NC(0, 64, 191),
    gray100 => NC(255, 0, 0),
    gray50 => NC(128, 0, 0),
    is_image => \&is_image,
   },
  );

for my $type_id (sort keys %types) {
  my $type = $types{$type_id};
  my $blue = $type->{blue};
  my $red = $type->{red};
  my $green2 = $type->{green2};
  my $green2_on_blue = $type->{green2_on_blue};
  my $red3_on_blue = $type->{red3_on_blue};
  my $green6_on_blue = $type->{green6_on_blue};
  my $red2_on_blue = $type->{red2_on_blue};
  my $green4_on_blue = $type->{green4_on_blue};
  my $gray100 = $type->{gray100};
  my $gray50 = $type->{gray50};
  my $is_image = $type->{is_image};

  print "# type $type_id\n";
  my $targ = Imager->new(xsize => 100, ysize => 100, bits => $type_id);
  $targ->box(color => $blue, filled => 1);
  is($targ->type, "direct", "check target image type");
  is($targ->bits, $type_id, "check target bits");

  my $src = Imager->new(xsize => 40, ysize => 40, channels => 4, bits => $type_id);
  $src->box(filled => 1, color => $red, xmax => 19, ymax => 19);
  $src->box(filled => 1, xmin => 20, color => $green2);
  save_to($src, "${type_id}_src");

  my $mask_ones = Imager->new(channels => 1, xsize => 40, ysize => 40, bits => $type_id);
  $mask_ones->box(filled => 1, color => NC(255, 255, 255));


  # mask or full mask, should be the same
  for my $mask_info ([ "nomask" ], [ "fullmask", mask => $mask_ones ]) {
    my ($mask_type, @mask_extras) = @$mask_info;
    print "# $mask_type\n";
    {
      my $cmp = $targ->copy;
      $cmp->box(filled => 1, color => $red,
		xmin=> 5, ymin => 10, xmax => 24, ymax => 29);
      $cmp->box(filled => 1, color => $green2_on_blue,
		xmin => 25, ymin => 10, xmax => 44, ymax => 49);
      {
	my $work = $targ->copy;
	ok($work->compose(src => $src, tx => 5, ty => 10, @mask_extras),
	   "$mask_type - simple compose");
	$is_image->($work, $cmp, "check match");
	save_to($work, "${type_id}_${mask_type}_simple");
      }
      { # >1 opacity
	my $work = $targ->copy;
	ok($work->compose(src => $src, tx => 5, ty => 10, opacity => 2.0, @mask_extras),
	   "$mask_type - compose with opacity > 1.0 acts like opacity=1.0");
	$is_image->($work, $cmp, "check match");
      }
      { # 0 opacity is a failure
	my $work = $targ->copy;
	ok(!$work->compose(src => $src, tx => 5, ty => 10, opacity => 0.0, @mask_extras),
	   "$mask_type - compose with opacity = 0 is an error");
	is($work->errstr, "opacity must be positive", "check message");
      }
    }
    { # compose at 1/3
      my $work = $targ->copy;
      ok($work->compose(src => $src, tx => 7, ty => 33, opacity => 1/3, @mask_extras),
	 "$mask_type - simple compose at 1/3");
      my $cmp = $targ->copy;
      $cmp->box(filled => 1, color => $red3_on_blue,
		xmin => 7, ymin => 33, xmax => 26, ymax => 52);
      $cmp->box(filled => 1, color => $green6_on_blue,
		xmin => 27, ymin => 33, xmax => 46, ymax => 72);
      $is_image->($work, $cmp, "check match");
    }
    { # targ off top left
      my $work = $targ->copy;
      ok($work->compose(src => $src, tx => -5, ty => -3, @mask_extras),
	 "$mask_type - compose off top left");
      my $cmp = $targ->copy;
      $cmp->box(filled => 1, color => $red,
		xmin=> 0, ymin => 0, xmax => 14, ymax => 16);
      $cmp->box(filled => 1, color => $green2_on_blue,
		xmin => 15, ymin => 0, xmax => 34, ymax => 36);
      $is_image->($work, $cmp, "check match");
    }
    { # targ off bottom right
      my $work = $targ->copy;
      ok($work->compose(src => $src, tx => 65, ty => 67, @mask_extras),
	 "$mask_type - targ off bottom right");
      my $cmp = $targ->copy;
      $cmp->box(filled => 1, color => $red,
		xmin=> 65, ymin => 67, xmax => 84, ymax => 86);
      $cmp->box(filled => 1, color => $green2_on_blue,
		xmin => 85, ymin => 67, xmax => 99, ymax => 99);
      $is_image->($work, $cmp, "check match");
    }
    { # src off top left
      my $work = $targ->copy;
      my @more_mask_extras;
      if (@mask_extras) {
	push @more_mask_extras,
	  (
	   mask_left => -5,
	   mask_top => -15,
	  );
      }
      ok($work->compose(src => $src, tx => 10, ty => 20,
			src_left => -5, src_top => -15,
			@mask_extras, @more_mask_extras),
	 "$mask_type - source off top left");
      my $cmp = $targ->copy;
      $cmp->box(filled => 1, color => $red,
		xmin=> 15, ymin => 35, xmax => 34, ymax => 54);
      $cmp->box(filled => 1, color => $green2_on_blue,
	      xmin => 35, ymin => 35, xmax => 54, ymax => 74);
      $is_image->($work, $cmp, "check match");
    }
    {
      # src off bottom right
      my $work = $targ->copy;
      ok($work->compose(src => $src, tx => 10, ty => 20,
			src_left => 10, src_top => 15,
			width => 40, height => 40, @mask_extras),
	 "$mask_type - source off bottom right");
      my $cmp = $targ->copy;
      $cmp->box(filled => 1, color => $red,
		xmin=> 10, ymin => 20, xmax => 19, ymax => 24);
      $cmp->box(filled => 1, color => $green2_on_blue,
		xmin => 20, ymin => 20, xmax => 39, ymax => 44);
      $is_image->($work, $cmp, "check match");
    }
    {
      # simply out of bounds
      my $work = $targ->copy;
      ok(!$work->compose(src => $src, tx => 100, @mask_extras),
	 "$mask_type - off the right of the target");
      $is_image->($work, $targ, "no changes");
      ok(!$work->compose(src => $src, ty => 100, @mask_extras),
	 "$mask_type - off the bottom of the target");
      $is_image->($work, $targ, "no changes");
      ok(!$work->compose(src => $src, tx => -40, @mask_extras),
	 "$mask_type - off the left of the target");
      $is_image->($work, $targ, "no changes");
      ok(!$work->compose(src => $src, ty => -40, @mask_extras),
	 "$mask_type - off the top of the target");
      $is_image->($work, $targ, "no changes");
    }
  }

  # masked tests
  my $mask = Imager->new(xsize => 40, ysize => 40, channels => 1, bits => $type_id);
  $mask->box(filled => 1, xmax => 19, color => $gray100);
  $mask->box(filled => 1, xmin => 20, ymax => 14, xmax => 34,
	     color => $gray50);
  is($mask->bits, $type_id, "check mask bits");
  {
    my $work = $targ->copy;
    ok($work->compose(src => $src, tx => 5, ty => 7,
		      mask => $mask),
       "simple draw masked");
    my $cmp = $targ->copy;
    $cmp->box(filled => 1, color => $red,
	      xmin => 5, ymin => 7, xmax => 24, ymax => 26);
    $cmp->box(filled => 1, color => $green4_on_blue,
	      xmin => 25, ymin => 7, xmax => 39, ymax => 21);
    $is_image->($work, $cmp, "check match");
    save_to($work, "${type_id}_simp_masked");
    save_to($work, "${type_id}_simp_masked_cmp");
  }
  {
    my $work = $targ->copy;
    ok($work->compose(src => $src, tx => 5, ty => 7,
		      mask_left => 5, mask_top => 2, 
		      mask => $mask),
       "draw with mask offset");
    my $cmp = $targ->copy;
    $cmp->box(filled => 1, color => $red,
	      xmin => 5, ymin => 7, xmax => 19, ymax => 26);
    $cmp->box(filled => 1, color => $red2_on_blue,
	      xmin => 20, ymin => 7, xmax => 24, ymax => 19);
    $cmp->box(filled => 1, color => $green4_on_blue,
	      xmin => 25, ymin => 7, xmax => 34, ymax => 19);
    $is_image->($work, $cmp, "check match");
  }
  {
    my $work = $targ->copy;
    ok($work->compose(src => $src, tx => 5, ty => 7,
		      mask_left => -3, mask_top => -2, 
		      mask => $mask),
       "draw with negative mask offsets");
    my $cmp = $targ->copy;
    $cmp->box(filled => 1, color => $red,
	      xmin => 8, ymin => 9, xmax => 24, ymax => 26);
    $cmp->box(filled => 1, color => $green2_on_blue,
	      xmin => 25, ymin => 9, xmax => 27, ymax => 46);
    $cmp->box(filled => 1, color => $green4_on_blue,
	      xmin => 28, ymin => 9, xmax => 42, ymax => 23);
    $is_image->($work, $cmp, "check match");
  }
}

{
  my $empty = Imager->new;
  my $good = Imager->new(xsize => 1, ysize => 1);
  ok(!$empty->compose(src => $good), "can't compose to empty image");
  is($empty->errstr, "compose: empty input image",
     "check error message");
  ok(!$good->compose(src => $empty), "can't compose from empty image");
  is($good->errstr, "compose: empty input image (for src)",
     "check error message");
  ok(!$good->compose(src => $good, mask => $empty),
     "can't compose with empty mask");
  is($good->errstr, "compose: empty input image (for mask)",
     "check error message");
}

unless ($ENV{IMAGER_KEEP_FILES}) {
  unlink @files;
}

sub save_to {
  my ($im, $name) = @_;

  my $type = $ENV{IMAGER_SAVE_TYPE} || "ppm";
  $name = "testout/t62_$name.$type";
  $im->write(file => $name,
	     pnm_write_wide_data => 1);
  push @files, $name;
}
