#!perl -w
use strict;
use ExtUtils::MakeMaker;
use Cwd;
use Config;
use File::Spec;
use Getopt::Long;
use ExtUtils::Manifest qw(maniread);
use ExtUtils::Liblist;
use vars qw(%formats $VERBOSE $INCPATH $LIBPATH $NOLOG $DEBUG_MALLOC $MANUAL $CFLAGS $LFLAGS $DFLAGS);
use lib 'inc';
use Devel::CheckLib;

# EU::MM runs Makefile.PL all in the same process, so sub-modules will
# see this
our $BUILDING_IMAGER = 1;

# used to display a summary after we've probed the world
our %IMAGER_LIBS;

#
# IM_INCPATH      colon seperated list of paths to extra include paths
# IM_LIBPATH      colon seperated list of paths to extra library paths
#
# IM_VERBOSE      turns on verbose mode for the library finding and such
# IM_MANUAL       to manually select which libraries are used and which not
# IM_ENABLE       to programmatically select which libraries are used
#                 and which are not
# IM_NOLOG        if true logging will not be compiled into the module
# IM_DEBUG_MALLOC if true malloc debbuging will be compiled into the module
#                 do not use IM_DEBUG_MALLOC in production - this slows
#                 everything down by alot
# IM_CFLAGS       Extra flags to pass to the compiler
# IM_LFLAGS       Extra flags to pass to the linker
# IM_DFLAGS       Extra flags to pass to the preprocessor

my $KEEP_FILES = $ENV{IMAGER_KEEP_FILES};

getenv();     # get environment variables

my $lext=$Config{'so'};   # Get extensions of libraries
my $aext=$Config{'_a'};

my $help; # display help if set
my @enable; # list of drivers to enable
my @disable; # or list of drivers to disable
my @incpaths; # places to look for headers
my @libpaths; # places to look for libraries
my $coverage; # build for coverage testing
my $assert; # build with assertions
my $trace_context; # trace context management to stderr
GetOptions("help" => \$help,
           "enable=s" => \@enable,
           "disable=s" => \@disable,
           "incpath=s", \@incpaths,
           "libpath=s" => \@libpaths,
           "verbose|v" => \$VERBOSE,
           "nolog" => \$NOLOG,
	   'coverage' => \$coverage,
	   "assert|a" => \$assert,
	   "tracecontext" => \$trace_context);

setenv();

if ($ENV{AUTOMATED_TESTING}) {
  $assert = 1;
}

if ($VERBOSE) { 
  print "Verbose mode\n"; 
  require Data::Dumper; 
  import Data::Dumper qw(Dumper);
}

if ($help) {
  usage();
}

my @defines;

if ($NOLOG)   { print "Logging not compiled into module\n"; }
else { 
  push @defines, [ IMAGER_LOG => 1, "Logging system" ];
}

if ($assert) {
  push @defines, [ IM_ASSERT => 1, "im_assert() are effective" ];
}

if ($DEBUG_MALLOC) {
  push @defines, [ IMAGER_DEBUG_MALLOC => 1, "Use Imager's DEBUG malloc()" ];
  print "Malloc debugging enabled\n";
}

if (@enable && @disable) {
  print STDERR "Only --enable or --disable can be used, not both, try --help\n";
  exit 1;
}

my %definc;
my %deflib;
my @incs; # all the places to look for headers
my @libs; # all the places to look for libraries

init();       # initialize global data
pathcheck();  # Check if directories exist

if (exists $ENV{IM_ENABLE}) {
  my %en = map { $_, 1 } split ' ', $ENV{IM_ENABLE};
  for my $key (keys %formats) {
    delete $formats{$key} unless $en{$key};
  }
}
if (@enable) {
  my %en = map { $_ => 1 } map { split /,/ } @enable;
  for my $key (keys %formats) {
    delete $formats{$key} unless $en{$key};
  }
}
elsif (@disable) {
  delete @formats{map { split /,/ } @disable};
}

# Pick what libraries are used
if ($MANUAL) {
  manual();
} else {
  automatic();
}

