#!perl -w
use strict;
use Test::More tests => 22;

use Imager;

-d "testout" or mkdir "testout";

Imager::init('log'=>'testout/t90cc.log');

{
  my $img=Imager->new();
  ok($img->open(file=>'testimg/scale.ppm'), 'load test image')
    or print "failed: ",$img->{ERRSTR},"\n";
  
  ok(defined($img->getcolorcount(maxcolors=>10000)), 'check color count is small enough');
  print "# color count: ".$img->getcolorcount()."\n";
  is($img->getcolorcount(), 86, 'expected number of colors');
  is($img->getcolorcount(maxcolors => 50), undef, 'check overflow handling');
}

{
  my $black = Imager::Color->new(0, 0, 0);
  my $blue  = Imager::Color->new(0, 0, 255);
  my $red   = Imager::Color->new(255, 0, 0);
  
  my $im    = Imager->new(xsize=>50, ysize=>50);
  
  my $count = $im->getcolorcount();
  is ($count, 1, "getcolorcount is 1");
  my @colour_usage = $im->getcolorusage();
  is_deeply (\@colour_usage, [2500], "2500 are in black");
  
  $im->box(filled=>1, color=>$blue, xmin=>25);
  
  $count = $im->getcolorcount();
  is ($count, 2, "getcolorcount is 2");
  @colour_usage = $im->getcolorusage();
  is_deeply(\@colour_usage, [1250, 1250] , "1250, 1250: Black and blue");
  
  $im->box(filled=>1, color=>$red, ymin=>25);
  
  $count = $im->getcolorcount();
  is ($count, 3, "getcolorcount is 3");
  @colour_usage = $im->getcolorusage();
  is_deeply(\@colour_usage, [625, 625, 1250] , 
	    "625, 625, 1250: Black blue and red");
  @colour_usage = $im->getcolorusage(maxcolors => 2);
  is(@colour_usage, 0, 'test overflow check');
  
  my $colour_usage = $im->getcolorusagehash();
  my $red_pack = pack("CCC", 255, 0, 0);
  my $blue_pack = pack("CCC", 0, 0, 255);
  my $black_pack = pack("CCC", 0, 0, 0);
  is_deeply( $colour_usage, 
	     { $black_pack => 625, $blue_pack => 625, $red_pack => 1250 },
	     "625, 625, 1250: Black blue and red (hash)");
  is($im->getcolorusagehash(maxcolors => 2), undef,
     'test overflow check');

  # test with a greyscale image
  my $im_g = $im->convert(preset => 'grey');
  # since the grey preset scales each source channel differently
  # each of the original colors will be converted to different colors
  is($im_g->getcolorcount, 3, '3 colors (grey)');
  is_deeply([ $im_g->getcolorusage ], [ 625, 625, 1250 ], 
	    'color counts (grey)');
  is_deeply({ "\x00" => 625, "\x12" => 625, "\x38" => 1250 },
	    $im_g->getcolorusagehash,
	    'color usage hash (grey)');
}

{
  my $empty = Imager->new;
  is($empty->getcolorcount, undef, "can't getcolorcount an empty image");
  is($empty->errstr, "getcolorcount: empty input image",
     "check error message");
  is($empty->getcolorusagehash, undef, "can't getcolorusagehash an empty image");
  is($empty->errstr, "getcolorusagehash: empty input image",
     "check error message");
  is($empty->getcolorusage, undef, "can't getcolorusage an empty image");
  is($empty->errstr, "getcolorusage: empty input image",
     "check error message");
}
