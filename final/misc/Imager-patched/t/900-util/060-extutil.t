#!perl -w
use strict;
use Test::More tests => 6;
use File::Spec;

{ # RT 37353
  local @INC = @INC;

  unshift @INC, File::Spec->catdir('blib', 'lib');
  unshift @INC, File::Spec->catdir('blib', 'arch');
  require Imager::ExtUtils;
  my $path = Imager::ExtUtils->base_dir;
  ok(File::Spec->file_name_is_absolute($path), "check dirs absolute")
    or print "# $path\n";
}

{ # includes
  my $includes = Imager::ExtUtils->includes;
  ok($includes =~ s/^-I//, "has the -I");
  ok(-e File::Spec->catfile($includes, "imext.h"), "found a header");
}

{ # typemap
  my $typemap = Imager::ExtUtils->typemap;
  ok($typemap, "got a typemap path");
  ok(-f $typemap, "it exists");
  open TYPEMAP, "< $typemap";
  my $tm_content = do { local $/; <TYPEMAP>; };
  close TYPEMAP;
  cmp_ok($tm_content, '=~', "Imager::Color\\s+T_PTROBJ",
	 "it seems to be the right file");
}
