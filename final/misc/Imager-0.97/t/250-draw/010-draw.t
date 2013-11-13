#!perl -w
use strict;
use Test::More tests => 256;
use Imager ':all';
use Imager::Test qw(is_color3 is_image);
use constant PI => 3.14159265358979;

-d "testout" or mkdir "testout";

init_log("testout/t21draw.log",1);

my $redobj = NC(255, 0, 0);
my $red = 'FF0000';
my $greenobj = NC(0, 255, 0);
my $green = [ 0, 255, 0 ];
my $blueobj = NC(0, 0, 255);
my $blue = { hue=>240, saturation=>1, value=>1 };
my $white = '#FFFFFF';

{
  my $img = Imager->new(xsize=>100, ysize=>500);

  ok($img->box(color=>$blueobj, xmin=>10, ymin=>10, xmax=>48, ymax=>18),
     "box with color obj");
  ok($img->box(color=>$blue, xmin=>10, ymin=>20, xmax=>48, ymax=>28),
     "box with color");
  ok($img->box(color=>$redobj, xmin=>10, ymin=>30, xmax=>28, ymax=>48, filled=>1),
     "filled box with color obj");
  ok($img->box(color=>$red, xmin=>30, ymin=>30, xmax=>48, ymax=>48, filled=>1),
     "filled box with color");

  ok($img->arc('x'=>75, 'y'=>25, r=>24, color=>$redobj),
     "filled arc with colorobj");

  ok($img->arc('x'=>75, 'y'=>25, r=>20, color=>$green),
     "filled arc with colorobj");
  ok($img->arc('x'=>75, 'y'=>25, r=>18, color=>$white, d1=>325, d2=>225),
     "filled arc with color");

  ok($img->arc('x'=>75, 'y'=>25, r=>18, color=>$blue, d1=>225, d2=>325),
     "filled arc with color");
  ok($img->arc('x'=>75, 'y'=>25, r=>15, color=>$green, aa=>1),
     "filled arc with color");

  ok($img->line(color=>$blueobj, x1=>5, y1=>55, x2=>35, y2=>95),
     "line with colorobj");

  # FIXME - neither the start nor end-point is set for a non-aa line
  my $c = Imager::i_get_pixel($img->{IMG}, 5, 55);
  ok(color_cmp($c, $blueobj) == 0, "# TODO start point not set");

  ok($img->line(color=>$red, x1=>10, y1=>55, x2=>40, y2=>95, aa=>1),
     "aa line with color");
  ok($img->line(color=>$green, x1=>15, y1=>55, x2=>45, y2=>95, antialias=>1),
     "antialias line with color");

  ok($img->polyline(points=>[ [ 55, 55 ], [ 90, 60 ], [ 95, 95] ],
		    color=>$redobj),
     "polyline points with color obj");
  ok($img->polyline('x'=>[ 55, 85, 90 ], 'y'=>[60, 65, 95], color=>$green, aa=>1),
     "polyline xy with color aa");
  ok($img->polyline('x'=>[ 55, 80, 85 ], 'y'=>[65, 70, 95], color=>$green, 
		    antialias=>1),
     "polyline xy with color antialias");

  ok($img->setpixel('x'=>[35, 37, 39], 'y'=>[55, 57, 59], color=>$red),
     "set array of pixels");
  ok($img->setpixel('x'=>39, 'y'=>55, color=>$green),
     "set single pixel");
  use Imager::Color::Float;
  my $flred = Imager::Color::Float->new(1, 0, 0, 0);
  my $flgreen = Imager::Color::Float->new(0, 1, 0, 0);
  ok($img->setpixel('x'=>[41, 43, 45], 'y'=>[55, 57, 59], color=>$flred),
     "set array of float pixels");
  ok($img->setpixel('x'=>45, 'y'=>55, color=>$flgreen),
     "set single float pixel");
  my @gp = $img->getpixel('x'=>[41, 43, 45], 'y'=>[55, 57, 59]);
  ok(grep($_->isa('Imager::Color'), @gp) == 3, "check getpixel result type");
  ok(grep(color_cmp($_, NC(255, 0, 0)) == 0, @gp) == 3, 
     "check getpixel result colors");
  my $gp = $img->getpixel('x'=>45, 'y'=>55);
  ok($gp->isa('Imager::Color'), "check scalar getpixel type");
  ok(color_cmp($gp, NC(0, 255, 0)) == 0, "check scalar getpixel color");
  @gp = $img->getpixel('x'=>[35, 37, 39], 'y'=>[55, 57, 59], type=>'float');
  ok(grep($_->isa('Imager::Color::Float'), @gp) == 3, 
     "check getpixel float result type");
  ok(grep(color_cmp($_, $flred) == 0, @gp) == 3,
     "check getpixel float result type");
  $gp = $img->getpixel('x'=>39, 'y'=>55, type=>'float');
  ok($gp->isa('Imager::Color::Float'), "check scalar float getpixel type");
  ok(color_cmp($gp, $flgreen) == 0, "check scalar float getpixel color");

  # more complete arc tests
  ok($img->arc(x=>25, 'y'=>125, r=>20, d1=>315, d2=>45, color=>$greenobj),
     "color arc through angle 0");
  # use diff combine here to make sure double writing is noticable
  ok($img->arc(x=>75, 'y'=>125, r=>20, d1=>315, d2=>45,
	       fill => { solid=>$blueobj, combine => 'diff' }),
     "fill arc through angle 0");
  ok($img->arc(x=>25, 'y'=>175, r=>20, d1=>315, d2=>225, color=>$redobj),
     "concave color arc");
  angle_marker($img, 25, 175, 23, 315, 225);
  ok($img->arc(x=>75, 'y'=>175, r=>20, d1=>315, d2=>225,
	       fill => { solid=>$greenobj, combine=>'diff' }),
     "concave fill arc");
  angle_marker($img, 75, 175, 23, 315, 225);
  ok($img->arc(x=>25, y=>225, r=>20, d1=>135, d2=>45, color=>$redobj),
     "another concave color arc");
  angle_marker($img, 25, 225, 23, 45, 135);
  ok($img->arc(x=>75, y=>225, r=>20, d1=>135, d2=>45, 
	       fill => { solid=>$blueobj, combine=>'diff' }),
     "another concave fillarc");
  angle_marker($img, 75, 225, 23, 45, 135);
  ok($img->arc(x=>25, y=>275, r=>20, d1=>135, d2=>45, color=>$redobj, aa=>1),
     "concave color arc aa");
  ok($img->arc(x=>75, y=>275, r=>20, d1=>135, d2=>45, 
	       fill => { solid=>$blueobj, combine=>'diff' }, aa=>1),
     "concave fill arc aa");

  ok($img->circle(x=>25, y=>325, r=>20, color=>$redobj),
     "color circle no aa");
  ok($img->circle(x=>75, y=>325, r=>20, color=>$redobj, aa=>1),
     "color circle aa");
  ok($img->circle(x=>25, 'y'=>375, r=>20, 
		  fill => { hatch=>'stipple', fg=>$blueobj, bg=>$redobj }),
     "fill circle no aa");
  ok($img->circle(x=>75, 'y'=>375, r=>20, aa=>1,
		  fill => { hatch=>'stipple', fg=>$blueobj, bg=>$redobj }),
     "fill circle aa");

  ok($img->arc(x=>50, y=>450, r=>45, d1=>135, d2=>45, 
	       fill => { solid=>$blueobj, combine=>'diff' }),
     "another concave fillarc");
  angle_marker($img, 50, 450, 47, 45, 135);

  ok($img->write(file=>'testout/t21draw.ppm'),
     "saving output");
}

