#!perl -w
use strict;
use ExtUtils::MakeMaker;

my %opts = 
  (
   NAME => 'Imager::Filter::Mandelbrot',
   VERSION_FROM => 'Mandelbrot.pm',
   OBJECT => 'Mandelbrot.o mandel.o',
   INC => '-I..'
  );
my $MM_ver = eval $ExtUtils::MakeMaker::VERSION;
if ($MM_ver > 6.06) {
  $opts{AUTHOR} = 'Tony Cook <tonyc@cpan.org>';
  $opts{ABSTRACT} = 'Mandelbrot Imager filter extension';
}

WriteMakefile(%opts);


