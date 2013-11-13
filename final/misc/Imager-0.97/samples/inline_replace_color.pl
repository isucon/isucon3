#!perl -w
use strict;
use Imager;

=head1 NAME

=for stopwords Inline

inline_replace_color.pl - replace one color with another in an image, using Inline

=head1 SYNOPSIS

  perl inline_replace_color.pl fromcolor tocolor inimage outimage

  perl inline_replace_color.pl white 808080 foo.jpg bar.png

=head1 DESCRIPTION

This is a simple demonstration of using Imager with Inline::C to
replace one color in an image with another.

Most of the work is done in the inline_replace_color() function.

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

# unlike the transform2() version this works in place
inline_replace_color($img, $from_color, $to_color);

$img->write(file=>$out)
  or die "Cannot write image $out: ", $img->errstr, "\n";

=item inline_replace_color

Called:

  inline_replace_color($in_image, $from_color, $to_color);

Returns a new image object with colors replaced.

=cut

use Inline C => <<'EOS' => WITH => 'Imager';
void
inline_replace_color(Imager::ImgRaw img, Imager::Color from, Imager::Color to) {
  int x, y, ch;
  i_color c;

  for (x = 0; x < img->xsize; ++x) {
    for (y = 0; y < img->ysize; ++y) {
      int match = 1;
      i_gpix(img, x, y, &c);
      for (ch = 0; ch < img->channels; ++ch) {
        if (c.channel[ch] != from->channel[ch]) {
          match = 0;
          break;
        }
      }
      if (match)
        i_ppix(img, x, y, to);
    }
  }
}
EOS

__END__

=back

=head1 REVISION

$Revision: 816 $

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=head1 SEE ALSO

Imager, Imager::Inline, Imager::API, Imager::Color, Imager::Files

=cut
