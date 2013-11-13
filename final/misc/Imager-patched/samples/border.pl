#!perl -w
use strict;
use Imager;
use Imager::Fountain;
use Getopt::Long;

Getopt::Long::Configure("bundling");

# see usage() for a description of the parameters we accept
my $border_width = 10;
my $border_height = 10;
my $border_thickness; # sets width and height and overrides them
my $fountain;
my $color = 'red';
GetOptions('width|w=i' => \$border_width,
	   'height|h=i' => \$border_height,
	   'thickness|t=i' => \$border_thickness,
	   'fountain|f=s' => \$fountain,
	   'color|c=s' => \$color)
  or usage();

# make sure we got sane values
if (defined $border_thickness) {
  if ($border_thickness <= 0) {
    die "--thickness must be positive\n";
  }
  $border_width = $border_height = $border_thickness;
}
elsif ($border_width < 0) {
  die "--width must non-negative\n";
}
elsif ($border_height < 0) {
  die "--height must be non-negative\n";
}
elsif ($border_width == 0 && $border_height == 0) {
  # not much point if both are zero
  die "One of --width or --height must be positive\n";
}

my $src_name = shift;
my $out_name = shift
  or usage();

# treat extras as an error
@ARGV
  and usage(); 

# load the source, let Imager work out the name
my $src_image = Imager->new;
$src_image->read(file=>$src_name)
  or die "Cannot read source image $src_name: ", $src_image->errstr, "\n";

my $out_image;
if ($fountain) {
  # add a fountain fill border
  my ($out_color, $in_color) = split /,/, $fountain, 2;
  $in_color
    or die "--fountain '$fountain' invalid\n";
  $out_image = fountain_border($src_image, $out_color, $in_color, 
			       $border_width, $border_height);
}
else {
  $out_image = solid_border($src_image, $color, 
			    $border_width, $border_height);
}

# write it out, and let Imager work out the output format from the
# filename
$out_image->write(file=>$out_name)
  or die "Cannot save $out_name: ", $out_image->errstr, "\n";

sub fountain_border {
  my ($src_image, $out_color_name, $in_color_name, 
      $border_width, $border_height) = @_;

  my $out_color = Imager::Color->new($out_color_name)
    or die "Cannot translate color $out_color_name: ", Imager->errstr, "\n";
  my $in_color = Imager::Color->new($in_color_name)
    or die "Cannot translate color $in_color_name: ", Imager->errstr, "\n";
  my $fountain = Imager::Fountain->new;
  $fountain->add
	(
	 c0 => $out_color,
	 c1 => $in_color,
	);

  my $out = Imager->new(xsize => $src_image->getwidth() + 2 * $border_width,
                        ysize => $src_image->getheight() + 2 * $border_height,
                        bits => $src_image->bits,
                        channels => $src_image->getchannels);

  my $width = $out->getwidth;
  my $height = $out->getheight;
  # these mark the corners of the inside rectangle, done here
  # to reduce the redundancy below
  my $in_left = $border_width - 1;
  my $in_right = $width - $border_width;
  my $in_top = $border_height - 1;
  my $in_bottom = $height - $border_height;

  # four linear fountain fills, one for each side
  # Note: we overlap the sides with the top and bottom to avoid
  # having them both anti-alias against the black background where x==y
  # (and the other corners)
  # top
  $out->polygon(x => [ 0, $width-1, $width-1, 0  ],
		y => [ 0, 0,        $in_top,  $in_top ],
		fill => { fountain => 'linear',
			  segments => $fountain,
			  xa => 0, ya => 0,
			  xb => 0, yb => $border_height });
  # bottom
  $out->polygon(x => [ 0,         $width-1,  $width-1,  0 ],
		y => [ $height-1, $height-1, $in_bottom, $in_bottom ],
		fill => { fountain => 'linear',
			  segments => $fountain,
			  xa => 0, ya => $height-1,
			  xb => 0, yb => $height-$border_height });
  # left
  $out->polygon(x => [ 0, 0,         $in_left,   $in_left ],
		y => [ 0, $height-1, $in_bottom, $in_top ],
		fill => { fountain => 'linear',
			  segments => $fountain,
			  xa => 0, ya => 0, 
			  xb => $border_width, yb => 0 });
  # right
  $out->polygon(x => [ $width-1, $width-1,  $in_right,  $in_right ],
		y => [ 0,        $height-1, $in_bottom, $in_top ],
		fill => { fountain => 'linear',
			  segments => $fountain,
			  xa => $width-1, ya => 0,
			  xb => $width-$border_width, yb => 0 });

  # and put the source in
  $out->paste(left => $border_width,
              top => $border_height,
              img => $src_image);

  return $out;
}

sub solid_border {
  my ($source, $color, $border_width, $border_height) = @_;

  my $out = Imager->new(xsize => $source->getwidth() + 2 * $border_width,
                        ysize => $source->getheight() + 2 * $border_height,
                        bits => $source->bits,
                        channels => $source->getchannels);

  # we can do it the lazy way for a solid border - just fill the whole image
  $out->box(filled => 1, color=>$color)
    or die "Invalid color '$color':", $out->errstr, "\n";

  $out->paste(left => $border_width,
              top => $border_height,
              img => $source);

  return $out;
}

sub usage {
  print <<EOS;
Usage: $0 [options] sourceimage outimage
Options are:
  --width <pixels> | -w <pixels>
    Set width of border (default 10)
      eg. --width 25
  --height <pixels> | -h <pixels>
    Set height of border (default 10)
      eg. --height 30
  --thickness <pixels> | -t <pixels>
    Sets width and height of border, overrides -w and -h
      eg. --thickness 20
  --fountain <outcolor>,<incolor> | -f outcolor,incolor
    Creates a border that's a linear fountain fill with outcolor at the
    outside and incolor at the inside.
      eg. --fountain red,black
  --color <color>
    Sets the color of the default solid border.  Ignored if --fountain
    is supplied.  (default red)
      eg. --color blue
EOS
  exit 1;
}

=head1 NAME

border.pl - sample to add borders to an image

=head1 SYNOPSIS

  perl border.pl [options] input output

=head1 DESCRIPTION

Simple sample of adding borders to an image.

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=head1 REVISION

$Revision$

=cut
