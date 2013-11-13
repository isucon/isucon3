#!perl -w
use strict;
use ExtUtils::MakeMaker;

my %opts = 
  (
   NAME => 'Imager::File::SGI',
   VERSION_FROM => 'SGI.pm',
   OBJECT => 'SGI.o imsgi.o',
   INC => '-I..',
   clean => { FILES => 'testout' },
  );
my $MM_ver = eval $ExtUtils::MakeMaker::VERSION;
if ($MM_ver > 6.06) {
  $opts{AUTHOR} = 'Tony Cook <tonyc@cpan.org>';
  $opts{ABSTRACT} = 'SGI Image file support';
}

WriteMakefile(%opts);


