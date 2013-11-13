#!perl -w
use strict;
use lib 't';
use Test::More;
use ExtUtils::Manifest qw(maniread);
#sub Pod::Coverage::TRACE_ALL() { 1 }
eval "use Test::Pod::Coverage 1.08;";
# 1.08 required for coverage_class support
plan skip_all => "Test::Pod::Coverage 1.08 required for POD coverage" if $@;

# scan for a list of files to get Imager method documentation from
my $manifest = maniread();
my @pods = ( 'Imager.pm', grep /\.pod$/, keys %$manifest );

my @private = 
  ( 
   '^io?_',
   '^DSO_',
   '^Inline$',
   '^yatf$',
   '^malloc_state$',
   '^init_log$',
   '^polybezier$', # not ready for public consumption
   '^border$', # I don't know what it is, expect it to go away
  );
my @trustme = ( '^open$',  );

plan tests => 20;

{
  pod_coverage_ok('Imager', { also_private => \@private,
			      pod_from => \@pods,
			      trustme => \@trustme,
			      coverage_class => 'Pod::Coverage::Imager' });
  pod_coverage_ok('Imager::Font');
  my @color_private = ( '^i_', '_internal$' );
  pod_coverage_ok('Imager::Color', 
		  { also_private => \@color_private });
  pod_coverage_ok('Imager::Color::Float', 
		  { also_private => \@color_private });
  pod_coverage_ok('Imager::Color::Table');
  pod_coverage_ok('Imager::ExtUtils');
  pod_coverage_ok('Imager::Expr');
  my $trust_parents = { coverage_class => 'Pod::Coverage::CountParents' };
  pod_coverage_ok('Imager::Expr::Assem', $trust_parents);
  pod_coverage_ok('Imager::Fill');
  pod_coverage_ok('Imager::Font::BBox');
  pod_coverage_ok('Imager::Font::Wrap');
  pod_coverage_ok('Imager::Fountain');
  pod_coverage_ok('Imager::Matrix2d');
  pod_coverage_ok('Imager::Regops');
  pod_coverage_ok('Imager::Transform');
  pod_coverage_ok('Imager::Test');
  pod_coverage_ok('Imager::IO',
		  {
		   pod_from => "lib/Imager/IO.pod",
		   coverage_class => "Pod::Coverage::Imager",
		   module => "Imager",
		  });
}

{
  # check all documented methods/functions are in the method index
  my $coverage = 
    Pod::Coverage::Imager->new(package => 'Imager',
			       pod_from => \@pods,
			       trustme => \@trustme,
			       also_private => \@private);
  my %methods = map { $_ => 1 } $coverage->covered;
  open IMAGER, "< Imager.pm"
    or die "Cannot open Imager.pm: $!";
  while (<IMAGER>) {
    last if /^=head1 METHOD INDEX/;
  }
  my @indexed;
  my @unknown_indexed;
  while (<IMAGER>) {
    last if /^=\w/ && !/^=for\b/;

    if (/^(\w+)\(/) {
      push @indexed, $1;
      unless (delete $methods{$1}) {
	push @unknown_indexed, $1;
      }
    }
  }

  unless (is(keys %methods, 0, "all methods in method index")) {
    diag "the following methods are documented but not in the index:";
    diag $_ for sort keys %methods;
  }
  unless (is(@unknown_indexed, 0, "only methods in method index")) {
    diag "the following names are in the method index but not documented";
    diag $_ for sort @unknown_indexed;
  }

  sub dict_cmp_func;
  is_deeply(\@indexed, [ sort dict_cmp_func @indexed ],
	    "check method index is alphabetically sorted");
}

sub dict_cmp_func {
  (my $tmp_a = lc $a) =~ tr/_//d;
  (my $tmp_b = lc $b) =~ tr/_//d;

  $tmp_a cmp $tmp_b;
}