my $lib_cflags = '';
my $lib_lflags = '';
my $F_LIBS = '';
my $F_OBJECT = '';
for my $frmkey (sort { $formats{$a}{order} <=> $formats{$b}{order} } keys %formats) {
  my $frm = $formats{$frmkey};
  push @defines, [ $frm->{def}, 1, "$frmkey available" ];
  $F_OBJECT .= ' '  .$frm->{objfiles};
  if ($frm->{cflags}) {
    $lib_cflags   .= ' '  .$frm->{cflags};
    ++$definc{$_} for map { /^-I(.*)$/ ? ($1) : () }
      grep /^-I./, split ' ', $frm->{cflags};
  }
  if ($frm->{lflags}) {
    $lib_lflags .= ' ' . $frm->{lflags};
  }
  else {
    $F_LIBS   .= ' '  .$frm->{libfiles};
  }

}

my $F_INC  = join ' ', map "-I$_", map / / ? qq{"$_"} : $_, 
  grep !$definc{$_}, @incs;
$F_LIBS = join(' ',map "-L$_", map / / ? qq{"$_"} : $_, 
	       grep !$deflib{$_}++, @libs) . $F_LIBS;

my $OSLIBS = '';
my $OSDEF  = "-DOS_$^O";

if ($^O eq 'hpux')                { $OSLIBS .= ' -ldld'; }
if (defined $Config{'d_dlsymun'}) { $OSDEF  .= ' -DDLSYMUN'; }

my @objs = qw(Imager.o context.o draw.o polygon.o image.o io.o iolayer.o
              log.o gaussian.o conv.o pnm.o raw.o feat.o combine.o
              filters.o dynaload.o stackmach.o datatypes.o
              regmach.o trans2.o quant.o error.o convert.o
              map.o tags.o palimg.o maskimg.o img8.o img16.o rotate.o
              bmp.o tga.o color.o fills.o imgdouble.o limits.o hlines.o
              imext.o scale.o rubthru.o render.o paste.o compose.o flip.o
	      perlio.o);

if ($Config{useithreads}) {
  if ($Config{i_pthread}) {
    print "POSIX threads\n";
    push @objs, "mutexpthr.o";
  }
  elsif ($^O eq 'MSWin32') {
    print "Win32 threads\n";
    push @objs, "mutexwin.o";
  }
  else {
    print "Unsupported threading model\n";
    push @objs, "mutexnull.o";
    if ($ENV{AUTOMATED_TESTING}) {
      die "OS unsupported: no threading support code for this platform\n";
    }
  }
}
else {
  print "No threads\n";
  push @objs, "mutexnull.o";
}

my @typemaps = qw(typemap.local typemap);
if ($] < 5.008) {
    unshift @typemaps, "typemap.oldperl";
}

if ($trace_context) {
  $CFLAGS .= " -DIMAGER_TRACE_CONTEXT";
}

my $tests = 't/*.t t/*/*.t';
if (-d "xt" && scalar(() = glob("xt/*.t"))) {
  $tests .= " xt/*.t";
}

my %opts=
  (
   'NAME'         => 'Imager',
   'VERSION_FROM' => 'Imager.pm',
   'LIBS'         => "$LFLAGS -lm $lib_lflags $OSLIBS $F_LIBS",
   'DEFINE'       => "$OSDEF $CFLAGS",
   'INC'          => "$lib_cflags $DFLAGS $F_INC",
   'OBJECT'       => join(' ', @objs, $F_OBJECT),
   clean          => { FILES=>'testout rubthru.c scale.c conv.c  filters.c gaussian.c render.c rubthru.c' },
   PM             => gen_PM(),
   PREREQ_PM      =>
   { 
    'Test::More' => 0.47,
    'Scalar::Util' => 1.00,
    'XSLoader'    => 0,
   },
   TYPEMAPS       => \@typemaps,
   test =>        { TESTS => $tests },
  );

if ($coverage) {
    if ($Config{gccversion}) {
	push @ARGV, 'OPTIMIZE=-ftest-coverage -fprofile-arcs -g';
	$opts{dynamic_lib} = { OTHERLDFLAGS => '-ftest-coverage -fprofile-arcs' };
    }
    else {
	die "Don't know the coverage C flags for your compiler\n";
    }
}

# eval to prevent warnings about versions with _ in them
my $MM_ver = eval $ExtUtils::MakeMaker::VERSION;
if ($MM_ver > 6.06) {
  $opts{AUTHOR} = 'Tony Cook <tonyc@cpan.org>, Arnar M. Hrafnkelsson';
  $opts{ABSTRACT} = 'Perl extension for Generating 24 bit Images';
}

if ($MM_ver >= 6.46) {
  $opts{META_MERGE} =
    {
     recommends =>
     {
      "Parse::RecDescent" => 0
     },
     license => "perl",
     dynamic_config => 1,
     no_index =>
     {
      directory =>
      [
       "PNG",
       "GIF",
       "TIFF",
       "JPEG",
       "W32",
       "FT2",
       "T1",
      ],
     },
     resources =>
     {
      homepage => "http://imager.perl.org/",
      repository => "git://git.imager.perl.org/imager.git",
      bugtracker => "http://rt.cpan.org/NoAuth/Bugs.html?Dist=Imager",
     },
    };
}

make_imconfig(\@defines);

if ($VERBOSE) { print Dumper(\%opts); }
mkdir('testout',0777); # since we cannot include it in the archive.

-d "probe" and rmdir "probe";

WriteMakefile(%opts);

my @good;
my @bad;
for my $name (sort { lc $a cmp lc $b } keys %IMAGER_LIBS) {
  if ($IMAGER_LIBS{$name}) {
    push @good, $name;
  }
  else {
    push @bad, $name;
  }
}

print "\n";
print "Libraries found:\n" if @good;
print "  $_\n" for @good;
print "Libraries *not* found:\n" if @bad;
print "  $_\n" for @bad;

exit;


sub MY::postamble {
    my $self = shift;
    my $perl = $self->{PERLRUN} ? '$(PERLRUN)' : '$(PERL)';
    my $mani = maniread;

    my @ims = grep /\.im$/, keys %$mani;
'
dyntest.$(MYEXTLIB) : dynfilt/Makefile
	cd dynfilt && $(MAKE) $(PASTHRU)

lib/Imager/Regops.pm : regmach.h regops.perl
	$(PERL) regops.perl regmach.h lib/Imager/Regops.pm

imconfig.h : Makefile.PL
	$(ECHO) "imconfig.h out-of-date with respect to $?"
	$(PERLRUN) Makefile.PL
	$(ECHO) "==> Your Makefile has been rebuilt - re-run your make command <=="
'.qq!
lib/Imager/APIRef.pod : \$(C_FILES) \$(H_FILES) apidocs.perl
	$perl apidocs.perl lib/Imager/APIRef.pod

!.join('', map _im_rule($perl, $_), @ims)

}

sub _im_rule {
  my ($perl, $im) = @_;

  (my $c = $im) =~ s/\.im$/.c/;
  return <<MAKE;

$c: $im lib/Imager/Preprocess.pm
	$perl -Ilib -MImager::Preprocess -epreprocess $im $c

MAKE

}

# manual configuration of helper libraries

sub manual {
  print <<EOF;

      Please answer the following questions about
      which formats are avaliable on your computer

press <return> to continue
EOF

  <STDIN>; # eat one return

  for my $frm(sort { $formats{$b}{order} <=> $formats{$a}{order} } keys %formats) {
  SWX:
    if ($formats{$frm}{docs}) { print "\n",$formats{$frm}{docs},"\n\n"; }
    print "Enable $frm support: ";
    my $gz = <STDIN>;
    chomp($gz);
    if ($gz =~ m/^(y|yes|n|no)/i) {
      $gz=substr(lc($gz),0,1);
      if ($gz eq 'n') {
	delete $formats{$frm};
      }
    } else { goto SWX; }
  }
}


# automatic configuration of helper libraries

sub automatic {
  print "Automatic probing:\n" if $VERBOSE;
  for my $frm (sort { $formats{$a}{order} <=> $formats{$b}{order} } keys %formats) {
    delete $formats{$frm} if !checkformat($frm);	
  }
}

sub grep_directory {
  my($path, $chk)=@_;

#    print "checking path $path\n";
  if ( !opendir(DH,$path) ) {
    warn "Cannot open dir $path: $!\n";
    return;
  }
  my @l=grep { $chk->($_) } readdir(DH);
  #    print @l;
  close(DH);
  return map $path, @l;
}

sub _probe_default {
  my ($format, $frm) = @_;

  my $lib_check=$formats{$frm}{'libcheck'};
  my $inc_check=$formats{$frm}{'inccheck'};

  if ($lib_check) {
    my @l;
    for my $lp (@libs) {
      push(@l, grep_directory($lp,$lib_check));
    }
    
    my @i;
    for my $ip (@incs) {
      push(@i, $ip) if $inc_check->($ip,$frm);
    }
    
    printf("%10s: includes %s - libraries %s\n",$frm,(@i?'found':'not found'),(@l?'found':'not found'));
    $formats{$frm}{incdir} = \@i;
    $formats{$frm}{libdir} = \@l;
    return 1 if scalar(@i && @l);
  }
  else {
    printf("%10s: not available\n", $frm);
  }

  return 0;
}

sub checkformat {
  my $frm=shift;

  print "  checkformat($frm)\n" if $VERBOSE;
  
  my $format = $formats{$frm};

  my @probes;
  if (my $code = $format->{'code'}) {
    if (ref $code eq 'ARRAY') {
      push @probes, @$code;
    }
    else {
      push @probes, $code;
    }
  }
  push @probes, \&_probe_default;

  print "    Calling probe function\n" if $VERBOSE;
  my $found;
  for my $func (@probes) {
    if ($func->($format, $frm)) {
      ++$found;
      last;
    }
  }

  $found or return;

  if ($format->{postcheck}) {
    print "    Calling postcheck function\n" if $VERBOSE;
    $format->{postcheck}->($format, $frm)
      or return;
  }

  return 1;
}


sub pathcheck {
  if ($VERBOSE) {
    print "pathcheck\n";
    print "  Include paths:\n";
    for (@incs) { print $_,"\n"; }
  }
  @incs=grep { -d $_ && -r _ && -x _ or ( print("  $_ doesnt exist or is unaccessible - removed.\n"),0) } @incs;

  if ($VERBOSE) {
    print "\nLibrary paths:\n";
    for (@libs) { print $_,"\n"; }
  }
  @libs=grep { -d $_ && -r _ && -x _ or ( print("  $_ doesnt exist or is unaccessible - removed.\n"),0) } @libs;
  print "\ndone.\n";
}


# Format data initialization

# format definition is:
# defines needed
# default include path
# files needed for include (boolean perl code)
# default lib path
# libs needed
# files needed for link (boolean perl code)
# object files needed for the format


sub init {

  my @definc = qw(/usr/include);
  @definc{@definc}=(1) x @definc;
  @incs=
    (
     split(/\Q$Config{path_sep}/, $INCPATH),
     map _tilde_expand($_), map { split /\Q$Config{path_sep}/ } @incpaths 
    );
  if ($Config{locincpth}) {
    push @incs, grep -d, split ' ', $Config{locincpth};
  }
  if ($^O =~ /win32/i && $Config{cc} =~ /\bcl\b/i) {
    push(@incs, split /;/, $ENV{INCLUDE}) if exists $ENV{INCLUDE};
  }
  if ($Config{incpath}) {
    push @incs, grep -d, split /\Q$Config{path_sep}/, $Config{incpath};
  }
  push @incs, grep -d,
      qw(/sw/include 
         /usr/include/freetype2
         /usr/local/include/freetype2
         /usr/local/include/freetype1/freetype
         /usr/include /usr/local/include /usr/include/freetype
         /usr/local/include/freetype);
  if ($Config{ccflags}) {
    my @hidden = map { /^-I(.*)$/ ? ($1) : () } split ' ', $Config{ccflags};
    push @incs, @hidden;
    @definc{@hidden} = (1) x @hidden;
  }

  @libs= ( split(/\Q$Config{path_sep}/,$LIBPATH),
    map _tilde_expand($_), map { split /\Q$Config{path_sep}/} @libpaths );
  if ($Config{loclibpth}) {
    push @libs, grep -d, split ' ', $Config{loclibpth};
  }
  
  push @libs, grep -d, qw(/sw/lib),  split(/ /, $Config{'libpth'});
  push @libs, grep -d, split / /, $Config{libspath} if $Config{libspath};
  if ($^O =~ /win32/i && $Config{cc} =~ /\bcl\b/i) {
    push(@libs, split /;/, $ENV{LIB}) if exists $ENV{LIB};
  }
  if ($^O eq 'cygwin') {
    push(@libs, '/usr/lib/w32api') if -d '/usr/lib/w32api';
    push(@incs, '/usr/include/w32api') if -d '/usr/include/w32api';
  }
  if ($Config{ldflags}) {
    # some builds of perl put -Ldir into ldflags without putting it in
    # loclibpth, let's extract them
    my @hidden = grep -d, map { /^-L(.*)$/ ? ($1) : () }
      split ' ', $Config{ldflags};
    push @libs, @hidden;
    # don't mark them as seen - EU::MM will remove any libraries
    # it can't find and it doesn't look for -L in ldflags
    #@deflib{@hidden} = @hidden;
  }
  push @libs, grep -d, qw(/usr/local/lib);

  $formats{'TT-fonts'}=
    {
     order=>'31',
     def=>'HAVE_LIBTT',
     inccheck=>sub { -e catfile($_[0], 'freetype.h')
                       && !-e catfile($_[0], 'fterrors.h') },
     libcheck=>sub { $_[0] eq "libttf$aext" or $_[0] eq "libttf.$lext" },
     libfiles=>'-lttf',
     objfiles=>'fontft1.o',
     code => \&freetype1_probe,
     docs=>q{
Truetype fonts are scalable fonts. They can include 
kerning and hinting information and generally yield good
visual quality esp on low resultions. The freetype library is
used to rasterize for us. The only drawback is that there
are alot of badly designed fonts out there.}
		       };
  # Make fix indent
  for (keys %formats) { $formats{$_}->{docs} =~ s/^\s+/  /mg; }
}



sub gen {
  my $V = $ENV{$_[0]};
  defined($V) ? $V : "";
}


# Get information from environment variables

sub getenv {

  ($VERBOSE,
   $INCPATH,
   $LIBPATH,
   $NOLOG,
   $DEBUG_MALLOC,
   $MANUAL,
   $CFLAGS,
   $LFLAGS,
   $DFLAGS) = map { gen $_ } qw(IM_VERBOSE
				IM_INCPATH
				IM_LIBPATH
				IM_NOLOG
				IM_DEBUG_MALLOC
				IM_MANUAL
				IM_CFLAGS
				IM_LFLAGS
				IM_DFLAGS);

}

# populate the environment so that sub-modules get the same info
sub setenv {
  $ENV{IM_VERBOSE} = 1 if $VERBOSE;
  $ENV{IM_INCPATH} = join $Config{path_sep}, @incpaths if @incpaths;
  $ENV{IM_LIBPATH} = join $Config{path_sep}, @libpaths if @libpaths;
}

sub make_imconfig {
  my ($defines) = @_;

  open CONFIG, "> imconfig.h"
    or die "Cannot create imconfig.h: $!\n";
  print CONFIG <<EOS;
/* This file is automatically generated by Makefile.PL.
   Don't edit this file, since any changes will be lost */

#ifndef IMAGER_IMCONFIG_H
#define IMAGER_IMCONFIG_H
EOS
  for my $define (@$defines) {
    if ($define->[2]) {
      print CONFIG "\n/*\n  $define->[2]\n*/\n\n";
    }
    print CONFIG "#define $define->[0] $define->[1]\n";
  }
  if ($Config{gccversion} && $Config{gccversion} =~ /^([0-9]+)/ && $1 > 3) {
    print CONFIG <<EOS;
/*

Compiler supports the GCC __attribute__((format...)) syntax.

*/

#define IMAGER_FORMAT_ATTR 1

EOS
  }

  if ($Config{d_snprintf}) {
    print CONFIG <<EOS;
/* We can use snprintf() */
#define IMAGER_SNPRINTF 1

EOS
  }

  if ($Config{d_vsnprintf}) {
    print CONFIG <<EOS;
/* We can use vsnprintf() */
#define IMAGER_VSNPRINTF 1

EOS
  }

  print CONFIG <<EOS;
/*
 Type and format code for formatted output as with printf.

 This is intended for formatting i_img_dim values.
*/
typedef $Config{ivtype} i_dim_format_t;
#define i_DF $Config{ivdformat}
EOS

  print CONFIG "\n#endif\n";
  close CONFIG;
}