{
  my $im = Imager->new(xsize => 400, ysize => 400);
  ok($im->arc(x => 200, y => 202, r => 10, filled => 0),
     "draw circle outline");
  is_color3($im->getpixel(x => 200, y => 202), 0, 0, 0,
	    "check center not filled");
  ok($im->arc(x => 198, y => 200, r => 13, filled => 0, color => "#f88"),
     "draw circle outline");
  is_color3($im->getpixel(x => 198, y => 200), 0, 0, 0,
	    "check center not filled");
  ok($im->arc(x => 200, y => 200, r => 24, filled => 0, color => "#0ff"),
     "draw circle outline");
  my $r = 40;
  while ($r < 180) {
    ok($im->arc(x => 200, y => 200, r => $r, filled => 0, color => "#ff0"),
       "draw circle outline r $r");
    $r += 15;
  }
  ok($im->write(file => "testout/t21circout.ppm"),
     "save arc outline");
}

{
  my $im = Imager->new(xsize => 400, ysize => 400);
  {
    my $lc = Imager::Color->new(32, 32, 32);
    my $an = 0;
    while ($an < 360) {
      my $an_r = $an * PI / 180;
      my $ca = cos($an_r);
      my $sa = sin($an_r);
      $im->line(aa => 1, color => $lc,
		x1 => 198 + 5 * $ca, y1 => 202 + 5 * $sa,
		x2 => 198 + 190 * $ca, y2 => 202 + 190 * $sa);
      $an += 5;
    }
  }
  my $d1 = 0;
  my $r = 20;
  while ($d1 < 350) {
    ok($im->arc(x => 198, y => 202, r => $r, d1 => $d1, d2 => $d1+300, filled => 0),
       "draw arc outline r$r d1$d1 len 300");
    ok($im->arc(x => 198, y => 202, r => $r+3, d1 => $d1, d2 => $d1+40, filled => 0, color => '#FFFF00'),
       "draw arc outline r$r d1$d1 len 40");
    $d1 += 15;
    $r += 6;
  }
  is_color3($im->getpixel(x => 198, y => 202), 0, 0, 0,
	    "check center not filled");
  ok($im->write(file => "testout/t21arcout.ppm"),
     "save arc outline");
}

