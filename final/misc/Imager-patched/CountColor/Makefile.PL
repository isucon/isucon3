#!perl -w
use strict;
use ExtUtils::MakeMaker;

my %opts = 
  (
   NAME => 'Imager::CountColor',
   VERSION_FROM => 'CountColor.pm',
   OBJECT => 'CountColor.o',
   INC => '-I..',
  );
my $MM_ver = eval $ExtUtils::MakeMaker::VERSION;
if ($MM_ver > 6.06) {
  $opts{AUTHOR} = 'Tony Cook <tonyc@cpan.org>';
  $opts{ABSTRACT} = 'Color Count an Imager image';
}

WriteMakefile(%opts);


