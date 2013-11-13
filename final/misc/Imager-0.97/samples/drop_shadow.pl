#!perl
use strict;
use Imager;
use Getopt::Long;

my $bg;
my $shadow_size = "10%";
my $offset = "0x0";
my $shadow_color = "#404040";

GetOptions(
	   "bg=s" => \$bg,
	   "size|s=s" => \$shadow_size,
	   "o|offset=s" => \$offset,
	   "s|shadow=s" => \$shadow_color,
	   );

my $infile = shift;
my $outfile = shift
  or die <<EOS;
Usage: $0 [options] infile outfile
Options can be any or all of:
 -bg color - fill the background with a color instead of using
             transparency, this can be a translucent color.
 -size size - size of the shadow in pixels, or percent of min dimension
 -offset <xsize>x<ysize> - offset of the original image within the shadow
 -shadow color - color of the shadow
EOS

my $src = Imager->new(file => $infile)
  or die "Cannot read image file '$infile': ", Imager->errstr, "\n";

# simplify things by always working in RGB rather than grey
$src = $src->convert(preset => "rgb");

if ($shadow_size =~ /^([0-9]+)%$/) {
  my $dim = $src->getwidth < $src->getheight ? $src->getwidth : $src->getheight;

  $shadow_size = int($1 * $dim / 100 + 0.5);
}

my ($x_offset, $y_offset) = $offset =~ /^([+-]?[0-9]+)x([+-]?[0-9]+)$/
  or die "$0: invalid offset\n";

my $shc = Imager::Color->new($shadow_color)
  or die "$0: invalid shadow color: ", Imager->errstr, "\n";

my ($red, $green, $blue) = $shc->rgba;

# First create a new image, either with an alpha channel (if you want
# transparency behind the shadow) or without, if you want a background
# colour:

my $out = Imager->new
  (
   xsize => $shadow_size * 2 + $src->getwidth,
   ysize => $shadow_size * 2 + $src->getheight,
   channels => 4,
  );

if ($bg) {
  # fill it with your background color, if you want one
  my $bgc = Imager::Color->new($bg)
    or die "$0: invalid color '$bg'\n";
  $out->box(filled => 1, color => $bgc);
}

# Make a work image to render the shadow on:
my $shadow_work = Imager->new
  (
   xsize => $out->getwidth,
   ysize => $out->getheight,
   channels => 1,
  );

if ($src->getchannels == 4) {
  # Extract the alpha channel from the source image, if the image has no
  # alpha, then a solid box then it's simpler, first the alpha version:
  my $alpha = $src->convert(preset => "alpha");

  # and draw that on the work shadow:
  $shadow_work->paste
    (
     src => $alpha,
     left => $shadow_size,
     top => $shadow_size,
    );
}
else {
  # otherwise just draw a box for the non-alpha source:

  $shadow_work->box
    (
     filled => 1,
     color => [ 255 ],
     xmin => $shadow_size,
     ymin => $shadow_size,
     xmax => $shadow_size + $src->getwidth() - 1,
     ymax => $shadow_size + $src->getheight() - 1,
    );
}

# Blur the work shadow:

$shadow_work->filter(type => "gaussian", stddev => $shadow_size);

# Convert it to an RGB image with alpha:

$shadow_work = $shadow_work->convert
  (
   matrix => [ [ 0, $red / 255 ],
		[ 0, $green / 255 ],
		[ 0, $blue / 255 ],
		[ 1 ] ]
  ) or die $shadow_work->errstr;

# Draw that on the output image:

$out->rubthrough(src => $shadow_work);

# Draw our original image on the output image, perhaps with an offset:
$out->rubthrough
  (
   src => $src,
   tx => $shadow_size + $x_offset,
   ty => $shadow_size + $y_offset,
  );

$out->write(file => $outfile)
  or die "Cannot write to '$outfile': ", $out->errstr, "\n";