{
  my $im = Imager->new(xsize => 400, ysize => 400);
  ok($im->arc(x => 197, y => 201, r => 10, filled => 0, aa => 1, color => 'white'),
     "draw circle outline");
  is_color3($im->getpixel(x => 197, y => 201), 0, 0, 0,
	    "check center not filled");
  ok($im->arc(x => 197, y => 205, r => 13, filled => 0, color => "#f88", aa => 1),
     "draw circle outline");
  is_color3($im->getpixel(x => 197, y => 205), 0, 0, 0,
	    "check center not filled");
  ok($im->arc(x => 190, y => 215, r => 24, filled => 0, color => [0,0, 255, 128], aa => 1),
     "draw circle outline");
  my $r = 40;
  while ($r < 190) {
    ok($im->arc(x => 197, y => 201, r => $r, filled => 0, aa => 1, color => '#ff0'), "draw aa circle rad $r");
    $r += 7;
  }
  ok($im->write(file => "testout/t21aacircout.ppm"),
     "save arc outline");
}

{
  my $im = Imager->new(xsize => 400, ysize => 400);
  {
    my $lc = Imager::Color->new(32, 32, 32);
    my $an = 0;
    while ($an < 360) {
      my $an_r = $an * PI / 180;
      my $ca = cos($an_r);
      my $sa = sin($an_r);
      $im->line(aa => 1, color => $lc,
		x1 => 198 + 5 * $ca, y1 => 202 + 5 * $sa,
		x2 => 198 + 190 * $ca, y2 => 202 + 190 * $sa);
      $an += 5;
    }
  }
  my $d1 = 0;
  my $r = 20;
  while ($d1 < 350) {
    ok($im->arc(x => 198, y => 202, r => $r, d1 => $d1, d2 => $d1+300, filled => 0, aa => 1),
       "draw aa arc outline r$r d1$d1 len 300");
    ok($im->arc(x => 198, y => 202, r => $r+3, d1 => $d1, d2 => $d1+40, filled => 0, color => '#FFFF00', aa => 1),
       "draw aa arc outline r$r d1$d1 len 40");
    $d1 += 15;
    $r += 6;
  }
  is_color3($im->getpixel(x => 198, y => 202), 0, 0, 0,
	    "check center not filled");
  ok($im->write(file => "testout/t21aaarcout.ppm"),
     "save arc outline");
}

{
  my $im = Imager->new(xsize => 400, ysize => 400);

  my $an = 0;
  my $step = 15;
  while ($an <= 360-$step) {
    my $cx = int(200 + 20 * cos(($an+$step/2) * PI / 180));
    my $cy = int(200 + 20 * sin(($an+$step/2) * PI / 180));

    ok($im->arc(x => $cx, y => $cy, aa => 1, color => "#fff", 
		d1 => $an, d2 => $an+$step, filled => 0, r => 170),
      "angle starting from $an");
    ok($im->arc(x => $cx+0.5, y => $cy+0.5, aa => 1, color => "#ff0", 
		d1 => $an, d2 => $an+$step, r => 168),
      "filled angle starting from $an");

    $an += $step;
  }
  ok($im->write(file => "testout/t21aaarcs.ppm"),
     "save arc outline");
}

