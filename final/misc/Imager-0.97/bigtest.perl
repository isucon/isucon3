#!perl -w
use strict;
# tests Imager with every combination of options
my @opts = qw(jpeg tiff png gif ungif T1-fonts TT-fonts freetype2);

# each option gets a bit
my %bits;
@bits{@opts} = map { 1 << $_ } 0..(@opts-1);

my $perl = $ENV{PERLBIN} || "perl";
my $make = $ENV{MAKEBIN} || "make";
my $makeopts = $ENV{MAKEOPTS} || '';
use Getopt::Std;
my %opts;
getopts('vd', \%opts);

my $top = (1 << @opts)-1;

my @results;
my $testlog = "bigtest.txt";

unlink $testlog;
my $total = 0;
my $good = 0;
system("$make clean") if -e 'Makefile' && !$opts{d};
for my $set (0..$top) {
  ++$total;
  $ENV{IM_ENABLE} = join(' ', grep($set & $bits{$_}, @opts));
  print STDERR $opts{v} ? "$set/$top Enable: $ENV{IM_ENABLE}\n" : '.';
  system("echo '****' \$IM_ENABLE >>$testlog");
  if ($opts{d}) {
    if (system("$make $makeopts disttest >>$testlog.txt 2>&1")) {
      push(@results, [ $ENV{IM_ENABLE}, 'disttest failed' ]);
      next;
    }
  }
  else {
    unlink 'Makefile';
    if (system("$perl Makefile.PL >>$testlog 2>&1")) {
      push(@results, [ $ENV{IM_ENABLE}, 'Makefile.PL failed' ]);
      next;
    }
    if (system("$make $makeopts >>$testlog 2>&1")) {
      push(@results, [ $ENV{IM_ENABLE}, 'make failed' ]);
      next;
    }
    if (system("$make test >>$testlog 2>&1")) {
      push(@results, [ $ENV{IM_ENABLE}, 'test failed' ]);
      next;
    }
    if (system("$make clean >>$testlog 2>&1")) {
      push(@results, [ $ENV{IM_ENABLE}, 'clean failed' ]);
      next;
    }
  }

  push(@results, [ $ENV{IM_ENABLE}, 'success' ]);
  ++$good;
}
print STDERR "\n";
printf("%-20s %-50s\n", "Result", "Options");
printf("%-20s %-50s\n", "-" x 20, "-" x 50);
foreach my $row (@results) {
  printf("%-20s %-50s\n", @$row[1,0]);
}
print "-" x 71, "\n";
print "Total: $total  Successes: $good  Failures: ",$total-$good,"\n";
print "Output in $testlog\n";

__END__

=head1 NAME

  bigtest.perl - tests combinations of libraries usable by Imager

=head1 SYNOPSYS

  perl bigtest.perl
  # grab a cup of coffee or four - this takes a while

=head1 DESCRIPTION

bigtest.perl uses the new IM_ENABLE environment variable of
Makefile.PL to built Imager for all possible combinations of libraries
that Imager uses.

At the time of writing this is 128 combinations, which takes quite a
while.

=head1 OPTIONS

 -v - verbose output

 -d - perform disttest for each combination

=head1 ENVIRONMENT VARIABLES

PERLBIN - the perl binary to use

MAKEBIN - the make binary to use

Any other variables used by Imager's Makefile.PL, except for IM_MANUAL
or IM_ENABLE.

=head1 BUGS

Doesn't test other possible options, like IM_NOLOG or IM_DEBUG_MALLOC.

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut

