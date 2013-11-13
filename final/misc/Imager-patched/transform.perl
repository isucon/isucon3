#!perl -w
use strict;
use Imager;
use Imager::Transform;

my %opts;
my @in;
my $expr;
my $func;
my $out;
my %con;
my $numre = Imager::Expr->numre;
while (defined(my $arg = shift)) {
  if ($arg =~ /^-/) {
    if ($arg eq '-g') {
      my $work = shift or die "$0: argument missing for -g\n";
      if ($work =~ /^(\d+)x(\d+)?$/) {
	$opts{width} = $1;
	$opts{height} = $2 if defined $2;
      }
      elsif ($work =~ /^x(\d+)$/) {
	$opts{height} = $2;
      }
      else {
	die "$0: invalid geometry supplied to -g\n";
      }
    }
    elsif ($arg eq '-f') {
      $func = shift or die "$0: argument missing for -f\n";
      $expr = Imager::Transform->new($func)
	or die "$0: unknown transformation $func\n";
    }
    elsif ($arg eq '-d') {
      my $func = shift or die "$0: argument missing for -d\n";
      my $desc = Imager::Transform->describe($func)
	  or die "$0: unknown transformation $func\n";
      print $desc;
      exit;
    }
    elsif ($arg eq '-l') {
      print join("\n", sort Imager::Transform->list),"\n";
      exit;
    }
    elsif ($arg eq '-o') {
      $out = shift or die "$0: argument missing for -o\n";
    }
    elsif ($arg eq '--') {
      push(@in, @ARGV);
      last;
    }
    else {
      die "$0: Unknown option $arg\n";
    }
  }
  else {
    if ($arg =~ /^([^\W\d]\w*)=($numre)$/) {
      exists $con{$1} 
	and die "$0: constant $1 already defined\n";
      $con{$1} = $2;
    }
    else {
      push(@in, $arg);
    }
  }
}

$expr or usage();
$expr->inputs <= @in
  or die "$0: not enough input images specified for $func\n";

for my $in (@in) {
  my $im = Imager->new();
  $im->read(file=>$in)
    or die "Cannot read $in: ",$im->errstr,"\n";
  $in = $im;
}

defined $out or $out = $func.".jpg";

$opts{jpegquality} = 100;
my $im = $expr->transform(\%opts, \%con, @in)
  or die "$0: error transforming: ",$expr->errstr,"\n";

$im->write(file=>$out, jpegquality=>100)
  or die "0: Cannot write $out: ",$im->errstr,"\n";


sub usage {
  print <<EOS;
Usage: $0 -f <func> <constant>=<value> ... <input-image>...
       $0 -l
       $0 -d <func>
 -f <func>  - function to evaluate
 -l         - list function names
 -d <func>  - describe <func>
 -g <digits>x<digits> - dimensions of output image
 -o <file>  - output file
EOS
  exit
}
