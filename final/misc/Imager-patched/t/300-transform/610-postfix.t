#!perl -w
use strict;
use Test::More tests => 6;
BEGIN { use_ok('Imager::Expr') }

SKIP:
{
  my $expr = Imager::Expr->new({rpnexpr=><<EXPR, variables=>[ qw(x y) ], constants=>{one=>1, two=>2}});
x two * # see if comments work
y one + 
getp1
EXPR
  ok($expr, "compile postfix")
    or print "# ", Imager::Expr->error, "\n";
  $expr
    or skip("Could not compile", 4);

  # perform some basic validation on the code
  my $code = $expr->dumpcode();
  my @code = split /\n/, $code;
  ok($code[-1] =~ /:\s+ret/, "ret at the end");
  ok(grep(/:\s+mult.*x/, @code), "found mult");
  ok(grep(/:\s+add.*y/, @code), "found add");
  ok(grep(/:\s+getp1/, @code), "found getp1");
}
