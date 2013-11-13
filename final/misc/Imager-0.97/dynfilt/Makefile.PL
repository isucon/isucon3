use strict;
use Config;
use ExtUtils::MakeMaker;
my $Verbose = 1;

my $lddl=$Config{"lddlflags"};

my @plugins= qw(dyntest dt2 mandelbrot flines);

my $libstr=join(' ',map { $_.'.$(SO)' } @plugins);

#print $libstr,"\n";
#print $objstr,"\n";
#print MY::top_targets();

WriteMakefile(
    NAME      => 'Imager::plugins',
    SKIP      => [qw(all dynamic static )],
    clean     => {'FILES' => $libstr},
);




sub lddl_magic {
  my $t;
  $t=$lddl;
  $t=~s/-bI:\$\(PERL_INC\)\/perl.exp//;
  $t=~s/\$\(BASEEXT\)/$_[0]/;
  return $t;
}




sub MY::top_targets {
    use Config;
if ($^O eq 'aix') {
        '
all :: dynamic

dynamic ::       '.$libstr.(join("\n",map { qq{

$_.\$(SO): $_\$(OBJ_EXT)
	LD_RUN_PATH="\$(LD_RUN_PATH)" \$(LD) -o \$\@ }.lddl_magic($_).qq{ \$(OTHERLDFLAGS) $_\$(OBJ_EXT)

} } @plugins)).'


pure_all :: 
	$(NOOP)

';

}
elsif ($^O =~ /win32/i && $Config{cc} =~ /cl/) {
  my @libpth = grep /\S/, split /("[^"]*"|\S+)/,$Config{libpth};
        '
all :: dynamic

dynamic :: '.$libstr.(join("\n",map { qq{

$_.\$(SO): $_\$(OBJ_EXT)
    \$(LD) /OUT:\$\@ }.lddl_magic($_).qq{ \$(OTHERLDFLAGS) $_\$(OBJ_EXT) $Config{libs} }.join(' ', map "/libpath:$_", @libpth).qq{

} } @plugins)).'


pure_all :: 
	$(NOOP)

';

} else {
  my $ldrun = $^O =~ /win32/i ? '' : 'LD_RUN_PATH="$(LD_RUN_PATH)"';
  my $phony_colon = $Config{make} eq 'dmake' ? ':' : '::';
    
        "
all $phony_colon dynamic

dynamic $phony_colon ".$libstr.(join("\n",map { qq{

$_.\$(SO): $_\$(OBJ_EXT)
	$ldrun \$(LD) -o \$\@ \$(LDDLFLAGS) \$(OTHERLDFLAGS) $_\$(OBJ_EXT)

} } @plugins)).'


pure_all :: 
	$(NOOP)

';

}
}

# EU::MM crashes without this when we define it in the base Makefile.PL
# but then warns about redefinition, so delete the GLOB entry
BEGIN { delete $MY::{metafile} }
sub MY::metafile {
  '';
}
