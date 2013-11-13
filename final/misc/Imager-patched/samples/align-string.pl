#!perl -w
use strict;
use Imager;

my ($font_filename, $size, $out_filename, @text) = @ARGV;

@text
  or usage();

$size =~ /^\d+$/ && $size >= 10
  or die "size must be 10 or greater";

my $text = "@text";

my $mark_color = Imager::Color->new('#00F');
my $text_color = Imager::Color->new('#fff');

my $font = Imager::Font->new(file=>$font_filename, 
			     size => $size, 
			     color => $text_color,
			     aa => 1)
  or die "Cannot create font from $font_filename: ", Imager->errstr;

my @valigns = qw(top center bottom baseline);
my @haligns = qw(left start center end right);

my $bounds = $font->bounding_box(string => $text);

my $text_width = $bounds->total_width;
my $text_height = $bounds->text_height;

my $img = Imager->new(xsize => $text_width * 2 * @haligns,
		      ysize => $text_height * 2 * @valigns);

my $xpos = $text_width;
for my $halign (@haligns) {
  my $ypos = $text_height;
  for my $valign (@valigns) {
    # mark the align point
    $img->line(x1 => $xpos - $size, y1 => $ypos, 
	       x2 => $xpos + $size, y2 => $ypos,
	       color => $mark_color);
    $img->line(x1 => $xpos, y1 => $ypos - $size, 
	       x2 => $xpos, y2 => $ypos + $size,
	       color => $mark_color);
    $img->align_string(font => $font,
		       string => $text,
		       x => $xpos, y => $ypos,
		       halign => $halign,
		       valign => $valign);
    $ypos += 2 * $text_height;
  }
  $xpos += 2 * $text_width;
}

$img->write(file => $out_filename)
  or die "Cannot write $out_filename: ", $img->errstr, "\n";

sub usage {
  die <<USAGE;
$0 fontfile size output text...
USAGE
}

=head1 NAME

align-string.pl - demo of the Imager align_string() method

=head1 SYNOPSIS

  perl align-string.pl fontfile size outputfile text ...

=head1 DESCRIPTION

Create an image in output C<imagein> C<outputfile> displaying a grid of
the various C<valign> and C<halign> options for the Imager align_string()
method.

Try it with different fonts and strings to get a better understanding
of the effect of the different alignments.

=head1 AUTHOR

Tony Cook <tonyc@cpan.org>

=head1 SEE ALSO

Imager, Imager::Font

=head1 REVISION

$Revision$

=cut

