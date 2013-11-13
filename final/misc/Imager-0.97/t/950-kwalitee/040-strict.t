#!perl -w
# this is intended for various kwalitee tests
use strict;
use Test::More;
use ExtUtils::Manifest qw(maniread);

my $manifest = maniread;

# work up counts first

my @pl_files = grep /\.(p[lm]|PL|perl)$/, keys %$manifest;

plan tests => scalar(@pl_files);

for my $filename (@pl_files) {
  open PL, "< $filename"
    or die "Cannot open $filename: $!";
  my $found_strict;
  while (<PL>) {
    if (/^use strict;/) {
      ++$found_strict;
      last;
    }
  }
  close PL;
  ok($found_strict, "file $filename has use strict");
}
