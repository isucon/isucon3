#!perl -w
use strict;
use Imager;
use Imager::Matrix2d;
use Getopt::Long;
use constant PI => 4 * atan2(1,1);

# this sample requires Freetype 2.x
$Imager::formats{"ft2"}
  or die "This sample require Freetype 2.x to be configured in Imager\n";

Getopt::Long::Configure("bundling");

my $angle = 30;
my $fg = 'white';
my $bg = 'black';
my $size = 20;
my $rotate;
GetOptions('angle|a=f' => \$angle,
	   'size|s=i' => \$size,
	   'foreground|fg|f=s' => \$fg,
	   'background|bg|b=s' => \$bg,
	   'rotate|r' => \$rotate)
  or usage();

# check for sanity
if ($angle < -45 or $angle > 45) {
  # while values outside this range are valid, the text would be hard
  # to read
  die "--angle is limited to the range -45 through +45\n";
}
elsif ($size < 10) {
  die "--size must be 10 or greater\n";
}

my $fontfile = shift;
my $outfile = shift;
@ARGV
  or usage();
my $text = "@ARGV";

my $angle_rads = $angle * (PI / 180);
my $trans;

# this is the only difference between rotation and shearing: the
# transformation matrix
if ($rotate) {
  $trans = Imager::Matrix2d->rotate(radians => $angle_rads);
}
else {
  $trans = Imager::Matrix2d->shear(x=>sin($angle_rads)/cos($angle_rads));
}

# only the Freetype 2.x driver supports transformations for now
my $font = Imager::Font->new(file=>$fontfile, type=>'ft2')
  or die "Cannot load font $fontfile: ", Imager->errstr, "\n";

$font->transform(matrix=>$trans);

my $bbox = $font->bounding_box(string=>$text, size=>$size);

# these are in font co-ordinates, so y is flipped
my ($left, $miny, $right, $maxy) =
  transformed_bounds($bbox, $trans);

# convert to image relative co-ordinates
my ($top, $bottom) = (-$maxy, -$miny);

my ($width, $height) = ($right - $left, $bottom - $top);

my $img = Imager->new(xsize=>$width, ysize=>$height);

# fill with the background
$img->box(filled=>1, color=>$bg);

# and draw our string in the right place
$img->string(text => $text,
	     color => Imager::Color->new('white'),
	     x => -$left,
	     y => -$top,
	     color => $fg,
	     font => $font,
	     size => $size);

$img->write(file=>$outfile)
  or die "Cannot save $outfile: ",$img->errstr,"\n";

sub transformed_bounds {
  my ($bbox, $matrix) = @_;

  my $bounds;
  for my $point ([ $bbox->start_offset, $bbox->ascent  ],
		 [ $bbox->start_offset, $bbox->descent ],
		 [ $bbox->end_offset,   $bbox->ascent  ],
		 [ $bbox->end_offset,   $bbox->descent ]) {
    $bounds = add_bound($bounds, transform_point(@$point, $matrix));
  }

  @$bounds;
}

sub transform_point {
  my ($x, $y, $matrix) = @_;

  return
    (
     $x * $matrix->[0] + $y * $matrix->[1] + $matrix->[2],
     $x * $matrix->[3] + $y * $matrix->[4] + $matrix->[5]
    );
}

sub add_bound {
  my ($bounds, $x, $y) = @_;

  $bounds or return [ $x, $y, $x, $y ];

  $x < $bounds->[0] and $bounds->[0] = $x;
  $y < $bounds->[1] and $bounds->[1] = $y;
  $x > $bounds->[2] and $bounds->[2] = $x;
  $y > $bounds->[3] and $bounds->[3] = $y;

  $bounds;
}

sub usage {
  print <<EOS;
Usage: $0 [options] fontfile outfile text...
Options:
  --angle <angle> | -a <angle>
    Set the slant angle in degrees, limited to -45 to +45.  Default 30.
  --size <pixels> | -s <angle>
    Set the text size in pixels.  Must be 10 or greater. Default: 20.
  --foreground <color> | --fg <color> | -f <color>
    Set the text foreground color.  Default: white.
  --background <color> | --bg <color> | -b <color>
    Set the image background color.  Default: black
  --rotate | -r
    Rotate instead of shearing.  Default: shear

eg.
  # shear
  $0 -a 45 fontfiles/ImUgly.ttf output.ppm "something to say"
  # rotate at 100 pixel font size, blue foregroune, white background
  $0 -rs 100 -b white -f blue fontfiles/ImUgly.ttf output.ppm Imager
EOS
  exit 1;
}

=head1 NAME

slant_text.pl - sample for drawing transformed text

=head1 SYNOPSIS

  perl slant_text.pl [options] fontfile output text

  Run without arguments for option details.

=head1 DESCRIPTION

This is a sample for drawing transformed text.

It's complicated by the need to create an image to put the text into,
if you have text, a font, and a good idea where it belongs, it's
simple to create the transformation matrix:

  use Imager::Matrix2d;
  # or call another method for shearing, etc
  my $matrix = Imager::Matrix2d->rotate(radians=>$some_angle);

Feed the transformation matrix to the font:

  $font->transform(matrix=>$font);

then draw the text as normal:

  $image->string(string=>$some_text,
                 x => $where_x,
                 y => $where_y,
                 font => $font,
                 size => $size);

But if you do need the bounds, the code above does show you how to do
it.

=head1 FUNCTIONS

=over

=item transformed_bounds

Returns a list of bounds:

  (minx, miny, maxx, maxy)

These are offsets from the text's starting point in font co-ordinates
- so positive y is I<up>.

Note: this returns the bounds of the transformed bounding box, in most
cases the actual text will not be touching these boundaries.

=cut

=back

=head1 AUTHOR

Tony Cook <tonyc@cpan.org>

=head1 REVISION

$Revision$

=head1 SEE ALSO

Imager(1), Imager::Cookbook, Imager::Matrix2d

=cut
