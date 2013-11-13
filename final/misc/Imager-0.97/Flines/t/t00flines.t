#!perl -w
use strict;
use blib;
use Imager;
use Test::More tests => 3;

BEGIN { use_ok('Imager::Filter::Flines') }

-d "testout" or mkdir "testout";

Imager->open_log(log => "testout/t00flines.log");

{
  my $im = Imager->new(xsize=>150, ysize=>150);
  
  $im->box(filled=>1, xmin => 70, ymin=>25, xmax =>130, ymax => 125, 
	   color=>'00FF00');
  $im->box(filled=>1, xmin=>20, ymin=>25, xmax=>80, ymax=>125,
	   color => '0000FF');
  $im->arc(x =>75, y=>75, r=>30, color => 'FF0000');
  $im->filter(type=>"conv", coef => [0.1, 0.2, 0.4, 0.2, 0.1]);

  ok($im->filter(type=>'flines'),
     "try filter")
    or print "# ", $im->errstr, "\n";
  ok($im->write(file => 'testout/t00flines.ppm'),
     "save result");
}

END {
  Imager->close_log;

  unless ($ENV{IMAGER_KEEP_FILES}) {
    unlink 'testout/t00flines.ppm';
    unlink "testout/t00flines.log";
    rmdir "testout";
  }
}
