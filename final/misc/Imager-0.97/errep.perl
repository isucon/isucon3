#!perl -w
use strict;

use Config;

my @precommands=('uname -a','perl -V');
my @manpages=('dlopen','shl_load','dlsym','dlclose');
my @postcommands=map { "man $_ | col -bf | cat -s" } @manpages;

print <<EOF;

  This script will gather information about your system in order to
  help debugging the problem compiling or testing Imager on your
  system.

  Make sure that you are in the same directory as errep.perl is when
  running the script.  Also make sure that the environment variables
  are the same as when running perl Makefile.PL

  It issues: uname -a, perl -V and gets the %Config hash from the
  build of the perl binary.  Then it tries to build and test the
  module (but not install it).  It dumps out the test logs if there
  are any.  It ends by dumping out some manpages.

  All the results are saved to the file 'report.txt'

  Continue [Y/n]?

EOF

my $a=<STDIN>;
chomp($a);
die "Aborted!\n" if $a =~ /^n/i;

print "Generating info about system\n";

open OSTD, '>&STDOUT' or die $!;
open STDOUT, '>report.txt' or die $!;
open STDERR, '>&STDOUT' or die $!;

rcomm('rm testout/*');
rcomm(@precommands);
my $make = $Config{make};
rcomm("$^X Makefile.PL --verbose") || rcomm("$make") || rcomm("$make test TEST_VERBOSE=1");
head("Logfiles from run");
dumplogs();

pconf();
rcomm(@postcommands);

sub pconf {
    head("perl Config parameters");
    for(sort keys %Config) {  print $_,"=>",(defined $Config{$_} ? $Config{$_} : '(undef)'),"\n"; }
    print "\n";
}


sub rcomm {
    my @commands=@_;
    my ($comm,$R);
    for $comm(@commands) {
	print "Executing '$comm'\n";
	print OSTD "Executing '$comm'\n";
	$R=system($comm);
	print "warning - rc=$R\n" if $R;
	print "=====================\n\n";
    }
    return $R;
}

sub head {
    my $h=shift;
    print "=========================\n";
    print $h;
    print "\n=========================\n";
}

sub dumplogs {
    opendir(DH,"testout") || die "Cannot open dir testout: $!\n";
    my @fl=sort grep(/\.log$/,readdir(DH));

    for my $f (@fl) {
	print "::::::::::::::\ntestout/$f\n::::::::::::::\n";
 	open(FH,"testout/$f") || warn "Cannot open testout/$f: $!\n";
	print while(<FH>);
	close(FH);
    }
}










