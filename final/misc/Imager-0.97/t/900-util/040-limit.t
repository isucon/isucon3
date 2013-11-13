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

# test that image file limits are localized to a thread

plan tests => 31;

Imager->open_log(log => "testout/t082limit.log");

ok(Imager->set_file_limits(width => 10, height => 10, bytes => 300),
   "set limits to 10, 10, 300");

ok(Imager->check_file_limits(width => 10, height => 10),
   "successful check limits in parent");

ok(!Imager->check_file_limits(width => 10, height => 10, sample_size => 2),
   "failed check limits in parent");

my @threads;
for my $tid (1..5) {
  my $t1 = threads->create
    (
     sub {
       my $id = shift;
       my $dlimit = $tid * 5;
       my $blimit = $dlimit * $dlimit * 3;
       ok(Imager->set_file_limits(width => $dlimit, height => $dlimit,
				  bytes => $blimit),
	  "$tid: set limits to $dlimit x $dlimit, $blimit bytes");
       ok(Imager->check_file_limits(width => $dlimit, height => $dlimit),
	  "$tid: successful check $dlimit x $dlimit");
       ok(!Imager->check_file_limits(width => $dlimit, height => $dlimit, sample_size => 2),
	  "$tid: failed check $dlimit x $dlimit, ssize 2");
       is_deeply([ Imager->get_file_limits ], [ $dlimit, $dlimit, $blimit ],
		 "check limits are still $dlimit x $dlimit , $blimit bytes");
     },
     $tid
    );
  push @threads, [ $tid, $t1 ];
}

for my $thread (@threads) {
  my ($id, $t1) = @$thread;
  ok($t1->join, "join child $id");
}

ok(Imager->check_file_limits(width => 10, height => 10),
   "test we still pass");
ok(!Imager->check_file_limits(width => 10, height => 10, sample_size => 2),
   "test we still fail");
is_deeply([ Imager->get_file_limits ], [ 10, 10, 300 ],
	  "check original main thread limits still set");
