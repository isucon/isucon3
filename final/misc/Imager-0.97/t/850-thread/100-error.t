#!perl -w
use strict;

# avoiding this prologue would be nice, but it seems to be unavoidable,
# see "It is also important to note ..." in perldoc threads
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

use Imager;

# test that the error contexts are separate under threads

plan tests => 11;

Imager->open_log(log => "testout/t081error.log");

Imager::i_clear_error();
Imager::i_push_error(0, "main thread a");

my @threads;
for my $tid (1..5) {
  my $t1 = threads->create
    (
     sub {
       my $id = shift;
       Imager::i_push_error(0, "$id: child thread a");
       sleep(1+rand(4));
       Imager::i_push_error(1, "$id: child thread b");

       is_deeply([ Imager::i_errors() ],
		 [
		  [ "$id: child thread b", 1 ],
		  [ "$id: child thread a", 0 ],
		 ], "$id: check errors in child");
       1;
     },
     $tid
    );
  push @threads, [ $tid, $t1 ];
}

Imager::i_push_error(1, "main thread b");

for my $thread (@threads) {
  my ($id, $t1) = @$thread;
  ok($t1->join, "join child $id");
}

Imager::i_push_error(2, "main thread c");

is_deeply([ Imager::i_errors() ],
	  [
	   [ "main thread c", 2 ],
	   [ "main thread b", 1 ],
	   [ "main thread a", 0 ],
	  ], "check errors in parent");

