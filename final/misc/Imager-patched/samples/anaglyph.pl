#!perl -w
use strict;
use Imager;
use Getopt::Long;

my $grey;
my $pure;
my $green;

GetOptions('grey|gray|g'=>\$grey,
	   'pure|p' => \$pure,
	   'green' => \$green);

if ($grey && $pure) {
  die "Only one of --grey or --pure can be used at a time\n";
}

my $left_name = shift;
my $right_name = shift;
my $out_name = shift
  or usage();

my $left = Imager->new;
$left->read(file=>$left_name)
  or die "Cannot load $left_name: ", $left->errstr, "\n";

my $right = Imager->new;
$right->read(file=>$right_name)
  or die "Cannot load $right_name: ", $right->errstr, "\n";

$left->getwidth == $right->getwidth
  && $left->getheight == $right->getheight
  or die "Images must be the same width and height\n";

$left->getwidth == $right->getwidth
  or die "Images must have the same number of channels\n";

my $out;
if ($grey) {
  $out = grey_anaglyph($left, $right);
}
elsif ($pure) {
  $out = pure_anaglyph($left, $right, $green);
}
else {
  $out = anaglyph_images($left, $right);
}

$out->write(file=>$out_name, jpegquality => 100)
  or die "Cannot write $out_name: ", $out->errstr, "\n";

sub usage {
  print <<EOS;
Usage: $0 left_image right_image out_image
EOS
  exit;
}

sub anaglyph_images {
  my ($left, $right) = @_;

  my $expr = <<'EXPR'; # get red from $left, green, blue from $right
x y getp1 red x y getp2 !pix @pix green @pix blue rgb
EXPR
  my $out = Imager::transform2 ({ rpnexpr=>$expr, }, $left, $right) 
    or die Imager->errstr;

  $out;
}

sub grey_anaglyph {
  my ($left, $right) = @_;

  $left = $left->convert(preset=>'grey');
  $right = $right->convert(preset=>'grey');

  my $expr = <<'EXPR';
x y getp1 red x y getp2 red !right @right @right rgb
EXPR

  return Imager::transform2({ rpnexpr=>$expr }, $left, $right);
}

sub pure_anaglyph {
  my ($left, $right, $green) = @_;

  $left = $left->convert(preset=>'grey');
  $right = $right->convert(preset=>'grey');

  my $expr;
  if ($green) {
    # output is rgb(first channel of left, first channel of right, 0)
    $expr = <<'EXPR'
x y getp1 red x y getp2 red 0 rgb
EXPR
  }
  else {
    # output is rgb(first channel of left, 0, first channel of right)
    $expr = <<'EXPR';
x y getp1 red 0 x y getp2 red rgb
EXPR
}

  return Imager::transform2({ rpnexpr=>$expr }, $left, $right);
}


=head1 NAME

=for stopwords anaglyph anaglyph.pl

anaglyph.pl - create a anaglyph from the source images

=head1 SYNOPSIS

  # color anaglyph
  perl anaglyph.pl left_input right_input output

  # grey anaglyph
  perl anaglyph.pl -g left_input right_input output
  perl anaglyph.pl --grey left_input right_input output
  perl anaglyph.pl --gray left_input right_input output

  # pure anaglyph (blue)
  perl anaglyph.pl -p left_input right_input output
  perl anaglyph.pl --pure left_input right_input output

  # pure anaglyph (green)
  perl anaglyph.pl -p --green left_input right_input output
  perl anaglyph.pl --pure --green left_input right_input output

=head1 DESCRIPTION


See http://www.3dexpo.com/anaglyph.htm for an example where this might
be useful.

Implementation based on the description at
http://www.recordedlight.com/stereo/tutorials/ps/anaglyph/pstut04.htm
though obviously the interactive component is missing.

=head1 CAVEAT

Using JPEG as the output format is not recommended.

=head1 AUTHOR

Tony Cook <tonyc@cpan.org>

=for stopwords Oppenheim

Thanks to Dan Oppenheim, who provided the impetus for this sample.

=head1 REVISION

$Revision$

=cut
