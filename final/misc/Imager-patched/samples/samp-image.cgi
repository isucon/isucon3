#!/usr/bin/perl -w
use strict;
use CGI;
use Imager;

my $cgi = CGI->new;

my $color = $cgi->param('color');

defined $color or $color = '';

# Imager allows a number of different color specs, but keep this
# simple, only accept simple RRGGBB hex colors
my %errors;

# note that you need to perform validation here as well as in 
# the form script, since the user can view image and manipulate the
# URL (or even fetch the URL using LWP and modify the request in any way
# they like.
# Since we're producing an image, we don't have a mechanism to
# report errors (unless we choose to draw text on an image), so
# just product a default image.
if (!defined $color || $color !~ /^[0-9a-f]{6}$/i) {
  $color = '000000';
}

my $im = Imager->new(xsize=>40, ysize=>40);
$im->box(filled=>1, color=>$color);

# this will force the flushing of the headers, otherwise the server (and
# your web browser) may see the image data before the content type.
++$|;

print "Content-Type: image/jpeg\n\n";

# use binmode to prevent LF expanding to CRLF on windows
binmode STDOUT;

# we have to supply the type of output since we haven't supplied a
# filename
$im->write(fd=>fileno(STDOUT), type=>'jpeg')
  or die "Cannot write to stdout: ", $im->errstr;

=head1 NAME

samp-image.cgi - demonstrates interaction of HTML generation with image generation

=head1 SYNOPSIS

  /cgi-bin/samp-image.cgi?color=RRGGBB

=head1 DESCRIPTION

This is the image generation program that samp-form.cgi uses to
generate the image.

See samp-form.cgi for more detail.

=head1 REVISION

$Revision$

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
