#!perl -w
use strict;
use Imager qw(:handy);
use Test::More tests => 122;

-d "testout" or mkdir "testout";

Imager::init_log("testout/t61filters.log", 1);
use Imager::Test qw(is_image_similar test_image is_image is_color4 is_fcolor4);
# meant for testing the filters themselves

my $imbase = test_image();

my $im_other = Imager->new(xsize=>150, ysize=>150);
$im_other->box(xmin=>30, ymin=>60, xmax=>120, ymax=>90, filled=>1);

test($imbase, {type=>'autolevels'}, 'testout/t61_autolev.ppm');

test($imbase, {type=>'contrast', intensity=>0.5}, 
     'testout/t61_contrast.ppm');

# this one's kind of cool
test($imbase, {type=>'conv', coef=>[ 0.3, 1, 0.3, ], },
     'testout/t61_conv_blur.ppm');

{
  my $work = $imbase->copy;
  ok(!Imager::i_conv($work->{IMG}, []), "conv should fail with empty array");
  ok(!$work->filter(type => 'conv', coef => []),
     "check the conv OO intergave too");
  is($work->errstr, "there must be at least one coefficient",
     "check conv error message");
}

{
  my $work8 = $imbase->copy;
  ok(!$work8->filter(type => "conv", coef => "ABC"),
     "coef not an array");
}
{
  my $work8 = $imbase->copy;
  ok(!$work8->filter(type => "conv", coef => [ -1, 2, -1 ]),
     "should fail if sum of coef is 0");
  is($work8->errstr, "sum of coefficients is zero", "check message");
}

{
  my $work8 = $imbase->copy;
  my $work16 = $imbase->to_rgb16;
  my $coef = [ -0.2, 1, -0.2 ];
  ok($work8->filter(type => "conv", coef => $coef),
     "filter 8 bit image");
  ok($work16->filter(type => "conv", , coef => $coef),
     "filter 16 bit image");
  is_image_similar($work8, $work16, 80000, "8 and 16 bit conv match");
}

{
  my $gauss = test($imbase, {type=>'gaussian', stddev=>5 },
		   'testout/t61_gaussian.ppm');

  my $imbase16 = $imbase->to_rgb16;
  my $gauss16 = test($imbase16,  {type=>'gaussian', stddev=>5 },
		     'testout/t61_gaussian16.ppm');
  is_image_similar($gauss, $gauss16, 250000, "8 and 16 gaussian match");
}


test($imbase, { type=>'gradgen', dist=>1,
                   xo=>[ 10,  10, 120 ],
                   yo=>[ 10, 140,  60 ],
                   colors=> [ NC('#FF0000'), NC('#FFFF00'), NC('#00FFFF') ]},
     'testout/t61_gradgen.ppm');

test($imbase, {type=>'mosaic', size=>8}, 'testout/t61_mosaic.ppm');

test($imbase, {type=>'hardinvert'}, 'testout/t61_hardinvert.ppm');

{ # invert - 8 bit
  my $im = Imager->new(xsize => 1, ysize => 1, channels => 4);
  ok($im, "make test image for invert test");
  ok($im->setpixel(x => 0, y => 0, color => "000010C0"),
     "set a test pixel");
  my $copy = $im->copy;
  ok($im->filter(type => "hardinvert"), "hardinvert it");
  is_color4($im->getpixel(x => 0, y => 0), 255, 255, 0xEF, 0xC0,
	    "check only colour inverted");
  ok($copy->filter(type => "hardinvertall"), "hardinvertall copy");
  is_color4($copy->getpixel(x => 0, y => 0), 255, 255, 0xEF, 0x3f,
	    "check all inverted");
}

