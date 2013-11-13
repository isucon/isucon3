#!perl -w
use strict;
use Test::More tests => 7;

BEGIN { use_ok('Imager::Expr') }

# only test this if Parse::RecDescent was loaded successfully
SKIP:
{
  Imager::Expr->type_registered('expr')
      or skip("Imager::Expr::Infix not available", 6);

  my $opts = {expr=>'z=0.8;return hsv(x/w*360,y/h,z)', variables=>[ qw(x y) ], constants=>{h=>100,w=>100}};
  my $expr = Imager::Expr->new($opts);
  ok($expr, "make infix expression")
    or skip("Could not make infix expression", 5);
  my $code = $expr->dumpcode();
  my @code = split /\n/,$code;
  #print $code;
  ok($code[-1] =~ /:\s+ret/, "final op a ret");
  ok(grep(/:\s+mult.*360/, @code), "mult by 360 found");
  # strength reduction converts these to mults
  #print grep(/:\s+div.*x/, @code) ? "ok 5\n" : "not ok 5\n";
  #print grep(/:\s+div.*y/, @code) ? "ok 6\n" : "not ok 6\n";
  ok(grep(/:\s+mult.*x/, @code), "mult by x found");
  ok(grep(/:\s+mult.*y/, @code), "mult by y found");
  ok(grep(/:\s+hsv.*0\.8/, @code), "hsv op found");
}
