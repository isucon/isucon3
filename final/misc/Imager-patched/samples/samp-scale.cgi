#!/usr/bin/perl -w

=head1 NAME

samp-scale.cgi - sample CGI that takes an uploaded image to make a new image using Imager

=head1 SYNOPSIS

  Copy samp-scale.html to your document tree.
  Copy samp-scale.cgi to your /cgi-bin
  Browse to samp-scale.html in your browser
  Select an image file
  Click on "Scale Image"

=cut


use strict;
use Imager;
use CGI;

my $cgi = CGI->new;

my $filename = $cgi->param('image');
if ($filename) {
  my $fh = $cgi->upload('image');
  if ($fh) {
    binmode $fh;

    my $image = Imager->new;
    if ($image->read(fh=>$fh)) {
      # scale it to max 200 x 200
      my $scaled = $image->scale(xpixels=>200, ypixels=>200, type=>'min');
      if ($scaled) {
	# no line end conversion (or UTF or whatever)
	binmode STDOUT;

	# send in the order we provide it
	++$|;

	# give it back to the user - as a JPEG
	print "Content-Type: image/jpeg\n\n";
	$scaled->write(fd=>fileno(STDOUT), type=>'jpeg');
      }
      else {
	# this should only fail in strange circumstances
	error("Cannot scale image: ", $image->errstr);
      }
    }
    else {
      error("Cannot read image: ".$image->errstr);
    }
  }
  else {
    error("Incorrect form or input tag - check enctype and that the file upload field is type file");
  }
}
else {
  error("No image was supplied");
}

# simple error handler, ideally you'd display the form again with
# an error in the right place, but this is a sample
sub error {
  my ($msg) = @_;

  print "Content-Type: text/plain\n\nError processing form:\n$msg\n";
  exit;
}

=head1 DESCRIPTION

This is a sample CGI program that accepts an image file from the
browser.

Please read L<Imager::Cookbook/Parsing an image posted via CGI> for
cautions and explanations.

=head1 AUTHOR

Tony Cook <tonyc@cpan.org>

=head1 REVISION

$Revision$

=cut
  
