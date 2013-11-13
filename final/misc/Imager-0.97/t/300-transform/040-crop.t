#!perl -w
use strict;
use Test::More tests => 66;
use Imager;
use Imager::Test qw(test_image);

#$Imager::DEBUG=1;

-d "testout" or mkdir "testout";

Imager::init('log'=>'testout/t65crop.log');

my $img=Imager->new() || die "unable to create image object\n";

ok($img, "created image ph");

SKIP:
{
  skip("couldn't load source image", 2)
    unless ok($img->open(file=>'testimg/scale.ppm',type=>'pnm'), "loaded source");
  my $nimg = $img->crop(top=>10, left=>10, bottom=>25, right=>25);
  ok($nimg, "got an image");
  ok($nimg->write(file=>"testout/t65.ppm"), "save to file");
}

{ # https://rt.cpan.org/Ticket/Display.html?id=7578
  # make sure we get the right type of image on crop
  my $src = Imager->new(xsize=>50, ysize=>50, channels=>2, bits=>16);
  is($src->getchannels, 2, "check src channels");
  is($src->bits, 16, "check src bits");
  my $out = $src->crop(left=>10, right=>40, top=>10, bottom=>40);
  is($out->getchannels, 2, "check out channels");
  is($out->bits, 16, "check out bits");
}
{ # https://rt.cpan.org/Ticket/Display.html?id=7578
  print "# try it for paletted too\n";
  my $src = Imager->new(xsize=>50, ysize=>50, channels=>3, type=>'paletted');
  # make sure color index zero is defined so there's something to copy
  $src->addcolors(colors=>[Imager::Color->new(0,0,0)]);
  is($src->type, 'paletted', "check source type");
  my $out = $src->crop(left=>10, right=>40, top=>10, bottom=>40);
  is($out->type, 'paletted', 'check output type');
}

{ # https://rt.cpan.org/Ticket/Display.html?id=7581
  # crop() documentation says width/height takes precedence, but is unclear
  # from looking at the existing code, setting width/height will go from
  # the left of the image, even if left/top are provided, despite the
  # sample in the docs
  # Let's make sure that things happen as documented
  my $src = test_image();
  # make sure we get what we want
  is($src->getwidth, 150, "src width");
  is($src->getheight, 150, "src height");

  # the test data is: 
  #  - description
  #  - hash ref containing args to crop()
  #  - expected left, top, right, bottom values
  # we call crop using the given arguments then call it using the 
  # hopefully stable left/top/right/bottom/arguments
  # this is kind of lame, but I don't want to include a rewritten
  # crop in this file
  my @tests = 
    (
     [ 
      "basic",
      { left=>10, top=>10, right=>70, bottom=>80 },
      10, 10, 70, 80,
     ],
     [
      "middle",
      { width=>50, height=>50 },
      50, 50, 100, 100,
     ],
     [
      "lefttop",
      { left=>20, width=>70, top=>30, height=>90 },
      20, 30, 90, 120,
     ],
     [
      "bottomright",
      { right=>140, width=>50, bottom=>130, height=>60 },
      90, 70, 140, 130,
     ],
     [
      "acrossmiddle",
      { top=>40, bottom=>110 },
      0, 40, 150, 110,
     ],
     [
      "downmiddle",
      { left=>40, right=>110 },
      40, 0, 110, 150,
     ],
     [
      "rightside",
      { left=>80, },
      80, 0, 150, 150,
     ],
     [
      "leftside",
      { right=>40 },
      0, 0, 40, 150,
     ],
     [
      "topside",
      { bottom=>40, },
      0, 0, 150, 40,
     ],
     [
      "bottomside",
      { top=>90 },
      0, 90, 150, 150,
     ],
     [
      "overright",
      { left=>100, right=>200 },
      100, 0, 150, 150,
     ],
     [
      "overtop",
      { bottom=>50, height=>70 },
      0, 0, 150, 50,
     ],
     [
      "overleft",
      { right=>30, width=>60 },
      0, 0, 30, 150,
     ],
     [ 
      "overbottom",
      { top=>120, height=>60 },
      0, 120, 150, 150,
     ],
    );
  for my $test (@tests) {
    my ($desc, $args, $left, $top, $right, $bottom) = @$test;
    my $out = $src->crop(%$args);
    ok($out, "got output for $desc");
    my $cmp = $src->crop(left=>$left, top=>$top, right=>$right, bottom=>$bottom);
    ok($cmp, "got cmp for $desc");
    # make sure they're the same
    my $diff = Imager::i_img_diff($out->{IMG}, $cmp->{IMG});
    is($diff, 0, "difference should be 0 for $desc");
  }
}
{ # https://rt.cpan.org/Ticket/Display.html?id=7581
  # previously we didn't check that the result had some pixels
  # make sure we do
  my $src = test_image();
  ok(!$src->crop(left=>50, right=>50), "nothing across");
  cmp_ok($src->errstr, '=~', qr/resulting image would have no content/,
	 "and message");
  ok(!$src->crop(top=>60, bottom=>60), "nothing down");
  cmp_ok($src->errstr, '=~', qr/resulting image would have no content/,
	 "and message");
}

{ # http://rt.cpan.org/NoAuth/Bug.html?id=9672
  my $warning;
  local $SIG{__WARN__} = 
    sub { 
      $warning = "@_";
      my $printed = $warning;
      $printed =~ s/\n$//;
      $printed =~ s/\n/\n\#/g; 
      print "# ",$printed, "\n";
    };
  my $img = Imager->new(xsize=>10, ysize=>10);
  $img->crop(left=>5);
  cmp_ok($warning, '=~', 'void', "correct warning");
  cmp_ok($warning, '=~', 'crop\\.t', "correct file");
}

{
    my $src = test_image();
    ok(!$src->crop( top=>1000, bottom=>1500, left=>0, right=>100 ),
                "outside of image" );
    cmp_ok($src->errstr, '=~', qr/outside of the image/, "and message");
    ok(!$src->crop( top=>100, bottom=>1500, left=>1000, right=>1500 ),
                "outside of image" );
    cmp_ok($src->errstr, '=~', qr/outside of the image/, "and message");
}

{
  my $empty = Imager->new;
  ok(!$empty->crop(left => 10), "can't crop an empty image");
  is($empty->errstr, "crop: empty input image", "check message");
}
