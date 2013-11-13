#!perl -w
use strict;
use ExtUtils::MakeMaker;

my %opts = 
  (
   NAME => 'Imager::Filter::DynTest',
   VERSION_FROM => 'DynTest.pm',
   OBJECT => 'DynTest.o linstretch.o',
   INC => '-I..'
  );
my $MM_ver = eval $ExtUtils::MakeMaker::VERSION;
if ($MM_ver > 6.06) {
  $opts{AUTHOR} = 'Tony Cook <tonyc@cpan.org>';
  $opts{ABSTRACT} = 'Demo Imager filter extension';
}

WriteMakefile(%opts);