{
  # we document that drawing from d1 to d2 where d2 > d1 will draw an
  # arc going through 360 degrees, test that
  my $im = Imager->new(xsize => 200, ysize => 200);
  ok($im->arc(x => 100, y => 100, aa => 0, filled => 0, color => '#fff',
	      d1 => 270, d2 => 90, r => 90), "draw non-aa arc through 0");
  ok($im->arc(x => 100, y => 100, aa => 1, filled => 0, color => '#fff',
	      d1 => 270, d2 => 90, r => 80), "draw aa arc through 0");
  ok($im->write(file => "testout/t21arc0.ppm"),
     "save arc through 0");
}

{
  # test drawing color defaults
  {
    my $im = Imager->new(xsize => 10, ysize => 10);
    ok($im->box(), "default outline the image"); # should outline the image
    is_color3($im->getpixel(x => 0, y => 0), 255, 255, 255,
	      "check outline default color TL");
    is_color3($im->getpixel(x => 9, y => 5), 255, 255, 255,
	      "check outline default color MR");
  }

  {
    my $im = Imager->new(xsize => 10, ysize => 10);
    ok($im->box(filled => 1), "default fill the image"); # should fill the image
    is_color3($im->getpixel(x => 0, y => 0), 255, 255, 255,
	      "check fill default color TL");
    is_color3($im->getpixel(x => 5, y => 5), 255, 255, 255,
	      "check fill default color MM");
  }
}

{
  my $empty = Imager->new;
  ok(!$empty->box(), "can't draw box to empty image");
  is($empty->errstr, "box: empty input image", "check error message");
  ok(!$empty->arc(), "can't draw arc to empty image");
  is($empty->errstr, "arc: empty input image", "check error message");
  ok(!$empty->line(x1 => 0, y1 => 0, x2 => 10, y2 => 0),
     "can't draw line to empty image");
  is($empty->errstr, "line: empty input image", "check error message");
  ok(!$empty->polyline(points => [ [ 0, 0 ], [ 10, 0 ] ]),
     "can't draw polyline to empty image");
  is($empty->errstr, "polyline: empty input image", "check error message");
  ok(!$empty->polygon(points => [ [ 0, 0 ], [ 10, 0 ], [ 0, 10 ] ]),
     "can't draw polygon to empty image");
  is($empty->errstr, "polygon: empty input image", "check error message");
  ok(!$empty->flood_fill(x => 0, y => 0), "can't flood fill to empty image");
  is($empty->errstr, "flood_fill: empty input image", "check error message");
}


malloc_state();

unless ($ENV{IMAGER_KEEP_FILES}) {
  unlink "testout/t21draw.ppm";
  unlink "testout/t21circout.ppm";
  unlink "testout/t21aacircout.ppm";
  unlink "testout/t21arcout.ppm";
  unlink "testout/t21aaarcout.ppm";
  unlink "testout/t21aaarcs.ppm";
  unlink "testout/t21arc0.ppm";
}

sub color_cmp {
  my ($l, $r) = @_;
  my @l = $l->rgba;
  my @r = $r->rgba;
  # print "# (",join(",", @l[0..2]),") <=> (",join(",", @r[0..2]),")\n";
  return $l[0] <=> $r[0]
    || $l[1] <=> $r[1]
      || $l[2] <=> $r[2];
}

sub angle_marker {
  my ($img, $x, $y, $radius, @angles) = @_;

  for my $angle (@angles) {
    my $x1 = int($x + $radius * cos($angle * PI / 180) + 0.5);
    my $y1 = int($y + $radius * sin($angle * PI / 180) + 0.5);
    my $x2 = int($x + (5+$radius) * cos($angle * PI / 180) + 0.5);
    my $y2 = int($y + (5+$radius) * sin($angle * PI / 180) + 0.5);
    
    $img->line(x1=>$x1, y1=>$y1, x2=>$x2, y2=>$y2, color=>'#FFF');
  }
}
