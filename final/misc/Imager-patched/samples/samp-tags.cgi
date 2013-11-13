#!/usr/bin/perl -w

=head1 NAME

samp-tags.cgi - sample CGI that takes an uploaded image to produce a report

=head1 SYNOPSIS

  Copy samp-tags.html to your document tree.
  Copy samp-tags.cgi to your /cgi-bin
  Browse to samp-tags.html in your browser
  Select an image file
  Click on "Report Image Tags"

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
      print "Content-Type: text/plain\n\n";
      print "File: $filename\n";
      my @tags = $image->tags;
      for my $tag (sort { $a->[0] cmp $b->[0] } @tags) {
	my $name = shift @$tag;
	print " $name: @$tag\n";
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
  
