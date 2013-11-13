#!perl -w
use strict;
use Imager;

my $in0_name = shift;
my $in1_name = shift;
my $out_name = shift
  or usage();

my $in0 = Imager->new;
$in0->read(file=>$in0_name)
  or die "Cannot load $in0_name: ", $in0->errstr, "\n";

my $in1 = Imager->new;
$in1->read(file=>$in1_name)
  or die "Cannot load $in1_name: ", $in1->errstr, "\n";

$in0->getwidth == $in1->getwidth
  && $in0->getheight == $in1->getheight
  or die "Images must be the same width and height\n";

$in0->getwidth == $in1->getwidth
  or die "Images must have the same number of channels\n";

my $out = interleave_images3($in0, $in1);

$out->write(file=>$out_name)
  or die "Cannot write $out_name: ", $out->errstr, "\n";

sub usage {
  print <<EOS;
Usage: $0 even_image odd_image out_image
EOS
  exit;
}

# this one uses transform2()
# see perldoc Imager::Engines
sub interleave_images {
  my ($even, $odd) = @_;

  my $width = $even->getwidth;
  my $height = 2 * $even->getheight;
  my $expr = <<EXPR; # if odd get pixel from img2[x,y/2] else from img1[x,y/2]
y 2 % x y 2 / getp2 x y 2 / getp1 ifp
EXPR
  my $out = Imager::transform2
    ({ 
      rpnexpr=>$expr, 
      width =>$width, 
      height=>$height 
     },
     $even, $odd) or die Imager->errstr;

  $out;
}

# i_copyto()
# this should really have been possible through the paste method too,
# but the paste() interface is too limited for this
# so we call i_copyto() directly
# http://rt.cpan.org/NoAuth/Bug.html?id=11858
# the code as written here does work though
sub interleave_images2 {
  my ($even, $odd) = @_;

  my $width = $even->getwidth;
  my $out = Imager->new(xsize=>$width, ysize=>2 * $even->getheight,
			channels => $even->getchannels);

  for my $y (0 .. $even->getheight-1) {
    Imager::i_copyto($out->{IMG}, $even->{IMG}, 0, $y, $width, $y+1,
		     0, $y*2);
    Imager::i_copyto($out->{IMG}, $odd->{IMG}, 0, $y, $width, $y+1,
		     0, 1+$y*2);
  }

  $out;
}

# this version uses the internal i_glin() and i_plin() functions
# as of 0.44 the XS for i_glin() has a bug in that it doesn't copy
# the returned colors into the returned color objects
# http://rt.cpan.org/NoAuth/Bug.html?id=11860
sub interleave_images3 {
  my ($even, $odd) = @_;

  my $width = $even->getwidth;
  my $out = Imager->new(xsize=>$width, ysize=>2 * $even->getheight,
			channels => $even->getchannels);

  for my $y (0 .. $even->getheight-1) {
    my @row = Imager::i_glin($even->{IMG}, 0, $width, $y);
    Imager::i_plin($out->{IMG}, 0, $y*2, @row);

    @row = Imager::i_glin($odd->{IMG}, 0, $width, $y);
    Imager::i_plin($out->{IMG}, 0, 1+$y*2, @row);
  }

  $out;
}

=head1 NAME

interleave.pl - given two identically sized images create an image twice the height with interleaved rows from the source images.

=head1 SYNOPSIS

  perl interleave.pl even_input odd_input output

=head1 DESCRIPTION

This sample produces an output image with interleaved rows from the
two input images.

Multiple implementations are included, including two that revealed
bugs or limitations in Imager, to demonstrate some different
approaches.

See http://www.3dexpo.com/interleaved.htm for an example where this
might be useful.

=head1 AUTHOR

Tony Cook <tonyc@cpan.org>

=for stopwords Oppenheim

Thanks to Dan Oppenheim, who provided the impetus for this sample.

=head1 REVISION

$Revision$

=cut