{ # invert - double image
  my $im = Imager->new(xsize => 1, ysize => 1, channels => 4, bits => "double");
  ok($im, "make double test image for invert test");
  ok($im->setpixel(x => 0, y => 0, color => Imager::Color::Float->new(0, 0, 0.125, 0.75)),
     "set a test pixel");
  my $copy = $im->copy;
  ok($im->filter(type => "hardinvert"), "hardinvert it");
  is_fcolor4($im->getpixel(x => 0, y => 0, type => "double"),
	     1.0, 1.0, 0.875, 0.75, 1e-5,
	     "check only colour inverted");
  ok($copy->filter(type => "hardinvertall"), "hardinvertall copy");
  is_fcolor4($copy->getpixel(x => 0, y => 0, type =>"double"),
	     1.0, 1.0, 0.875, 0.25, 1e-5,
	     "check all inverted");
}

test($imbase, {type=>'noise'}, 'testout/t61_noise.ppm');

test($imbase, {type=>'radnoise'}, 'testout/t61_radnoise.ppm');

test($imbase, {type=>'turbnoise'}, 'testout/t61_turbnoise.ppm');

test($imbase, {type=>'bumpmap', bump=>$im_other, lightx=>30, lighty=>30},
     'testout/t61_bumpmap.ppm');

test($imbase, {type=>'bumpmap_complex', bump=>$im_other}, 'testout/t61_bumpmap_complex.ppm');

test($imbase, {type=>'postlevels', levels=>3}, 'testout/t61_postlevels.ppm');

test($imbase, {type=>'watermark', wmark=>$im_other },
     'testout/t61_watermark.ppm');

test($imbase, {type=>'fountain', xa=>75, ya=>75, xb=>85, yb=>30,
               repeat=>'triangle', #ftype=>'radial', 
               super_sample=>'circle', ssample_param => 16,
              },
     'testout/t61_fountain.ppm');
use Imager::Fountain;

my $f1 = Imager::Fountain->new;
$f1->add(end=>0.2, c0=>NC(255, 0,0), c1=>NC(255, 255,0));
$f1->add(start=>0.2, c0=>NC(255,255,0), c1=>NC(0,0,255,0));
test($imbase, { type=>'fountain', xa=>20, ya=>130, xb=>130, yb=>20,
                #repeat=>'triangle',
                segments=>$f1
              },
     'testout/t61_fountain2.ppm');
my $f2 = Imager::Fountain->new
  ->add(end=>0.5, c0=>NC(255,0,0), c1=>NC(255,0,0), color=>'hueup')
  ->add(start=>0.5, c0=>NC(255,0,0), c1=>NC(255,0,0), color=>'huedown');
#use Data::Dumper;
#print Dumper($f2);
test($imbase, { type=>'fountain', xa=>20, ya=>130, xb=>130, yb=>20,
                    segments=>$f2 },
     'testout/t61_fount_hsv.ppm');
my $f3 = Imager::Fountain->read(gimp=>'testimg/gimpgrad');
ok($f3, "read gimpgrad");
test($imbase, { type=>'fountain', xa=>75, ya=>75, xb=>90, yb=>15,
                    segments=>$f3, super_sample=>'grid',
                    ftype=>'radial_square', combine=>'color' },
     'testout/t61_fount_gimp.ppm');
{ # test new fountain with no parameters
  my $warn = '';
  local $SIG{__WARN__} = sub { $warn .= "@_" };
  my $f4 = Imager::Fountain->read();
  ok(!$f4, "read with no parameters does nothing");
  like($warn, qr/Nothing to do!/, "check the warning");
}
{ # test with missing file
  my $warn = '';
  local $SIG{__WARN__} = sub { $warn .= "@_" };
  my $f = Imager::Fountain->read(gimp => "no-such-file");
  ok(!$f, "try to read a fountain defintion that doesn't exist");
  is($warn, "", "should be no warning");
  like(Imager->errstr, qr/^Cannot open no-such-file: /, "check message");
}
SKIP:
{
  my $fh = IO::File->new("testimg/gimpgrad", "r");
  ok($fh, "opened gradient")
    or skip "Couldn't open gradient: $!", 1;
  my $f = Imager::Fountain->read(gimp => $fh);
  ok($f, "read gradient from file handle");
}
{
  # not a gradient
  my $f = Imager::Fountain->read(gimp => "t/400-filter/010-filters.t");
  ok(!$f, "fail to read non-gradient");
  is(Imager->errstr, "t/400-filter/010-filters.t is not a GIMP gradient file",
     "check error message");
}
{ # an invalid gradient file
  my $f = Imager::Fountain->read(gimp => "testimg/gradbad.ggr");
  ok(!$f, "fail to read bad gradient (bad seg count)");
  is(Imager->errstr, "testimg/gradbad.ggr is missing the segment count",
     "check error message");
}
{ # an invalid gradient file
  my $f = Imager::Fountain->read(gimp => "testimg/gradbad2.ggr");
  ok(!$f, "fail to read bad gradient (bad segment)");
  is(Imager->errstr, "Bad segment definition",
     "check error message");
}
test($imbase, { type=>'unsharpmask', stddev=>2.0 },
     'testout/t61_unsharp.ppm');
