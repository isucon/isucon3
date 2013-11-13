#!perl -w
use strict;
use Test::More tests => 23;
use Imager;

BEGIN { use_ok('Imager::Matrix2d', ':handy') }

my $id = Imager::Matrix2d->identity;

ok(almost_equal($id, [ 1, 0, 0,
                       0, 1, 0,
                       0, 0, 1 ]), "identity matrix");
my $trans = Imager::Matrix2d->translate('x'=>10, 'y'=>-11);
ok(almost_equal($trans, [ 1, 0, 10,
                          0, 1, -11,
                          0, 0, 1 ]), "translate matrix");
my $trans_x = Imager::Matrix2d->translate(x => 10);
ok(almost_equal($trans_x, [ 1, 0, 10,
			   0, 1, 0,
			   0, 0, 1 ]), "translate just x");
my $trans_y = Imager::Matrix2d->translate('y' => 11);
ok(almost_equal($trans_y, [ 1, 0, 0,
			   0, 1, 11,
			   0, 0, 1 ]), "translate just y");

my $rotate = Imager::Matrix2d->rotate(degrees=>90);
ok(almost_equal($rotate, [ 0, -1, 0,
                           1, 0,  0,
                           0, 0,  1 ]), "rotate matrix");

my $shear = Imager::Matrix2d->shear('x'=>0.2, 'y'=>0.3);
ok(almost_equal($shear, [ 1,   0.2, 0,
                          0.3, 1,   0,
                          0,   0,   1 ]), "shear matrix");

my $scale = Imager::Matrix2d->scale('x'=>1.2, 'y'=>0.8);
ok(almost_equal($scale, [ 1.2, 0,   0,
                          0,   0.8, 0,
                          0,   0,   1 ]), "scale matrix");

my $custom = Imager::Matrix2d->matrix(1, 0, 0, 0, 1, 0, 0, 0, 1);
ok(almost_equal($custom, [ 1, 0, 0,
                       0, 1, 0,
                       0, 0, 1 ]), "custom matrix");

my $trans_called;
$rotate = Imager::Matrix2d::Test->rotate(degrees=>90, x=>50);
ok($trans_called, "translate called on rotate with just x");

$trans_called = 0;
$rotate = Imager::Matrix2d::Test->rotate(degrees=>90, 'y'=>50);
ok($trans_called, "translate called on rotate with just y");

ok(!Imager::Matrix2d->matrix(), "bad custom matrix");
is(Imager->errstr, "9 coefficients required", "check error");

{
  my @half = ( 0.5, 0, 0,
	       0, 0.5, 0,
	       0, 0, 1 );
  my @quart = ( 0, 0.25, 0,
		1, 0, 0,
		0, 0, 1 );
  my $half_matrix = Imager::Matrix2d->matrix(@half);
  my $quart_matrix = Imager::Matrix2d->matrix(@quart);
  my $result = $half_matrix * $quart_matrix;
  is_deeply($half_matrix * \@quart, $result, "mult by unblessed matrix");
  is_deeply(\@half * $quart_matrix, $result, "mult with unblessed matrix");

  my $half_three = Imager::Matrix2d->matrix(1.5, 0, 0, 0, 1.5, 0, 0, 0, 3);
  is_deeply($half_matrix * 3, $half_three, "mult by three");
  is_deeply(3 * $half_matrix, $half_three, "mult with three");

  {
    # check error handling - bad ref type
    my $died = 
      !eval {
      my $foo = $half_matrix * +{};
      1;
    };
    ok($died, "mult by hash ref died");
    like($@, qr/multiply by array ref or number/, "check message");
  }

  {
    # check error handling - bad array
    $@ = '';
    my $died = 
      !eval {
      my $foo = $half_matrix * [ 1 .. 8 ];
      1;
    };
    ok($died, "mult by short array ref died");
    like($@, qr/9 elements required in array ref/, "check message");
  }

  {
    # check error handling - bad value
    $@ = '';
    my $died = 
      !eval {
      my $foo = $half_matrix * "abc";
      1;
    };
    ok($died, "mult by bad scalar died");
    like($@, qr/multiply by array ref or number/, "check message");
  }
  
}


sub almost_equal {
  my ($m1, $m2) = @_;

  for my $i (0..8) {
    abs($m1->[$i] - $m2->[$i]) < 0.00001 or return undef;
  }
  return 1;
}

# this is used to ensure translate() is called correctly by rotate
package Imager::Matrix2d::Test;
use vars qw(@ISA);
BEGIN { @ISA = qw(Imager::Matrix2d); }

sub translate {
  my ($class, %opts) = @_;

  ++$trans_called;
  return $class->SUPER::translate(%opts);
}

