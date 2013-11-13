#!perl -w
use strict;
use Test::More tests => 232;

BEGIN { use_ok(Imager=>':all') }
use Imager::Test qw(is_image is_color4 is_image_similar);

-d "testout" or mkdir "testout";

Imager::init('log'=>'testout/t40scale.log');
my $img=Imager->new();

ok($img->open(file=>'testimg/scale.ppm',type=>'pnm'),
   "load test image") or print "# ",$img->errstr,"\n";

my $scaleimg=$img->scale(scalefactor=>0.25)
  or print "# ",$img->errstr,"\n";
ok($scaleimg, "scale it (good mode)");

ok($scaleimg->write(file=>'testout/t40scale1.ppm',type=>'pnm'),
   "save scaled image") or print "# ",$img->errstr,"\n";

$scaleimg=$img->scale(scalefactor=>0.25,qtype=>'preview');
ok($scaleimg, "scale it (preview)") or print "# ",$img->errstr,"\n";

ok($scaleimg->write(file=>'testout/t40scale2.ppm',type=>'pnm'),
   "write preview scaled image")  or print "# ",$img->errstr,"\n";

$scaleimg = $img->scale(scalefactor => 0.25, qtype => 'mixing');
ok($scaleimg, "scale it (mixing)") or print "# ", $img->errstr, "\n";
ok($scaleimg->write(file=>'testout/t40scale3.ppm', type=>'pnm'),
   "write mixing scaled image") or print "# ", $img->errstr, "\n";

{ # double image scaling with mixing, since it has code to handle it
  my $dimg = Imager->new(xsize => $img->getwidth, ysize => $img->getheight,
                         channels => $img->getchannels,
                         bits => 'double');
  ok($dimg, "create double/sample image");
  $dimg->paste(src => $img);
  $scaleimg = $dimg->scale(scalefactor => 0.25, qtype => 'mixing');
  ok($scaleimg, "scale it (mixing, double)");
  ok($scaleimg->write(file => 'testout/t40mixdbl.ppm', type => 'pnm'),
     "write double/mixing scaled image");
  is($scaleimg->bits, 'double', "got the right image type as output");

  # hscale only, mixing
  $scaleimg = $dimg->scale(xscalefactor => 0.33, yscalefactor => 1.0,
                           qtype => 'mixing');
  ok($scaleimg, "scale it (hscale, mixing, double)");
  is($scaleimg->getheight, $dimg->getheight, "same height");
  ok($scaleimg->write(file => 'testout/t40hscdmix.ppm', type => 'pnm'),
     "save it");

  # vscale only, mixing
  $scaleimg = $dimg->scale(xscalefactor => 1.0, yscalefactor => 0.33,
                           qtype => 'mixing');
  ok($scaleimg, "scale it (vscale, mixing, double)");
  is($scaleimg->getwidth, $dimg->getwidth, "same width");
  ok($scaleimg->write(file => 'testout/t40vscdmix.ppm', type => 'pnm'),
     "save it");
}

{
  # check for a warning when scale() is called in void context
  my $warning;
  local $SIG{__WARN__} = 
    sub { 
      $warning = "@_";
      my $printed = $warning;
      $printed =~ s/\n$//;
      $printed =~ s/\n/\n\#/g; 
      print "# ",$printed, "\n";
    };
  $img->scale(scalefactor=>0.25);
  cmp_ok($warning, '=~', qr/void/, "check warning");
  cmp_ok($warning, '=~', qr/scale\.t/, "check filename");
  $warning = '';
  $img->scaleX(scalefactor=>0.25);
  cmp_ok($warning, '=~', qr/void/, "check warning");
  cmp_ok($warning, '=~', qr/scale\.t/, "check filename");
  $warning = '';
  $img->scaleY(scalefactor=>0.25);
  cmp_ok($warning, '=~', qr/void/, "check warning");
  cmp_ok($warning, '=~', qr/scale\.t/, "check filename");
}
{ # https://rt.cpan.org/Ticket/Display.html?id=7467
  # segfault in Imager 0.43
  # make sure scale() doesn't let us make an image zero pixels high or wide
  # it does this by making the given axis as least 1 pixel high
  my $out = $img->scale(scalefactor=>0.00001);
  is($out->getwidth, 1, "min scale width");
  is($out->getheight, 1, "min scale height");

  $out = $img->scale(scalefactor=>0.00001, qtype => 'preview');
  is($out->getwidth, 1, "min scale width (preview)");
  is($out->getheight, 1, "min scale height (preview)");

  $out = $img->scale(scalefactor=>0.00001, qtype => 'mixing');
  is($out->getwidth, 1, "min scale width (mixing)");
  is($out->getheight, 1, "min scale height (mixing)");
}

