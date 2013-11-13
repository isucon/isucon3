#!perl
use strict;
use Imager;
use Imager::Color::Float;
use Imager::Fill;
use Config;
my $loaded_threads;
BEGIN {
  if ($Config{useithreads} && $] > 5.008007) {
    $loaded_threads =
      eval {
	require threads;
	threads->import;
	1;
      };
  }
}
use Test::More;

$Config{useithreads}
  or plan skip_all => "can't test Imager's threads support with no threads";
$] > 5.008007
  or plan skip_all => "require a perl with CLONE_SKIP to test Imager's threads support";
$loaded_threads
  or plan skip_all => "couldn't load threads";

$INC{"Devel/Cover.pm"}
  and plan skip_all => "threads and Devel::Cover don't get along";

# https://rt.cpan.org/Ticket/Display.html?id=65812
# https://github.com/schwern/test-more/issues/labels/Test-Builder2#issue/100
$Test::More::VERSION =~ /^2\.00_/
  and plan skip_all => "threads are hosed in 2.00_06 and presumably all 2.00_*";

plan tests => 13;

my $thread = threads->create(sub { 1; });
ok($thread->join, "join first thread");

# these are all, or contain, XS allocated objects, if we don't handle
# CLONE requests, or provide a CLONE_SKIP, we'll probably see a
# double-free, one from the thread, and the other from the main line
# of control.
#
# So make one of each

my $im = Imager->new(xsize => 10, ysize => 10);
my $c = Imager::Color->new(0, 0, 0); # make some sort of color
ok($c, "made the color");
my $cf = Imager::Color::Float->new(0, 0, 0);
ok($cf, "made the float color");
my $hl;
SKIP:
{
  Imager::Internal::Hlines::testing()
      or skip "no hlines visible to test", 1;
  $hl = Imager::Internal::Hlines::new(0, 100, 0, 100);
  ok($hl, "made the hlines");
}
my $io = Imager::io_new_bufchain();
ok($io, "made the io");
my $tt;
SKIP:
{
  $Imager::formats{tt}
    or skip("No TT font support", 1);
  $tt = Imager::Font->new(type => "tt", file => "fontfiles/dodge.ttf");
  ok($tt, "made the font");
}
my $ft2;
SKIP:
{
  $Imager::formats{ft2}
    or skip "No FT2 support", 1;
  $ft2 = Imager::Font->new(type => "ft2", file => "fontfiles/dodge.ttf");
  ok($ft2, "made ft2 font");
}
my $fill = Imager::Fill->new(solid => $c);
ok($fill, "made the fill");

my $t2 = threads->create
  (
   sub {
     ok(!UNIVERSAL::isa($im->{IMG}, "Imager::ImgRaw"),
	"the low level image object should become unblessed");
     ok(!$im->_valid_image, "image no longer considered valid");
     is($im->errstr, "images do not cross threads",
	"check error message");
     1;
   }
  );
ok($t2->join, "join second thread");
#print STDERR $im->{IMG}, "\n";
ok(UNIVERSAL::isa($im->{IMG}, "Imager::ImgRaw"),
   "but the object should be fine in the main thread");

