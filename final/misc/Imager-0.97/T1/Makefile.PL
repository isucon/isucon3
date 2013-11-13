#!perl -w
use strict;
use ExtUtils::MakeMaker;
use Getopt::Long;
use Config;

my $verbose = $ENV{IM_VERBOSE};
my @libpaths;
my @incpaths;

GetOptions("incpath=s", \@incpaths,
           "libpath=s" => \@libpaths,
           "verbose|v" => \$verbose);

our $BUILDING_IMAGER;
our %IMAGER_LIBS;

my $MM_ver = eval $ExtUtils::MakeMaker::VERSION;

my %opts = 
  (
   NAME => 'Imager::Font::T1',
   VERSION_FROM => 'T1.pm',
   OBJECT => 'T1.o imt1.o',
   clean => { FILES => 'testout' },
  );

my @inc;
if ($BUILDING_IMAGER) {
  push @inc, "-I..";
  unshift @INC, "../lib";
}
else {
  unshift @INC, "inc";
  print "T1Lib: building independently\n";
  require Imager::ExtUtils;
  push @inc, Imager::ExtUtils->includes;
  $opts{TYPEMAPS} = [ Imager::ExtUtils->typemap ];

  # Imager required configure through use
  my @Imager_req = ( Imager => "0.95" );
  if ($MM_ver >= 6.46) {
    $opts{META_MERGE} =
      {
       configure_requires => 
       {
	@Imager_req,
       },
       build_requires => 
       {
	@Imager_req,
	"Test::More" => "0.47",
       },
       resources =>
       {
	homepage => "http://imager.perl.org/",
	repository => "git://git.imager.perl.org/imager.git",
	bugtracker => "http://rt.cpan.org/NoAuth/Bugs.html?Dist=Imager",
       },
      };
    $opts{PREREQ_PM} =
      {
       @Imager_req,
       XSLoader => 0,
      };
  }
}

require Imager::Probe;

my %probe =
  (
   name => "T1Lib",
   inccheck =>
   sub { -e File::Spec->catfile($_[0], "t1lib.h") },
   libbase => "t1",
   testcode => _t1_test_code(),
   testcodeheaders => [ "stdio.h", "string.h", "t1lib.h" ],
   incpath => \@incpaths,
   libpath => \@libpaths,
   verbose => $verbose,
  );

my $probe_res = Imager::Probe->probe(\%probe);
if ($probe_res) {
  $IMAGER_LIBS{T1} = 1;

  push @inc, $probe_res->{INC};
  $opts{LIBS} = $probe_res->{LIBS};
  $opts{DEFINE} = $probe_res->{DEFINE};
  $opts{INC} = "@inc";

  if ($MM_ver > 6.06) {
    $opts{AUTHOR} = 'Tony Cook <tonyc@cpan.org>';
    $opts{ABSTRACT} = 'T1Lib font driver for Imager';
  }
  
  WriteMakefile(%opts);
}
else {
  $IMAGER_LIBS{T1} = 0;

  if ($BUILDING_IMAGER) {
    ExtUtils::MakeMaker::WriteEmptyMakefile(%opts);
  }
  else {
    # fail in good way
    die "OS unsupported: T1Lib headers/libraries not found\n";
  }
}

sub _t1_test_code {
  return <<'CODE';
int font_id;
if (T1_InitLib(IGNORE_CONFIGFILE|IGNORE_FONTDATABASE) == NULL) {
  fprintf(stderr, "T1Lib: Cannot initialize\n");
  return 1;
}
T1_CloseLib();
return 0;
CODE
}

