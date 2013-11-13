#!perl
use strict;
use Imager;
use Getopt::Long;

my $delay = 10;
my $frames = 20;
my $low_pct = 30;
my $back = '#FFFFFF';
my $verbose = 0;
GetOptions('delay|d=i', \$delay,
	   'frames|f=i', \$frames,
	   'lowpct|p=i', \$low_pct,
	   'back|b=s', \$back,
	   'verbose|v' => \$verbose);

my $back_color = Imager::Color->new($back)
  or die "Cannot convert $back to a color: ", Imager->errstr, "\n";

$low_pct >= 0 && $low_pct < 100
  or die "lowpct must be >=0 and < 100\n";

$delay > 0 and $delay < 255
  or die "delay must be between 1 and 255\n";

$frames > 1 
  or die "frames must be > 1\n";

my $in_name = shift
  or usage();

my $out_name = shift
  or usage();

my $base = Imager->new;
$base->read(file => $in_name)
  or die "Cannot read image file $in_name: ", $base->errstr, "\n";

# convert to RGBA to simplify the convert() matrix
$base = $base->convert(preset => 'rgb') unless $base->getchannels >=3;
$base = $base->convert(preset => 'addalpha') unless $base->getchannels == 4;

my $width = $base->getwidth;
my $height = $base->getheight;

my @down;
my $down_frames = $frames / 2;
my $step = (100 - $low_pct) / $down_frames;
my $percent = 100 - $step;
++$|;
print "Generating frames\n" if $verbose;
for my $frame_no (1 .. $down_frames) {
  print "\rFrame $frame_no/$down_frames";

  # canvas with our background color
  my $canvas = Imager->new(xsize => $width, ysize => $height);
  $canvas->box(filled => 1, color => $back_color);

  # make a version of our original with the alpha scaled
  my $scale = $percent / 100.0;
  my $draw = $base->convert(matrix => [ [ 1, 0, 0, 0 ],
					[ 0, 1, 0, 0 ],
					[ 0, 0, 1, 0 ],
					[ 0, 0, 0, $scale ] ]);

  # draw it on the canvas
  $canvas->rubthrough(src => $draw);

  push @down, $canvas;
  $percent -= $step;
}
print "\n" if $verbose;

# generate a sequence going from the original down to the most faded
my @frames = $base;
push @frames, @down;
# remove the most faded frame so it isn't repeated
pop @down; 
# and back up again
push @frames, reverse @down;

print "Writing frames\n" if $verbose;
Imager->write_multi({ file => $out_name, 
		      type => 'gif',
		      gif_loop => 0, # loop forever
		      gif_delay => $delay,
		      translate => 'errdiff',
		      make_colors => 'mediancut',
		    },
		    @frames)
  or die "Cannot write $out_name: ", Imager->errstr, "\n";

sub usage {
  die <<EOS;
Produce an animated gif that cycles an image fading into a background and
unfading back to the original image.
Usage: $0 [options] input output
Input can be any image supported by Imager.
Output should be a .gif file.
Options include:
  -v | --verbose
    Progress reports
  -d <delay> | --delay <delay>
    Delay between frames in 1/100 sec.  Default 10.
  -p <percent> | --percent <percent>
    Low percentage coverage.  Default: 30
  -b <color> | --back <color>
    Color to fade towards, in some format Imager understands.
    Default: #FFFFFF
  -f <frames> | --frames <frames>
    Rough total number of frames to produce.  Default: 20.
EOS
}

=head1 NAME

flasher.pl - produces a slowly flashing GIF based on an input image

=head1 SYNOPSIS

  perl flasher.pl [options] input output.gif

=head1 DESCRIPTION

flasher.pl generates an animation from the given image to C<lowpct>%
coverage on a blank image of color C<back>.

=head1 OPTIONS

=over

=item *

C<-f> I<frames>, C<--frames> I<frames> - the total number of frames.
This is always rounded up to the next even number.  Default: 20

=item *

C<-d> I<delay>, C<--delay> I<delay> - the delay in 1/100 second between
frames.  Default: 10.

=item *

C<-p> I<percent>, C<--lowpct> I<percent> - the lowest coverage of the image.
Default: 30

=item *

C<-b> I<color>, C<--back> I<color> - the background color to fade to.  
Default: #FFFFFF.

=item *

C<-v>, C<--verbose> - produce progress information.

=back

=head1 AUTHOR

Tony Cook <tonyc@cpan.org>

=cut

