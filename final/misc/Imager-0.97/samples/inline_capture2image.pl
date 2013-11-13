#!perl -w
use strict;
use Imager;

# this is just to exercise the code, see the capture2image
# function below for the meat
my $from = shift;

my $to = shift;

my $width = shift || 320;

my $height = shift || 240;

$to or die "Usage: $0 from to [width [height]]\n";

my $data;
open RAWVIDEO, "< $from"
  or die "Cannot open $from: $!\n";
binmode RAWVIDEO;
$data = do { local $/; <RAWVIDEO> };
close RAWVIDEO;

length $data >= $width * $height * 3
  or die "Not enough data for video frame\n";

my $im = Imager->new(xsize=>$width, ysize=>$height);

capture2image($im, $data);

$im->write(file=>$to)
  or die "Cannot save $to: $!\n";

use Inline C => <<'EOS' => WITH => 'Imager';
void
capture2image(Imager::ImgRaw out, unsigned char *data) {
  i_color *line_buf = mymalloc(sizeof(i_color) * out->xsize);
  i_color *pixelp;
  int x, y;
  
  for (y = 0; y < out->ysize; ++y) {
    pixelp = line_buf;
    for (x = 0; x < out->xsize; ++x) {
      pixelp->rgba.b = *data++;
      pixelp->rgba.g = *data++;
      pixelp->rgba.r = *data++;
      ++pixelp;
    }
    i_plin(out, 0, out->xsize, y, line_buf);
  }

  myfree(line_buf);
}
EOS

__END__

=head1 NAME

inline_capture2image.pl - convert captured C<BGR> data to any Imager supported format

=head1 SYNOPSIS

  perl inline_capture2image.pl rawbgr foo.ext
  perl inline_capture2image.pl rawbgr foo.ext width
  perl inline_capture2image.pl rawbgr foo.ext width height

=head1 DESCRIPTION

This was inspired by the discussion at
http://www.perlmonks.org/?node_id=539316 (Feeding video data to
Imager).

inline_capture2image.pl takes V4L raw captured image data and outputs
an image in any image format supported by Imager.

=head1 SEE ALSO

Imager, Imager::API

Perl and Video Capture
http://www.perlmonks.org/?node=474047

Feeding video data to Imager
http://www.perlmonks.org/?node_id=539316

=head1 AUTHOR

Tony Cook <tonyc@cpan.org>

=head1 REVISION

$Revision$

=cut
