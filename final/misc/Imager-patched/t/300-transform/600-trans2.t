#!perl -w
use strict;
use Test::More tests => 40;
BEGIN { use_ok('Imager'); }
use Imager::Test qw(is_color3);

-d "testout" or mkdir "testout";

Imager::init('log'=>'testout/t58trans2.log');

my $im1 = Imager->new();
$im1->open(file=>'testimg/penguin-base.ppm', type=>'pnm')
	 || die "Cannot read image";
my $im2 = Imager->new();
$im2->open(file=>'testimg/scale.ppm',type=>'pnm')
	|| die "Cannot read testimg/scale.ppm";

# error handling
my $opts = { rpnexpr=>'x x 10 / sin 10 * y + get1' };
my $im3 = Imager::transform2($opts);
ok(!$im3, "returned an image on error");
ok(defined($Imager::ERRSTR), "No error message on failure");

# image synthesis
my $im4 = Imager::transform2({
	width=>300, height=>300,
	rpnexpr=>'x y cx cy distance !d y cy - x cx - atan2 !a @d 10 / @a + 3.1416 2 * % !a2 @a2 cy * 3.1416 / 1 @a2 sin 1 + 2 / hsv'});
ok($im4, "synthesis failed");

if ($im4) {
  $im4->write(type=>'pnm', file=>'testout/t56a.ppm')
    || die "Cannot write testout/t56a.ppm";
}

# image distortion
my $im5 = Imager::transform2({
	rpnexpr=>'x x 10 / sin 10 * y + getp1'
}, $im1);
ok($im5, "image distortion");
if ($im5) {
  $im5->write(type=>'pnm', file=>'testout/t56b.ppm')
    || die "Cannot write testout/t56b.ppm";
}

# image combination
$opts = {
rpnexpr=>'x h / !rat x w2 % y h2 % getp2 !pat x y getp1 @rat * @pat 1 @rat - * +'
};
my $im6 = Imager::transform2($opts,$im1,$im2);
ok($im6, "image combination");
if ($im6) {
  $im6->write(type=>'pnm', file=>'testout/t56c.ppm')
    || die "Cannot write testout/t56c.ppm";
}

# alpha
$opts = 
  {
   rpnexpr => '0 0 255 x y + w h + 2 - / 255 * rgba',
   channels => 4,
   width => 50,
   height => 50,
  };
my $im8 = Imager::transform2($opts);
ok($im8, "alpha output");
my $c = $im8->getpixel(x=>0, 'y'=>0);
is(($c->rgba)[3], 0, "zero alpha");
$c = $im8->getpixel(x=>49, 'y'=>49);
is(($c->rgba)[3], 255, "max alpha");

$opts = { rpnexpr => 'x 1 + log 50 * y 1 + log 50 * getp1' };
my $im9 = Imager::transform2($opts, $im1);
ok($im9, "log function");
if ($im9) {
  $im9->write(type=>'pnm', file=>'testout/t56-9.ppm');
}

