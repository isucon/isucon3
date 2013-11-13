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

-d "testout" or mkdir "testout";

Imager->open_log(log => "testout/t080log1.log")
  or plan skip_all => "Cannot open log file: " . Imager->errstr;

plan tests => 3;

Imager->log("main thread a\n");

my $t1 = threads->create
  (
   sub {
     Imager->log("child thread a\n");
     Imager->open_log(log => "testout/t080log2.log")
       or die "Cannot open second log file: ", Imager->errstr;
     Imager->log("child thread b\n");
     sleep(1);
     Imager->log("child thread c\n");
     sleep(1);
     1;
   }
   );

Imager->log("main thread b\n");
sleep(1);
Imager->log("main thread c\n");
ok($t1->join, "join child thread");
Imager->log("main thread d\n");
Imager->close_log();

my %log1 = parse_log("testout/t080log1.log");
my %log2 = parse_log("testout/t080log2.log");

my @log1 =
  (
   "main thread a",
   "main thread b",
   "child thread a",
   "main thread c",
   "main thread d",
  );

my @log2 =
  (
   "child thread b",
   "child thread c",
  );

is_deeply(\%log1, { map {; $_ => 1 } @log1 },
	  "check messages in main thread log");
is_deeply(\%log2, { map {; $_ => 1 } @log2 },
	  "check messages in child thread log");

# grab the messages from the given log
sub parse_log {
  my ($filename) = @_;

  open my $fh, "<", $filename
    or die "Cannot open log file $filename: $!";

  my %lines;
  while (<$fh>) {
    chomp;
    my ($date, $time, $file_line, $level, $message) = split ' ', $_, 5;
    $lines{$message} = 1;
  }

  delete $lines{"Imager - log started (level = 1)"};
  delete $lines{"Imager $Imager::VERSION starting"};

  return %lines;
}

END {
  unlink "testout/t080log1.log", "testout/t080log2.log"
    unless $ENV{IMAGER_KEEP_FILES};
}