{ # error handling - NULL image
  my $im = Imager->new;
  ok(!$im->scale(scalefactor => 0.5), "try to scale empty image");
  is($im->errstr, "scale: empty input image", "check error message");

  # scaleX/scaleY
  ok(!$im->scaleX(scalefactor => 0.5), "try to scaleX empty image");
  is($im->errstr, "scaleX: empty input image", "check error message");
  ok(!$im->scaleY(scalefactor => 0.5), "try to scaleY empty image");
  is($im->errstr, "scaleY: empty input image", "check error message");
}

{ # invalid qtype value
  my $im = Imager->new(xsize => 100, ysize => 100);
  ok(!$im->scale(scalefactor => 0.5, qtype=>'unknown'), "unknown qtype");
  is($im->errstr, "invalid value for qtype parameter", "check error message");
  
  # invalid type value
  ok(!$im->scale(xpixels => 10, ypixels=>50, type=>"unknown"), "unknown type");
  is($im->errstr, "invalid value for type parameter", "check error message");
}

SKIP:
{ # Image::Math::Constrain support
  eval "require Image::Math::Constrain;";
  $@ and skip "optional module Image::Math::Constrain not installed", 3;
  my $constrain = Image::Math::Constrain->new(20, 100);
  my $im = Imager->new(xsize => 160, ysize => 96);
  my $result = $im->scale(constrain => $constrain);
  ok($result, "successful scale with Image::Math::Constrain");
  is($result->getwidth, 20, "check result width");
  is($result->getheight, 12, "check result height");
}

{ # scale size checks
  my $im = Imager->new(xsize => 160, ysize => 96); # some random size

  scale_test($im, 'scale', 80, 48, "48 x 48 def type",
	     xpixels => 48, ypixels => 48);
  scale_test($im, 'scale', 80, 48, "48 x 48 max type",
	     xpixels => 48, ypixels => 48, type => 'max');
  scale_test($im, 'scale', 80, 48, "80 x 80 min type",
	     xpixels => 80, ypixels => 80, type => 'min');
  scale_test($im, 'scale', 80, 48, "no scale parameters (default to 0.5 scalefactor)");
  scale_test($im, 'scale', 120, 72, "0.75 scalefactor",
	     scalefactor => 0.75);
  scale_test($im, 'scale', 80, 48, "80 width",
	     xpixels => 80);
  scale_test($im, 'scale', 120, 72, "72 height",
	     ypixels => 72);

  # new scaling parameters in 0.54
  scale_test($im, 'scale', 80, 48, "xscale 0.5",
	     xscalefactor => 0.5);
  scale_test($im, 'scale', 80, 48, "yscale 0.5",
	     yscalefactor => 0.5);
  scale_test($im, 'scale', 40, 48, "xscale 0.25 yscale 0.5",
	     xscalefactor => 0.25, yscalefactor => 0.5);
  scale_test($im, 'scale', 160, 48, "xscale 1.0 yscale 0.5",
	     xscalefactor => 1.0, yscalefactor => 0.5);
  scale_test($im, 'scale', 160, 48, "xpixels 160 ypixels 48 type nonprop",
	     xpixels => 160, ypixels => 48, type => 'nonprop');
  scale_test($im, 'scale', 160, 96, "xpixels 160 ypixels 96",
	     xpixels => 160, ypixels => 96);
  scale_test($im, 'scale', 80, 96, "xpixels 80 ypixels 96 type nonprop",
	     xpixels => 80, ypixels => 96, type => 'nonprop');

  # scaleX
  scale_test($im, 'scaleX', 80, 96, "defaults");
  scale_test($im, 'scaleX', 40, 96, "0.25 scalefactor",
             scalefactor => 0.25);
  scale_test($im, 'scaleX', 120, 96, "pixels 120",
             pixels => 120);

  # scaleY
  scale_test($im, 'scaleY', 160, 48, "defaults");
  scale_test($im, 'scaleY', 160, 192, "2.0 scalefactor",
             scalefactor => 2.0);
  scale_test($im, 'scaleY', 160, 144, "pixels 144",
             pixels => 144);
}