# probes for freetype1 by scanning @incs for the includes and 
# @libs for the libs.  This is done separately because freetype's headers
# are stored in a freetype or freetype1 directory under PREFIX/include.
#
# we could find the files with the existing mechanism, but it won't set
# -I flags correctly.
#
# This could be extended to freetype2 too, but freetype-config catches
# that
sub freetype1_probe {
  my ($frm, $frmkey) = @_;

  my $found_inc;
 INCS:
  for my $inc (@incs) {
    for my $subdir (qw/freetype freetype1/) {
      my $path = File::Spec->catfile($inc, $subdir, 'freetype.h');
      -e $path or next;
      $path = File::Spec->catfile($inc, $subdir, 'fterrors.h');
      -e $path and next;

      $found_inc = File::Spec->catdir($inc, $subdir);
      last INCS;
    }
  }

  my $found_lib;
 LIBS:
  for my $lib (@libs) {
    my $a_path = File::Spec->catfile($lib, "libttf$aext");
    my $l_path = File::Spec->catfile($lib, "libttf.$lext");
    if (-e $a_path || -e $l_path) {
      $found_lib = $lib;
      last LIBS;
    }
  }

  return unless $found_inc && $found_lib;
  printf("%10s: includes %s - libraries %s\n", $frmkey,
	 ($found_inc ? 'found' : 'not found'), 
	 ($found_lib ? 'found' : 'not found'));

  $frm->{cflags} = "-I$found_inc";
  $frm->{libfiles} = "-lttf";

  return 1;
}

sub catfile {
  return File::Spec->catfile(@_);
}

sub usage {
  print STDERR <<EOS;
Usage: $0 [--enable feature1,feature2,...] [other options]
       $0 [--disable feature1,feature2,...]  [other options]
       $0 --help
Possible feature names are:
  T1-fonts
Other options:
  --verbose | -v
    Verbose library probing (or set IM_VERBOSE in the environment)
  --nolog
    Disable logging (or set IM_NOLOG in the environment)
  --incpath dir
    Add to the include search path
  --libpath dir
    Add to the library search path
  --coverage
    Build for coverage testing.
  --assert
    Build with assertions active.
EOS
  exit 1;

}

# generate the PM MM argument
# I'd prefer to modify the public version, but there doesn't seem to be 
# a public API to do that
sub gen_PM {
  my %pm;
  my $instbase = '$(INST_LIBDIR)';

  # first the basics, .pm and .pod files
  $pm{"Imager.pm"} = "$instbase/Imager.pm";

  my $mani = maniread();

  for my $filename (keys %$mani) {
    if ($filename =~ m!^lib/! && $filename =~ /\.(pm|pod)$/) {
      (my $work = $filename) =~ s/^lib//;
      $pm{$filename} = $instbase . $work;
    }
  }

  # need the typemap
  $pm{typemap} = $instbase . '/Imager/typemap';

  # and the core headers
  for my $filename (keys %$mani) {
    if ($filename =~ /^\w+\.h$/) {
      $pm{$filename} = $instbase . '/Imager/include/' . $filename;
    }
  }

  # and the generated header
  $pm{"imconfig.h"} = $instbase . '/Imager/include/imconfig.h';

  \%pm;
}

my $home;
sub _tilde_expand {
  my ($path) = @_;

  if ($path =~ m!^~[/\\]!) {
    defined $home or $home = $ENV{HOME};
    if (!defined $home && $^O eq 'MSWin32'
       && defined $ENV{HOMEDRIVE} && defined $ENV{HOMEPATH}) {
      $home = $ENV{HOMEDRIVE} . $ENV{HOMEPATH};
    }
    unless (defined $home) {
      $home = eval { (getpwuid($<))[7] };
    }
    defined $home or die "You supplied $path, but I can't find your home directory\n";
    $path =~ s/^~//;
    $path = File::Spec->catdir($home, $path);
  }

  $path;
}

1;
