#!perl -w
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

use Test::More tests => 70;

use Imager;
use Imager::Test qw(is_fcolor4);

-d "testout" or mkdir "testout";

Imager->open_log(log => "testout/t15color.log");

my $c1 = Imager::Color->new(100, 150, 200, 250);
ok(test_col($c1, 100, 150, 200, 250), 'simple 4-arg');
my $c2 = Imager::Color->new(100, 150, 200);
ok(test_col($c2, 100, 150, 200, 255), 'simple 3-arg');
my $c3 = Imager::Color->new("#6496C8");
ok(test_col($c3, 100, 150, 200, 255), 'web color');
# crashes in Imager-0.38pre8 and earlier
my @foo;
for (1..1000) {
  push(@foo, Imager::Color->new("#FFFFFF"));
}
my $fail;
for (@foo) {
  Imager::Color::set_internal($_, 128, 128, 128, 128) == $_ or ++$fail;
  Imager::Color::set_internal($_, 128, 128, 128, 128) == $_ or ++$fail;
  test_col($_, 128, 128, 128, 128) or ++$fail;
}
ok(!$fail, 'consitency check');

# test the new OO methods
color_ok('r g b',, 100, 150, 200, 255, Imager::Color->new(r=>100, g=>150, b=>200));
color_ok('red green blue', 101, 151, 201, 255, 
         Imager::Color->new(red=>101, green=>151, blue=>201));
color_ok('grey', 102, 255, 255, 255, Imager::Color->new(grey=>102));
color_ok('gray', 103, 255, 255, 255, Imager::Color->new(gray=>103));
SKIP:
{
  skip "no X rgb.txt found", 1 
    unless grep -r, Imager::Color::_test_x_palettes();
  color_ok('xname', 0, 0, 255, 255, Imager::Color->new(xname=>'blue'));
}
color_ok('gimp', 255, 250, 250, 255, 
         Imager::Color->new(gimp=>'snow', palette=>'testimg/test_gimp_pal'));
color_ok('h s v', 255, 255, 255, 255, Imager::Color->new(h=>0, 's'=>0, 'v'=>1.0));
color_ok('h s v again', 255, 0, 0, 255, Imager::Color->new(h=>0, 's'=>1, v=>1));
color_ok('web 6 digit', 128, 129, 130, 255, Imager::Color->new(web=>'#808182'));
color_ok('web 3 digit', 0x11, 0x22, 0x33, 255, Imager::Color->new(web=>'#123'));
color_ok('rgb arrayref', 255, 150, 121, 255, Imager::Color->new(rgb=>[ 255, 150, 121 ]));
color_ok('rgba arrayref', 255, 150, 121, 128, 
         Imager::Color->new(rgba=>[ 255, 150, 121, 128 ]));
color_ok('hsv arrayref', 255, 0, 0, 255, Imager::Color->new(hsv=>[ 0, 1, 1 ]));
color_ok('channel0-3', 129, 130, 131, 134, 
         Imager::Color->new(channel0=>129, channel1=>130, channel2=>131,
                            channel3=>134));
color_ok('c0-3', 129, 130, 131, 134, 
         Imager::Color->new(c0=>129, c1=>130, c2=>131, c3=>134));
color_ok('channels arrayref', 200, 201, 203, 204, 
         Imager::Color->new(channels=>[ 200, 201, 203, 204 ]));
color_ok('name', 255, 250, 250, 255, 
         Imager::Color->new(name=>'snow', palette=>'testimg/test_gimp_pal'));

# test the internal HSV <=> RGB conversions
# these values were generated using the GIMP
# all but hue is 0..360, saturation and value from 0 to 1
# rgb from 0 to 255
my @hsv_vs_rgb =
  (
   { hsv => [ 0, 0.2, 0.1 ], rgb=> [ 25, 20, 20 ] },
   { hsv => [ 0, 0.5, 1.0 ], rgb => [ 255, 127, 127 ] },
   { hsv => [ 100, 0.5, 1.0 ], rgb => [ 170, 255, 127 ] },
   { hsv => [ 100, 1.0, 1.0 ], rgb=> [ 85, 255, 0 ] },
   { hsv => [ 335, 0.5, 0.5 ], rgb=> [127, 63, 90 ] },
  );

use Imager::Color::Float;
my $test_num = 23;
my $index = 0;
for my $entry (@hsv_vs_rgb) {
  print "# color index $index\n";
  my $hsv = $entry->{hsv};
  my $rgb = $entry->{rgb};
  my $fhsvo = Imager::Color::Float->new($hsv->[0]/360.0, $hsv->[1], $hsv->[2]);
  my $fc = Imager::Color::Float::i_hsv_to_rgb($fhsvo);
  fcolor_close_enough("i_hsv_to_rgbf $index", $rgb->[0]/255, $rgb->[1]/255, 
                      $rgb->[2]/255, $fc);
  my $fc2 = Imager::Color::Float::i_rgb_to_hsv($fc);
  fcolor_close_enough("i_rgbf_to_hsv $index", $hsv->[0]/360.0, $hsv->[1], $hsv->[2], 
                      $fc2);

  my $hsvo = Imager::Color->new($hsv->[0]*255/360.0, $hsv->[1] * 255, 
                                $hsv->[2] * 255);
  my $c = Imager::Color::i_hsv_to_rgb($hsvo);
  color_close_enough("i_hsv_to_rgb $index", @$rgb, $c);
  my $c2 = Imager::Color::i_rgb_to_hsv($c);
  color_close_enough_hsv("i_rgb_to_hsv $index", $hsv->[0]*255/360.0, $hsv->[1] * 255, 
                     $hsv->[2] * 255, $c2);
  ++$index;
}

