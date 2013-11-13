#!perl -w
use strict;
use Imager;
use POSIX qw(ceil);

$Imager::formats{gif} || $Imager::formats{ungif}
  or die "Your build of Imager doesn't support gif\n";

$Imager::formats{gif}
  or warn "Your build of Imager output's uncompressed GIFs, install libgif instead of libungif (the patents have expired)";

my $factor = shift;
my $in_name = shift;
my $out_name = shift
  or die "Usage: $0 scalefactor input.gif output.gif\n";

$factor > 0
  or die "scalefactor must be positive\n";

my @in = Imager->read_multi(file => $in_name)
  or die "Cannot read image file: ", Imager->errstr, "\n";

# the sizes need to be based on the screen size of the image, but
# that's only present in GIF, make sure the image was read as gif

$in[0]->tags(name => 'i_format') eq 'gif'
  or die "File $in_name is not a GIF image\n";

my $src_screen_width = $in[0]->tags(name => 'gif_screen_width');
my $src_screen_height = $in[0]->tags(name => 'gif_screen_height');

my $out_screen_width = ceil($src_screen_width * $factor);
my $out_screen_height = ceil($src_screen_height * $factor);

my @out;
for my $in (@in) {
  my $scaled = $in->scale(scalefactor => $factor, qtype=>'mixing');
  
  # roughly preserve the relative position
  $scaled->settag(name => 'gif_left', 
		  value => $factor * $in->tags(name => 'gif_left'));
  $scaled->settag(name => 'gif_top', 
		  value => $factor * $in->tags(name => 'gif_top'));

  $scaled->settag(name => 'gif_screen_width', value => $out_screen_width);
  $scaled->settag(name => 'gif_screen_height', value => $out_screen_height);

  # set some other tags from the source
  for my $tag (qw/gif_delay gif_user_input gif_loop gif_disposal/) {
    $scaled->settag(name => $tag, value => $in->tags(name => $tag));
  }
  if ($in->tags(name => 'gif_local_map')) {
    $scaled->settag(name => 'gif_local_map', value => 1);
  }

  push @out, $scaled;
}

Imager->write_multi({ file => $out_name }, @out)
  or die "Cannot save $out_name: ", Imager->errstr, "\n";

=head1 NAME

=for stopwords gifscale.pl

gifscale.pl - demonstrates adjusting tags when scaling a GIF image

=head1 SYNOPSIS

  perl gifscale.pl scalefactor input.gif output.gif

=head1 DESCRIPTION

Scales an input multiple-image GIF file.  Unlike a simple scale each file
solution this:

=over

=item *

preserves GIF animation attributes

=item *

adjusts the sub-images positions on the background accounting for the
scale factor.

=back

=head1 AUTHOR

Tony Cook <tonyc@cpan.org>

=cut
