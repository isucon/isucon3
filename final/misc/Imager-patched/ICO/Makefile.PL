#!perl -w
use strict;
use ExtUtils::MakeMaker;

my %opts = 
  (
   NAME => 'Imager::File::ICO',
   VERSION_FROM => 'ICO.pm',
   OBJECT => 'ICO.o msicon.o imicon.o',
   INC => '-I..',
   clean => { FILES => 'testout' },
  );
my $MM_ver = eval $ExtUtils::MakeMaker::VERSION;
if ($MM_ver > 6.06) {
  $opts{AUTHOR} = 'Tony Cook <tonyc@cpan.org>';
  $opts{ABSTRACT} = 'Icon Image file support';
}

WriteMakefile(%opts);


