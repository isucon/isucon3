#!perl -w
use strict;
use Imager;

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
  or plan skip_all => "can't test Imager's lack of threads support with no threads";
$] > 5.008007
  or plan skip_all => "require a perl with CLONE_SKIP to test Imager's lack of threads support";
$loaded_threads
  or plan skip_all => "couldn't load threads";

$INC{"Devel/Cover.pm"}
  and plan skip_all => "threads and Devel::Cover don't get along";

# https://rt.cpan.org/Ticket/Display.html?id=65812
# https://github.com/schwern/test-more/issues/labels/Test-Builder2#issue/100
$Test::More::VERSION =~ /^2\.00_/
  and plan skip_all => "threads are hosed in 2.00_06 and presumably all 2.00_*";

plan tests => 8;

Imager->open_log(log => "testout/t20thread.log");

my $ft1 = Imager::Font->new(file => "fontfiles/dodge.ttf", type => "ft2");
ok($ft1, "make a font");
ok($ft1->_valid, "and it's valid");
my $ft2;

my $thr = threads->create
  (
   sub {
     ok(!$ft1->_valid, "first font no longer valid");
     $ft2 = Imager::Font->new(file => "fontfiles/dodge.ttf", type => "ft2");
     ok($ft2, "make a new font in thread");
     ok($ft2->_valid, "and it's valid");
     1;
   },
  );

ok($thr->join, "join the thread");
ok($ft1->_valid, "original font still valid in main thread");
is($ft2, undef, "font created in thread shouldn't be set in main thread");

Imager->close_log();