{ # check proper alpha handling for mixing
  my $im = Imager->new(xsize => 40, ysize => 40, channels => 4);
  $im->box(filled => 1, color => 'C0C0C0');
  my $rot = $im->rotate(degrees => -4)
    or die;
  $rot = $rot->to_rgb16;
  my $sc = $rot->scale(qtype => 'mixing', xpixels => 40);
  my $out = Imager->new(xsize => $sc->getwidth, ysize => $sc->getheight);
  $out->box(filled => 1, color => 'C0C0C0');
  my $cmp = $out->copy;
  $out->rubthrough(src => $sc);
  is_image($out, $cmp, "check we get the right image after scaling (mixing)");

  # we now set alpha=0 pixels to zero on scaling
  is_color4($sc->getpixel('x' => 39, 'y' => 39), 0, 0, 0, 0,
	    "check we set alpha=0 pixels to zero on scaling");
}

{ # check proper alpha handling for default scaling
  my $im = Imager->new(xsize => 40, ysize => 40, channels => 4);
  $im->box(filled => 1, color => 'C0C0C0');
  my $rot = $im->rotate(degrees => -4)
    or die;
  my $sc = $rot->scale(qtype => "normal", xpixels => 40);
  my $out = Imager->new(xsize => $sc->getwidth, ysize => $sc->getheight);
  $out->box(filled => 1, color => 'C0C0C0');
  my $cmp = $out->copy;
  $out->rubthrough(src => $sc);
  is_image_similar($out, $cmp, 100, "check we get the right image after scaling (normal)");

  # we now set alpha=0 pixels to zero on scaling
  is_color4($sc->getpixel('x' => 39, 'y' => 39), 0, 0, 0, 0,
	    "check we set alpha=0 pixels to zero on scaling");
}

{ # scale_calculate
  my $im = Imager->new(xsize => 100, ysize => 120);
  is_deeply([ $im->scale_calculate(scalefactor => 0.5) ],
	    [ 0.5, 0.5, 50, 60 ],
	    "simple scale_calculate");
  is_deeply([ Imager->scale_calculate(scalefactor => 0.5) ],
	    [], "failed scale_calculate");
  is_deeply([ Imager->scale_calculate(width => 120, height => 150,
				      xpixels => 240) ],
	    [ 2.0, 2.0, 240, 300 ],
	    "class method scale_factor");
}

{ # passing a reference for scaling parameters should fail
  # RT #35172
  my $im = Imager->new(xsize => 100, ysize => 100);
  ok(!$im->scale(xpixels => {}), "can't use a reference as a size");
  cmp_ok($im->errstr, '=~', "xpixels parameter cannot be a reference",
	 "check error message");
}

sub scale_test {
  my ($in, $method, $exp_width, $exp_height, $note, @parms) = @_;

  print "# $note: @parms\n";
  for my $qtype (qw(normal preview mixing)) {
  SKIP:
    {
      my $scaled = $in->$method(@parms, qtype => $qtype);
      ok($scaled, "$method $note qtype $qtype")
	or skip("failed to scale", 2);
      is($scaled->getwidth, $exp_width, "check width");
      is($scaled->getheight, $exp_height, "check height");
    }
  }
}