# check the built-ins table
color_ok('builtin black', 0, 0, 0, 255, 
	Imager::Color->new(builtin=>'black'));

{
  my $c1 = Imager::Color->new(255, 255, 255, 0);
  my $c2 = Imager::Color->new(255, 255, 255, 255);
  ok(!$c1->equals(other=>$c2), "not equal no ignore alpha");
  ok(scalar($c1->equals(other=>$c2, ignore_alpha=>1)), 
      "equal with ignore alpha");
  ok($c1->equals(other=>$c1), "equal to itself");
}

{ # http://rt.cpan.org/NoAuth/Bug.html?id=13143
  # Imager::Color->new(color_name) warning if HOME environment variable not set
  local $ENV{HOME};
  my @warnings;
  local $SIG{__WARN__} = sub { push @warnings, "@_" };

  # presumably no-one will name a color like this.
  my $c1 = Imager::Color->new(gimp=>"ABCDEFGHIJKLMNOP");
  is(@warnings, 0, "Should be no warnings")
    or do { print "# $_" for @warnings };
}

{
  # float color from hex triple
  my $f3white = Imager::Color::Float->new("#FFFFFF");
  is_fcolor4($f3white, 1.0, 1.0, 1.0, 1.0, "check color #FFFFFF");
  my $f3black = Imager::Color::Float->new("#000000");
  is_fcolor4($f3black, 0, 0, 0, 1.0, "check color #000000");
  my $f3grey = Imager::Color::Float->new("#808080");
  is_fcolor4($f3grey, 0x80/0xff, 0x80/0xff, 0x80/0xff, 1.0, "check color #808080");

  my $f4white = Imager::Color::Float->new("#FFFFFF80");
  is_fcolor4($f4white, 1.0, 1.0, 1.0, 0x80/0xff, "check color #FFFFFF80");
}

{
  # fail to make a color
  ok(!Imager::Color::Float->new("-unknown-"), "try to make float color -unknown-");
}

{
  # set after creation
  my $c = Imager::Color::Float->new(0, 0, 0);
  is_fcolor4($c, 0, 0, 0, 1.0, "check simple init of float color");
  ok($c->set(1.0, 0.5, 0.25, 1.0), "set() the color");
  is_fcolor4($c, 1.0, 0.5, 0.25, 1.0, "check after set");

  ok(!$c->set("-unknown-"), "set to unknown");
}

{
  # test ->hsv
  my $c = Imager::Color->new(255, 0, 0);
  my($h,$s,$v) = $c->hsv;
  is($h,0,'red hue');
  is($s,1,'red saturation');
  is($v,1,'red value');

  $c = Imager::Color->new(0, 255, 0);
  ($h,$s,$v) = $c->hsv;
  is($h,120,'green hue');
  is($s,1,'green saturation');
  is($v,1,'green value');

  $c = Imager::Color->new(0, 0, 255);
  ($h,$s,$v) = $c->hsv;
  is($h,240,'blue hue');
  is($s,1,'blue saturation');
  is($v,1,'blue value');

  $c = Imager::Color->new(255, 255, 255);
  ($h,$s,$v) = $c->hsv;
  is($h,0,'white hue');
  is($s,0,'white saturation');
  is($v,1,'white value');

  $c = Imager::Color->new(0, 0, 0);
  ($h,$s,$v) = $c->hsv;
  is($h,0,'black hue');
  is($s,0,'black saturation');
  is($v,0,'black value');
}

sub test_col {
  my ($c, $r, $g, $b, $a) = @_;
  unless ($c) {
    print "# $Imager::ERRSTR\n";
    return 0;
  }
  my ($cr, $cg, $cb, $ca) = $c->rgba;
  return $r == $cr && $g == $cg && $b == $cb && $a == $ca;
}

sub color_close_enough {
  my ($name, $r, $g, $b, $c) = @_;

  my ($cr, $cg, $cb) = $c->rgba;
  ok(abs($cr-$r) <= 5 && abs($cg-$g) <= 5 && abs($cb-$b) <= 5,
    "$name - ($cr, $cg, $cb) <=> ($r, $g, $b)");
}

sub color_close_enough_hsv {
  my ($name, $h, $s, $v, $c) = @_;

  my ($ch, $cs, $cv) = $c->rgba;
  if ($ch < 5 && $h > 250) {
    $ch += 255;
  }
  elsif ($ch > 250 && $h < 5) {
    $h += 255;
  }
  ok(abs($ch-$h) <= 5 && abs($cs-$s) <= 5 && abs($cv-$v) <= 5,
    "$name - ($ch, $cs, $cv) <=> ($h, $s, $v)");
}

sub fcolor_close_enough {
  my ($name, $r, $g, $b, $c) = @_;

  my ($cr, $cg, $cb) = $c->rgba;
  ok(abs($cr-$r) <= 0.01 && abs($cg-$g) <= 0.01 && abs($cb-$b) <= 0.01,
    "$name - ($cr, $cg, $cb) <=> ($r, $g, $b)");
}

sub color_ok {
  my ($name, $r, $g, $b, $a, $c) = @_;

  unless (ok(test_col($c, $r, $g, $b, $a), $name)) {
    print "# ($r,$g,$b,$a) != (".join(",", $c ? $c->rgba: ()).")\n";
  }
}

