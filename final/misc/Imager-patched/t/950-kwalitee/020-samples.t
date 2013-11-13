#!perl -w
# packaging test - make sure we included the samples in the MANIFEST <sigh>
use Test::More;
use ExtUtils::Manifest qw(maniread);

# first build a list of samples from samples/README
open SAMPLES, "< samples/README"
  or die "Cannot open samples/README: $!";
my @sample_files;
while (<SAMPLES>) {
  chomp;
  /^\w[\w.-]+\.\w+$/ and push @sample_files, $_;
}

close SAMPLES;

my $manifest = maniread();

my @mani_samples = sort grep m(^samples/\w+\.pl$), keys %$manifest;

plan tests => scalar(@sample_files) + scalar(@mani_samples);

for my $filename (@sample_files) {
  ok(exists($manifest->{"samples/$filename"}), 
     "sample file $filename in manifest");
}

my %files = map { $_ => 1 } @sample_files;
for my $filename (@mani_samples) {
  $filename =~ s(^samples/)();
  ok(exists $files{$filename},
     "sample $filename in manifest found in README");
}
