#!perl -w
use strict;
use Tk;
use Tk::Photo;
use MIME::Base64;
use Tk::PNG;
use Imager;

my $image = Imager->new(xsize=>100, ysize=>100);

# draw something simple here, you'll probably do something more complex
$image->box(filled=>1, color=>'blue');
$image->box(filled=>1, color=>'red', 
	    xmin=>20, ymin=>20, xmax=>79, ymax=>79);

my $image_data;
$image->write(data =>\$image_data, type=>'png')
  or die "Cannot save image: ", $image->errstr;

# supplying binary data didn't work, so we base64 encode it
$image_data = encode_base64($image_data);

my $main = MainWindow->new;
my $tk_image = $main->Photo(-data => $image_data);
$main->Label(-image=>$tk_image)->pack;
MainLoop;

=head1 NAME

=for stopwords tk-photo.pl

tk-photo.pl - display an Imager image under Tk

=head1 SYNOPSIS

  $ perl tk-photo.pl

=head1 DESCRIPTION

Simple code to make a Tk::Photo object from an Imager image.

This works by:

=over

=item 1.

write the image data to a scalar in PNG format

=item 2.

Base64 decode the data

=item 3.

read() it into the photo object, supplying the Base64 encoded data to
the C<-data> parameter.

=back

=head1 REVISION

$Revision$

=head1 AUTHOR

Tony Cook <tonyc@cpan.org>

=cut
