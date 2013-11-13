#!perl -w
use strict;
use Test::More tests => 7;
BEGIN { use_ok("Imager", ":all") }

-d "testout" or mkdir "testout";

Imager->open_log(log => "testout/t05error.log");

# try to read an invalid pnm file
open FH, "< testimg/junk.ppm"
  or die "Cannot open testin/junk: $!";
binmode(FH);
my $IO = Imager::io_new_fd(fileno(FH));
my $im = i_readpnm_wiol($IO, -1);
SKIP:{
  ok(!$im, "read of junk.ppm should have failed")
    or skip("read didn't fail!", 5);

  my @errors = Imager::i_errors();

  is(scalar @errors, 1, "got the errors")
    or skip("no errors to check", 4);

 SKIP:
  {
    my $error0 = $errors[0];
    is(ref $error0, "ARRAY", "entry 0 is an array ref")
      or skip("entry 0 not an array", 3);

    is(scalar @$error0, 2, "entry 0 has 2 elements")
      or skip("entry 0 doesn't have enough elements", 2);

    is($error0->[0], "while skipping to height", "check message");
    is($error0->[1], "0", "error code should be 0");
  }
}

Imager->close_log;

unless ($ENV{IMAGER_KEEP_FILES}) {
  unlink "testout/t05error.log";
}
