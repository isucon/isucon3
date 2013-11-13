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
   NAME => 'Imager::File::GIF',
   VERSION_FROM => 'GIF.pm',
   OBJECT => 'GIF.o imgif.o',
   clean => { FILES => 'testout' },
  );

my @inc;
if ($BUILDING_IMAGER) {
  unshift @inc, "-I..";
  unshift @INC, "../lib";
}
else {
  unshift @INC, "inc";
  print "GIF: building independently\n";
  require Imager::ExtUtils;
  push @inc, Imager::ExtUtils->includes;
  $opts{TYPEMAPS} = [ Imager::ExtUtils->typemap ];

  # Imager required configure through use
  my @Imager_req = ( Imager => "0.94" );
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
   name => "GIF",
   inccheck => sub { -e File::Spec->catfile($_[0], "gif_lib.h") },
   libbase => "gif",
   testcode => _gif_test_code(),
   testcodeheaders => [ "stddef.h", "gif_lib.h", "stdio.h", "errno.h", "string.h" ],
   incpath => \@incpaths,
   libpath => \@libpaths,
   verbose => $verbose,
  );

my $probe_res = Imager::Probe->probe(\%probe);
if ($probe_res) {
  $IMAGER_LIBS{GIF} = 1;

  push @inc, $probe_res->{INC};
  $opts{LIBS} = $probe_res->{LIBS};
  $opts{DEFINE} = $probe_res->{DEFINE};
  $opts{INC} = "@inc";
  
  if ($MM_ver > 6.06) {
    $opts{AUTHOR} = 'Tony Cook <tonyc@cpan.org>';
    $opts{ABSTRACT} = 'GIF Image file support';
  }
  
  WriteMakefile(%opts);
}
else {
  $IMAGER_LIBS{GIF} = 0;

  if ($BUILDING_IMAGER) {
    ExtUtils::MakeMaker::WriteEmptyMakefile(%opts);
  }
  else {
    # fail in good way
    die "OS unsupported: GIF libraries or headers not found\n";
  }
}

sub _gif_test_code {
  return <<'CODE';
/* TODO: test DGifOpen() and processing with callbacks */
GifFileType *gf;
#ifdef GIF_LIB_VERSION
const char vers[] = GIF_LIB_VERSION;
const char *versp = vers;
int ver_maj;
int ver_min;
#else
int ver_maj = GIFLIB_MAJOR;
int ver_min = GIFLIB_MINOR;
int error;
#endif
GifColorType colors[2];
ColorMapObject *map;
FILE *fh;
char buf[6];
int mode;
#if defined(GIFLIB_MAJOR) && GIFLIB_MAJOR >= 5
gf=DGifOpenFileName("testimg/expected.gif", &error);
#else
gf=DGifOpenFileName("testimg/expected.gif");
#endif
if (!gf) {
  fprintf(stderr, "GIF: Cannot open testimg/expected.gif\n");
  return 1;
}
if (gf->SWidth != 16 || gf->SHeight != 16) {
  fprintf(stderr, "GIF: bad screen description (%d x %d)\n", gf->SWidth, gf->SHeight);
  return 1;
}
#if !defined(GIFLIB_MAJOR) || GIFLIB_MAJOR < 5
/* crashes in older versions of giflib, not used in giflib 5 */
EGifSetGifVersion("89a");
EGifSetGifVersion("87a");
#endif

#ifdef GIF_LIB_VERSION
/* skip the " Version " */
while (*versp && (*versp < '0' || *versp > '9'))
  ++versp;
if (!*versp) {
  fprintf(stderr, "GIF: Cannot find version number in '%s'\n", vers);
  return 1;
}
ver_maj = 0;
while (*versp && *versp >= '0' && *versp <= '9') {
  ver_maj *= 10;
  ver_maj += *versp++ - '0';
}
if (*versp != '.' || versp[1] < '0' || versp[1] > '9') {
  fprintf(stderr, "Cannot parse major version number in '%s'\n", vers);
  return 1;
}
++versp; /* skip '.' */
ver_min = 0;
while (*versp && *versp >= '0' && *versp <= '9') {
  ver_min *= 10;
  ver_min += *versp++ - '0';
}
#endif
if (ver_maj < 4) {
  fprintf(stderr, "GIF: gif lib version 3 is no longer supported\n");
  return 1;
}
if (ver_maj == 4 && ver_min < 1) {
  fprintf(stderr, "GIF: you need at least giflib 4.1\n");
  return 1;
}

/* test we write both GIF87a and GIF89a files */
for (mode = 0; mode < 2; ++mode) {
#if defined(GIFLIB_MAJOR) && GIFLIB_MAJOR >= 5
  gf=EGifOpenFileName("probe.gif", 0, &error);
  EGifSetGifVersion(gf, mode);

#else
  gf=EGifOpenFileName("probe.gif", 0);
  EGifSetGifVersion(mode ? "89a" : "87a");
#endif
  if (!gf) {
    fprintf(stderr, "GIF: cannot create probe.gif for testing\n");
    return 1;
  }
  colors[0].Red = colors[0].Green = colors[0].Blue = 0;
  colors[1].Red = colors[1].Green = colors[1].Blue = 0;
#if defined(GIFLIB_MAJOR) && GIFLIB_MAJOR >= 5
  map = GifMakeMapObject(2, colors);
#else
  map = MakeMapObject(2, colors);
#endif
  EGifPutScreenDesc(gf, 1, 1, 1, 0, map);
  EGifPutImageDesc(gf, 0, 0, 1, 1, 0, NULL);
  EGifPutPixel(gf, 0);
  EGifCloseFile(gf);

  fh = fopen("probe.gif", "r");
  if (!fh) {
    fprintf(stderr, "GIF: cannot open probe.gif for reading\n");
    return 1;
  }
  errno = 0;
  memset(buf, 0, sizeof(buf));
  if (fread(buf, 1, 6, fh) != 6) {
    fprintf(stderr, "GIF: cannot read probe.gif header (%d)\n", errno);
    return 1;
  }
  fclose(fh);
  if (memcmp(buf, mode ? "GIF89a" : "GIF87a", 6)) {
    fprintf(stderr, "GIF: incorrect header on test - 4.2.0 bug? (mode %d, buf %-6s)\n", mode, buf);
    return 1;
  }
  remove("probe.gif");
}

fprintf(stderr, "GIF: Major %d, Minor %d\n", ver_maj, ver_min);
return 0;
CODE
}