test($imbase, {type=>'conv', coef=>[ -1, 3, -1, ], },
     'testout/t61_conv_sharp.ppm');

test($imbase, { type=>'nearest_color', dist=>1,
                   xo=>[ 10,  10, 120 ],
                   yo=>[ 10, 140,  60 ],
                   colors=> [ NC('#FF0000'), NC('#FFFF00'), NC('#00FFFF') ]},
     'testout/t61_nearest.ppm');

# Regression test: the checking of the segment type was incorrect
# (the comparison was checking the wrong variable against the wrong value)
my $f4 = [ [ 0, 0.5, 1, NC(0,0,0), NC(255,255,255), 5, 0 ] ];
test($imbase, {type=>'fountain',  xa=>75, ya=>75, xb=>90, yb=>15,
               segments=>$f4, super_sample=>'grid',
               ftype=>'linear', combine=>'color' },
     'testout/t61_regress_fount.ppm');
my $im2 = $imbase->copy;
$im2->box(xmin=>20, ymin=>20, xmax=>40, ymax=>40, color=>'FF0000', filled=>1);
$im2->write(file=>'testout/t61_diff_base.ppm');
my $im3 = Imager->new(xsize=>150, ysize=>150, channels=>3);
$im3->box(xmin=>20, ymin=>20, xmax=>40, ymax=>40, color=>'FF0000', filled=>1);
my $diff = $imbase->difference(other=>$im2);
ok($diff, "got difference image");
SKIP:
{
  skip(1, "missing comp or diff image") unless $im3 && $diff;

  is(Imager::i_img_diff($im3->{IMG}, $diff->{IMG}), 0,
     "compare test image and diff image");
}

# newer versions of gimp add a line to the gradient file
my $name;
my $f5 = Imager::Fountain->read(gimp=>'testimg/newgimpgrad.ggr',
                                name => \$name);
ok($f5, "read newer gimp gradient")
  or print "# ",Imager->errstr,"\n";
is($name, "imager test gradient", "check name read correctly");
$f5 = Imager::Fountain->read(gimp=>'testimg/newgimpgrad.ggr');
ok($f5, "check we handle case of no name reference correctly")
  or print "# ",Imager->errstr,"\n";

# test writing of gradients
ok($f2->write(gimp=>'testout/t61grad1.ggr'), "save a gradient")
  or print "# ",Imager->errstr,"\n";
undef $name;
my $f6 = Imager::Fountain->read(gimp=>'testout/t61grad1.ggr', 
                                name=>\$name);
ok($f6, "read what we wrote")
  or print "# ",Imager->errstr,"\n";
ok(!defined $name, "we didn't set the name, so shouldn't get one");

# try with a name
ok($f2->write(gimp=>'testout/t61grad2.ggr', name=>'test gradient'),
   "write gradient with a name")
  or print "# ",Imager->errstr,"\n";
undef $name;
my $f7 = Imager::Fountain->read(gimp=>'testout/t61grad2.ggr', name=>\$name);
ok($f7, "read what we wrote")
  or print "# ",Imager->errstr,"\n";
is($name, "test gradient", "check the name matches");

