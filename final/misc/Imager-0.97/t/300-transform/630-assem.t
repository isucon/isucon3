#!perl -w
use strict;
use Test::More tests => 6;

BEGIN { use_ok('Imager::Expr::Assem') }

SKIP:
{
  my $expr = Imager::Expr->new
    ({assem=><<EOS,
	var count:n ; var p:p
	count = 0
	p = getp1 x y
loop:
# this is just a delay
	count = add count 1
	var temp:n
	temp = lt count totalcount
	jumpnz temp loop
	ret p
EOS
      variables=>[qw(x y)],
      constants=>{totalcount=>5}
     });
  ok($expr, "compile simple assembler")
    or do {
      print "# ", Imager::Expr->error, "\n";
      skip("didn't compile", 4);
    };
  my $code = $expr->dumpcode();
  my @code = split /\n/, $code;
  ok($code[-1] =~ /:\s+ret/, "last op is a ret");
  ok($code[0] =~ /:\s+set/, "first op is a set");
  ok($code[1] =~ /:\s+getp1/, "next is a getp1");
  ok($code[3] =~ /:\s+lt/, "found comparison");
}
