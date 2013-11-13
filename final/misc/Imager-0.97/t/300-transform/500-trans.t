#!perl -w
use strict;
use Test::More;
use Imager;

eval "use Affix::Infix2Postfix; 1;"
  or plan skip_all => "No Affix::Infix2Postfix";

plan tests => 8;

#$Imager::DEBUG=1;

-d "testout" or mkdir "testout";

Imager->open_log('log'=>'testout/t55trans.log');

my $img=Imager->new();

SKIP:
{
  ok($img, "make image object")
    or skip("can't make image object", 5);

  ok($img->open(file=>'testimg/scale.ppm',type=>'pnm'),
     "read sample image")
    or skip("couldn't load test image", 4);

 SKIP:
  {
    my $nimg=$img->transform(xexpr=>'x',yexpr=>'y+10*sin((x+y)/10)');
    ok($nimg, "do transformation")
      or skip ( "warning ".$img->errstr, 1 );

    #	xopcodes=>[qw( x y Add)],yopcodes=>[qw( x y Sub)],parm=>[]

    ok($nimg->write(type=>'pnm',file=>'testout/t55.ppm'), "save to file");
  }

 SKIP:
  {
    my $nimg=$img->transform(xexpr=>'x+0.1*y+5*sin(y/10.0+1.57)',
			     yexpr=>'y+10*sin((x+y-0.785)/10)');
    ok($nimg, "more complex transform")
      or skip("couldn't make image", 1);

    ok($nimg->write(type=>'pnm',file=>'testout/t55b.ppm'), "save to file");
  }
}

{
  my $empty = Imager->new;
  ok(!$empty->transform(xexpr => "x", yexpr => "y"),
     "fail to transform an empty image");
  is($empty->errstr, "transform: empty input image",
     "check error message");
}
