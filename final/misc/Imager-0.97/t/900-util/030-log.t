#!perl -w
use strict;
use Imager;
use Test::More tests => 6;

my $log_name = "testout/t95log.log";

my $log_message = "test message 12345";

SKIP: {
  skip("Logging not build", 3)
    unless Imager::i_log_enabled();
  ok(Imager->open_log(log => $log_name), "open log")
    or diag("Open log: " . Imager->errstr);
  ok(-f $log_name, "file is there");
  Imager->log($log_message);
  Imager->close_log();

  my $data = '';
  if (open LOG, "< $log_name") {
    $data = do { local $/; <LOG> };
    close LOG;
  }
  like($data, qr/\Q$log_message/, "check message made it to the log");
}

SKIP: {
  skip("Logging built", 3)
    if Imager::i_log_enabled();

  ok(!Imager->open_log(log => $log_name), "should be no logfile");
  is(Imager->errstr, "Logging disabled", "check error message");
  ok(!-f $log_name, "file shouldn't be there");
}