# op tests
sub op_test($$$$$$);
print "# op tests\n";
op_test('7F0000', <<EOS, 0, 127, 0, 'value hsv getp1');
120 1.0
0 0 getp1 value
hsv
EOS
op_test("7F0000", <<EOS, 255, 0, 0, 'hue');
0 0 getp1 hue
1.0 1.0 hsv
EOS
op_test("7F0000", <<EOS, 0, 255, 0, 'sat');
120 0 0 getp1 sat 1.0 hsv
EOS
op_test("4060A0", <<'EOS', 128, 128, 128, "add mult sub rgb red green blue");
0 0 getp1 !p @p red 2 * @p green 32 + @p blue 32 - rgb
EOS
op_test('806040', <<'EOS', 64, 64, 64, "div uminus");
0 0 getp1 !p @p red 2 / @p green 32 uminus add @p blue rgb
EOS
op_test('40087f', <<'EOS', 8, 64, 31, 'pow mod');
0 0 getp1 !p @p red 0.5 pow @p green 2 pow @p blue 32 mod rgb
EOS
op_test('202122', '0 0 getp1 4 *', 128, 132, 136, 'multp');
op_test('404040', '0 0 getp1 1 2 3 rgb +', 65, 66, 67, 'addp');
op_test('414243', '0 0 getp1 3 2 1 rgb -', 62, 64, 66, 'subp');
op_test('808040', <<'EOS', 64, 64, 8, 'sin cos pi sqrt');
0 0 getp1 !p pi 6 / sin @p red * 0.1 + pi 3 / cos @p green * 0.1 + 
@p blue sqrt rgb
EOS
op_test('008080', <<'EOS', 0, 0, 0, 'atan2');
0 0 0 0 getp1 !p @p red 128 / @p green 128 / atan2 hsv
EOS
op_test('000000', <<'EOS', 150, 150, 150, 'distance');
0 100 120 10 distance !d @d @d @d rgb
EOS
op_test('000000', <<'EOS', 100, 100, 100, 'int');
50.75 int 2 * !i @i @i @i rgb
EOS
op_test('000100', <<'EOS', 128, 0, 0, 'if');
0 0 getp1 !p @p red 0 128 if @p green 0 128 if 0 rgb
EOS
op_test('FF0000', <<'EOS', 0, 255, 0, 'ifp');
0 0 0 getp1 0 255 0 rgb ifp
EOS
op_test('000000', <<'EOS', 1, 0, 1, 'le lt gt');
0 1 le 1 0 lt 1 0 gt rgb
EOS
op_test('000000', <<'EOS', 0, 1, 0, 'ge eq ne');
0 1 ge 0 0 eq 0 0 ne rgb
EOS
op_test('000000', <<'EOS', 0, 1, 1, 'and or not');
1 0 and 1 0 or 0 not rgb
EOS
op_test('000000', <<'EOS', 255, 0, 255, 'abs');
-255 abs 0 abs 255 abs rgb
EOS
op_test('000000', <<'EOS', 50, 82, 0, 'exp log');
1 exp log 50 * 0.5 + 0.5 exp 50 * 0 rgb
EOS
op_test('800000', <<'EOS', 128, 0, 0, 'det');
1 0 0 1 det 128 * 1 1 1 1 det 128 * 0 rgb
EOS
op_test('FF80C0', <<'EOS', 127, 0, 0, 'sat');
0 0 getp1 sat 255 * 0.01 + 0 0 rgb
EOS


{
  my $empty = Imager->new;
  my $good = Imager->new(xsize => 1, ysize => 1);
  ok(!Imager::transform2({ rpnexpr => "x y getp1" }, $good, $empty),
     "can't transform an empty image");
  is(Imager->errstr, "transform2: empty input image (input image 2)",
     "check error message");
}

use Imager::Transform;

# some simple tests
print "# Imager::Transform\n";
my @funcs = Imager::Transform->list;
ok(@funcs, "funcs");

my $tran = Imager::Transform->new($funcs[0]);
ok($tran, "got tranform");
ok($tran->describe() eq Imager::Transform->describe($funcs[0]),
   "description");
# look for a function that takes inputs (at least one does)
my @needsinputs = grep Imager::Transform->new($_)->inputs, @funcs;
# make sure they're 
my @inputs = Imager::Transform->new($needsinputs[0])->inputs;
ok($inputs[0]{desc}, "input description");
# at some point I might want to test the actual transformations

# check lower level error handling
my $im7 = Imager::transform2({rpnexpr=>'x y getp2', width=>100, height=>100});
ok(!$im7, "expected failure on accessing invalid image");
print "# ", Imager->errstr, "\n";
ok(Imager->errstr =~ /not enough images/, "didn't get expected error");

sub op_test ($$$$$$) {
  my ($in_color, $code, $r, $g, $b, $comment) = @_;

  my $im = Imager->new(xsize => 1, ysize => 1);
  $im->setpixel(x => 0, y => 0, color => $in_color);
 SKIP:
  {
    my $out = Imager::transform2({ rpnexpr => $code }, $im);
    unless ($out) {
      fail("$comment: could not compile $code - ".Imager->errstr);
      return;
    }
    my $found = $out->getpixel(x => 0, y => 0);
    is_color3($found, $r, $g, $b, $comment);
  }
}
