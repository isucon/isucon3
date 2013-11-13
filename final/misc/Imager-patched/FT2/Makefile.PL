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
   NAME => 'Imager::Font::FT2',
   VERSION_FROM => 'FT2.pm',
   OBJECT => 'FT2.o freetyp2.o',
   clean => { FILES => 'testout' },
  );

my @inc;
if ($BUILDING_IMAGER) {
  push @inc, "-I..";
  unshift @INC, "../lib";
}
else {
  unshift @INC, "inc";
  print "FreeType 2: building independently\n";
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
       'Scalar::Util' => 1.00,
       XSLoader => 0,
      };
  }
}

require Imager::Probe;

my %probe =
  (
   name => "FreeType 2",
   code => \&freetype2_probe_ftconfig,
   inccheck =>
   sub { -e File::Spec->catfile($_[0], "freetype/ftbitmap.h") },
   libbase => "freetype",
   testcode => _ft2_test_code(),
   testcodeheaders => [ "stdio.h", "string.h", "ft2build.h" ],
   testcodeprologue => _ft2_test_code_prologue(),
   incpath => \@incpaths,
   libpath => \@libpaths,
   alternatives =>
   [
    {
     incsuffix => "freetype2",
    },
    {
     incsuffix => "freetype",
    },
   ],
   verbose => $verbose,
  );

my $probe_res = Imager::Probe->probe(\%probe);
if ($probe_res) {
  $IMAGER_LIBS{FT2} = 1;

  push @inc, $probe_res->{INC};
  $opts{LIBS} = $probe_res->{LIBS};
  $opts{DEFINE} = $probe_res->{DEFINE};
  $opts{INC} = "@inc";
  $opts{LDDLFLAGS} = $probe_res->{LDDLFLAGS}
    if $probe_res->{LDDLFLAGS};

  if ($MM_ver > 6.06) {
    $opts{AUTHOR} = 'Tony Cook <tonyc@cpan.org>';
    $opts{ABSTRACT} = 'FreeType 2 font driver for Imager';
  }
  
  WriteMakefile(%opts);
}
else {
  $IMAGER_LIBS{FT2} = 0;

  if ($BUILDING_IMAGER) {
    ExtUtils::MakeMaker::WriteEmptyMakefile(%opts);
  }
  else {
    # fail in good way
    die "OS unsupported: FreeType 2 headers/libraries not found\n";
  }
}

sub _ft2_test_code {
  return <<'CODE';
FT_Library library = 0;
FT_Face face = 0;
FT_Error error;
error = FT_Init_FreeType(&library);
if (error) {
  fprintf(stderr, "FreeType 2: cannot initialize library: %d\n", error);
  return 1;
}
error = FT_New_Face(library, "fontfiles/dodge.ttf", 0, &face);
if (error) {
  fprintf(stderr, "FreeType 2: cannot load font: %d\n", error);
  return 1;
}
return 0;
CODE
}

sub _ft2_test_code_prologue {
  return <<'CODE';
#include FT_FREETYPE_H

CODE
}

sub is_exe {
  my ($name) = @_;

  my @exe_suffix = $Config{_exe};
  if ($^O eq 'MSWin32') {
    push @exe_suffix, qw/.bat .cmd/;
  }
  elsif ($^O eq 'cygwin') {
    push @exe_suffix, "";
  }

  for my $dir (File::Spec->path) {
    for my $suffix (@exe_suffix) {
      -x File::Spec->catfile($dir, "$name$suffix")
	and return 1;
    }
  }

  return;
}

# probes for freetype2 by trying to run freetype-config
sub freetype2_probe_ftconfig {
  my ($req) = @_;

  is_exe('freetype-config') or return;

  my $cflags = `freetype-config --cflags`
    and !$? or return;
  chomp $cflags;

  my $lflags = `freetype-config --libs`
    and !$? or return;
  chomp $lflags;

  # before 2.1.5 freetype-config --cflags could output
  # the -I options in the wrong order, causing a conflict with
  # freetype1.x installed with the same --prefix
  #
  # can happen iff:
  #  - both -Iprefix/include and -Iprefix/include/freetype2 are in cflags
  #    in that order
  #  - freetype 1.x headers are in prefix/include/freetype
  my @incdirs = map substr($_, 2), grep /^-I/, split ' ', $cflags;
  if (@incdirs == 2 
      && $incdirs[1] eq "$incdirs[0]/freetype2"
      && -e "$incdirs[0]/freetype/freetype.h"
      && -e "$incdirs[0]/freetype/fterrid.h") {
    print "** freetype-config provided -I options out of order, correcting\n"
      if $verbose;
    $cflags = join(' ', grep(!/-I/, split ' ', $cflags),
		   map "-I$_", reverse @incdirs);
  }

  print "$req->{name}: configured via freetype-config\n";

  return
    {
     INC => $cflags,
     LIBS => $lflags,
    };
}
