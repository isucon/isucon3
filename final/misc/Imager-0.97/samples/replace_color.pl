#!perl -w
use strict;
use Imager;

=head1 NAME

replace_color - replace one color with another in an image

=head1 SYNOPSIS

  perl replace_color fromcolor tocolor inimage outimage

=head1 DESCRIPTION

This is a simple demonstration of Imager::transform2 that replaces one
color with another in an image.

Note: this works with full color images, and always produces a 3
channel output image - the alpha channel (if any) is not preserved.

Most of the work is done in the replace_color() function.

=over

=cut

# extract parameters
my $from = shift;

my $to = shift;

my $in = shift;

my $out = shift
  or die "Usage: $0 fromcolor tocolor inimage outimage\n";

# convert the colors into objects
my $from_color = Imager::Color->new($from)
  or die "Cannot convert fromcolor $from into a color: ", Imager->errstr, "\n";

my $to_color = Imager::Color->new($to)
  or die "Cannot convert tocolor $to into a color: ", Imager->errstr, "\n";

# do the work
my $img = Imager->new;
$img->read(file=>$in)
  or die "Cannot read image $in: ", $img->errstr, "\n";

my $result = replace_color($img, $from_color, $to_color)
  or die "Cannot replace colors: ", Imager->errstr, "\n";

$result->write(file=>$out)
  or die "Cannot write image $out: ", $result->errstr, "\n";

=item replace_color

Called:

  my $result = replace_color($in_image, $from_color, $to_color);

Returns a new image object with colors replaced.

=cut

sub replace_color {
  my ($img, $from_color, $to_color) = @_;

  my ($from_red, $from_green, $from_blue) = $from_color->rgba;
  my ($to_red, $to_green, $to_blue) = $to_color->rgba;
  my $rpnexpr = <<'EOS';
# get the pixel
x y getp1 !pix
# check against the from_color
@pix red from_red eq
@pix green from_green eq
@pix blue from_blue eq
and and
# pick a result
to_red to_green to_blue rgb @pix ifp
EOS
  # rpnexpr doesn't really support comments - remove them
  $rpnexpr =~ s/^#.*\n//mg; 
  my %constants =
    (
     from_red => $from_red,
     from_green => $from_green,
     from_blue => $from_blue,
     to_red => $to_red,
     to_green => $to_green,
     to_blue => $to_blue,
    );
  return Imager::transform2({ rpnexpr => $rpnexpr,
			      constants => \%constants },
			    $img);
}

__END__

=back

=head1 REVISION

$Revision$

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=head1 SEE ALSO

Imager, Imager::Engines, Imager::Color, Imager::Files

=cut
