#!perl -w
# takes spot function and builds an ordered dither 8x8 matrix
use strict;
my $func = shift or die "Usage: $0 function [width height expandx expandy]\n";
my $width = shift || 8;
my $height = shift || 8;
my @spot;
use vars qw($x $y);
for $y (0..$height-1) {
  for $x (0..$width-1) {
    my $res = eval $func;
    $spot[$x+$y*$width] = $res * $res;
  }
}
my @sp;
@sp[sort { $spot[$a] <=> $spot[$b] } (0.. $#spot)] = 0..$#spot;

while (@sp) {
  print "   ",map(sprintf("%4d,", 4*$_), splice(@sp, 0, $width)),"\n";
}

sub min {
  my (@data) = @_;
  my $min = shift @data;
  for (@data) {
    $min = $_ if $_ < $min;
  }
  $min;
}

sub dist {
  my ($x1, $y1) = @_;
  return ($x1-$x)*($x1-$x) + ($y1-$y)*($y1-$y);
}

sub theta {
  my ($x1, $y1) = @_;

  return atan2($y1-$y, $x1-$x);
}

sub dt {
  my ($x1, $y1) = @_;
  dist($x1, $y1)+theta($x1,$y1)/20;
}