# we attempt to convert color names in segments to segments now
{
  my @segs =
    (
     [ 0.0, 0.5, 1.0, '000000', '#FFF', 0, 0 ],
    );
  my $im = Imager->new(xsize=>50, ysize=>50);
  ok($im->filter(type=>'fountain', segments => \@segs,
                 xa=>0, ya=>30, xb=>49, yb=>30), 
     "fountain with color names instead of objects in segments");
  my $left = $im->getpixel('x'=>0, 'y'=>20);
  ok(color_close($left, Imager::Color->new(0,0,0)),
     "check black converted correctly");
  my $right = $im->getpixel('x'=>49, 'y'=>20);
  ok(color_close($right, Imager::Color->new(255,255,255)),
     "check white converted correctly");

  # check that invalid color names are handled correctly
  my @segs2 =
    (
     [ 0.0, 0.5, 1.0, '000000', 'FxFxFx', 0, 0 ],
    );
  ok(!$im->filter(type=>'fountain', segments => \@segs2,
                  xa=>0, ya=>30, xb=>49, yb=>30), 
     "fountain with invalid color name");
  cmp_ok($im->errstr, '=~', 'No color named', "check error message");
}

{
  # test simple gradient creation
  my @colors = map Imager::Color->new($_), qw/white blue red/;
  my $s = Imager::Fountain->simple(positions => [ 0, 0.3, 1.0 ],
				   colors => \@colors);
  ok($s, "made simple gradient");
  my $start = $s->[0];
  is($start->[0], 0, "check start of first correct");
  is_color4($start->[3], 255, 255, 255, 255, "check color at start");
}
{
  # simple gradient error modes
  {
    my $warn = '';
    local $SIG{__WARN__} = sub { $warn .= "@_" };
    my $s = Imager::Fountain->simple();
    ok(!$s, "no parameters to simple()");
    like($warn, qr/Nothing to do/);
  }
  {
    my $s = Imager::Fountain->simple(positions => [ 0, 1 ],
				     colors => [ NC(0, 0, 0) ]);
    ok(!$s, "mismatch of positions and colors fails");
    is(Imager->errstr, "positions and colors must be the same size",
       "check message");
  }
  {
    my $s = Imager::Fountain->simple(positions => [ 0 ],
				     colors => [ NC(0, 0, 0) ]);
    ok(!$s, "not enough positions");
    is(Imager->errstr, "not enough segments");
  }
}

{
  my $im = Imager->new(xsize=>100, ysize=>100);
  # build the gradient the hard way - linear from black to white,
  # then back again
  my @simple =
   (
     [   0, 0.25, 0.5, 'black', 'white', 0, 0 ],
     [ 0.5. 0.75, 1.0, 'white', 'black', 0, 0 ],
   );
  # across
  my $linear = $im->filter(type   => "fountain",
                           ftype  => 'linear',
                           repeat => 'sawtooth',
                           xa     => 0,
                           ya     => $im->getheight / 2,
                           xb     => $im->getwidth - 1,
                           yb     => $im->getheight / 2);
  ok($linear, "linear fountain sample");
  # around
  my $revolution = $im->filter(type   => "fountain",
                               ftype  => 'revolution',
                               xa     => $im->getwidth / 2,
                               ya     => $im->getheight / 2,
                               xb     => $im->getwidth / 2,
                               yb     => 0);
  ok($revolution, "revolution fountain sample");
  # out from the middle
  my $radial = $im->filter(type   => "fountain",
                           ftype  => 'radial',
                           xa     => $im->getwidth / 2,
                           ya     => $im->getheight / 2,
                           xb     => $im->getwidth / 2,
                           yb     => 0);
  ok($radial, "radial fountain sample");
}

