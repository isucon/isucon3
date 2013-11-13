#!perl -w
use strict;
use Imager;

my $left_name = shift;
my $right_name = shift;
my $out_name = shift
  or die "Usage: $0 left right out\n";

my $left = Imager->new(file => $left_name)
  or die "Cannot read $left_name: ", Imager->errstr, "\n";

my $right = Imager->new(file => $right_name)
  or die "Cannot read $right_name: ", Imager->errstr, "\n";

$left = $left->scale;
$right = $right->scale;

my $steps = 5;

my @cycle;

push @cycle, $left;
my @down;
my @delays = ( 50, ( 10 ) x ($steps-1), 50, ( 10 ) x ($steps-1) );

for my $pos (1 .. $steps-1) {
  my $work = $left->copy;
  $work->compose(src => $right, opacity => $pos/$steps);
  push @cycle, $work;
  unshift @down, $work;
}
push @cycle, $right, @down;


Imager->write_multi({ file => $out_name, gif_delay => \@delays, gif_loop => 0, make_colors => "mediancut", translate => "errdiff" }, @cycle)
  or die "Cannot write $out_name: ", Imager->errstr, "\n";

=head1 NAME

wiggle.pl - wiggle stereoscopy

=head1 SYNOPSIS

  perl wiggle.pl left.jpg right.jpg out.gif

=head1 DESCRIPTION

Produces an animated GIF that displays left, then a blend of four
images leading to right then back again.  The left and right images
are displayed a little longer.

If the left and right images form a stereo pair (and the order doesn't
really matter) the output animated GIF is useful for wiggle
stereoscopy.

=head1 CREDITS

=for stopwords
Oppenheim

Dan Oppenheim <droppenheim@yahoo.com> described the effect and asked
how to implement it.

=head1 AUTHOR

Tony Cook <tonyc@cpan.org>

=cut


