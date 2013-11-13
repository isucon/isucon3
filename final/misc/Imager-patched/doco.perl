#!/usr/bin/perl -w
use strict;

use Cwd;

# doco.perl - 24 Jan 18:09:40 EST 2001
#   Addi - (addi@umich.edu)
#
# Extract documentation and help from the source files
# 
#   -f <files> list FIXME comments for files
#   -f         list FIXME comments for all files
#   -d <file>  list pod comments from file

my $comm = shift or USAGE();

my @files;
if ($comm eq "-f") {
	if (@ARGV) {
		@files = @ARGV;
	}
	else {
		@files = getfiles();
	}

	for my $file (@files) {
		local(*FH, $/); open(FH,"< $file") or die $!;
		my $data = <FH>; close(FH);
		while( $data =~ m/FIXME:(.*?)\*\//sg ) {
			printf("%10.10s:%5d %s\n", $file, ptol($data, pos($data)), $1);
		}
	}
	exit(0);
}

if ($comm eq "-d") {
	USAGE() if !@ARGV;
	my $file = shift; 
	getfiles();
	local(*FH, $/); open(FH, "< $file") or die $!;
	my $data = <FH>; close(FH);
	$data =~ s/^(=item)/\n$1/mg;
	$data =~ s/^(=cut)/\n~~~~~~~~\n\n$1\n\n/mg;
	print "\n";
	open(FH,"|pod2text ") or die "Cannot run pod2text: $!\n";
	print FH $data;
	close(FH);
	exit(2);
}


sub USAGE {

print<<'EOF';
doco.perl [-f files| stuff]

  -f <files> list FIXME comments for files.
  -f         list FIXME comments for all files.

EOF
	exit;
}

sub getfiles {
	my $BASE=cwd;
	local(*FH);
	open(FH,"$BASE/MANIFEST") or die "Cannot open MANIFEST file: $!\n";
	my @MANIFEST = <FH>;
	chomp(@MANIFEST);
	return grep { m/\.(c|im)\s*$/ } @MANIFEST;
}

# string position to line number in string

sub ptol {
	my ($str, $pos) = @_;
	my $lcnt=1;
	$lcnt++ while(substr($str,0,$pos)=~m/\n/g);
	$lcnt;
}