{
  # try a simple custom filter that uses the Perl image interface
  sub perl_filt {
    my %args = @_;

    my $im = $args{imager};

    my $channels = $args{channels};
    unless (@$channels) {
      $channels = [ reverse(0 .. $im->getchannels-1) ];
    }
    my @chans = @$channels;
    push @chans, 0 while @chans < 4;

    for my $y (0 .. $im->getheight-1) {
      my $row = $im->getsamples(y => $y, channels => \@chans);
      $im->setscanline(y => $y, pixels => $row);
    }
  }
  Imager->register_filter(type => 'perl_test',
                          callsub => \&perl_filt,
                          defaults => { channels => [] },
                          callseq => [ qw/imager channels/ ]);
  test($imbase, { type => 'perl_test' }, 'testout/t61perl.ppm');
}

{ # check the difference method out
  my $im1 = Imager->new(xsize => 3, ysize => 2);
  $im1->box(filled => 1, color => '#FF0000');
  my $im2 = $im1->copy;
  $im1->setpixel(x => 1, 'y' => 0, color => '#FF00FF');
  $im2->setpixel(x => 1, 'y' => 0, color => '#FF01FF');
  $im1->setpixel(x => 2, 'y' => 0, color => '#FF00FF');
  $im2->setpixel(x => 2, 'y' => 0, color => '#FF02FF');

  my $diff1 = $im1->difference(other => $im2);
  my $cmp1 = Imager->new(xsize => 3, ysize => 2, channels => 4);
  $cmp1->setpixel(x => 1, 'y' => 0, color => '#FF01FF');
  $cmp1->setpixel(x => 2, 'y' => 0, color => '#FF02FF');
  is_image($diff1, $cmp1, "difference() - check image with mindist 0");

  my $diff2 = $im1->difference(other => $im2, mindist => 1);
  my $cmp2 = Imager->new(xsize => 3, ysize => 2, channels => 4);
  $cmp2->setpixel(x => 2, 'y' => 0, color => '#FF02FF');
  is_image($diff2, $cmp2, "difference() - check image with mindist 1");
}

{
  # and again with large samples
  my $im1 = Imager->new(xsize => 3, ysize => 2, bits => 'double');
  $im1->box(filled => 1, color => '#FF0000');
  my $im2 = $im1->copy;
  $im1->setpixel(x => 1, 'y' => 0, color => '#FF00FF');
  $im2->setpixel(x => 1, 'y' => 0, color => '#FF01FF');
  $im1->setpixel(x => 2, 'y' => 0, color => '#FF00FF');
  $im2->setpixel(x => 2, 'y' => 0, color => '#FF02FF');

  my $diff1 = $im1->difference(other => $im2);
  my $cmp1 = Imager->new(xsize => 3, ysize => 2, channels => 4);
  $cmp1->setpixel(x => 1, 'y' => 0, color => '#FF01FF');
  $cmp1->setpixel(x => 2, 'y' => 0, color => '#FF02FF');
  is_image($diff1, $cmp1, "difference() - check image with mindist 0 - large samples");

  my $diff2 = $im1->difference(other => $im2, mindist => 1.1);
  my $cmp2 = Imager->new(xsize => 3, ysize => 2, channels => 4);
  $cmp2->setpixel(x => 2, 'y' => 0, color => '#FF02FF');
  is_image($diff2, $cmp2, "difference() - check image with mindist 1.1 - large samples");
}

{
  my $empty = Imager->new;
  ok(!$empty->filter(type => "hardinvert"), "can't filter an empty image");
  is($empty->errstr, "filter: empty input image",
     "check error message");
  ok(!$empty->difference(other => $imbase), "can't difference empty image");
  is($empty->errstr, "difference: empty input image",
     "check error message");
  ok(!$imbase->difference(other => $empty),
     "can't difference against empty image");
  is($imbase->errstr, "difference: empty input image (other image)",
     "check error message");
}

sub test {
  my ($in, $params, $out) = @_;

  my $copy = $in->copy;
  if (ok($copy->filter(%$params), $params->{type})) {
    ok($copy->write(file=>$out), "write $params->{type}") 
      or print "# ",$copy->errstr,"\n";
  }
  else {
    diag($copy->errstr);
  SKIP: 
    {
      skip("couldn't filter", 1);
    }
  }
  $copy;
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
