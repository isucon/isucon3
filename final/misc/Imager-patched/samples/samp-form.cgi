#!/usr/bin/perl -w
use strict;
use CGI;
use HTML::Entities;

my $cgi = CGI->new;

# get our parameter, make sure it's defined to avoid 
my $color = $cgi->param('color');

# Imager allows a number of different color specs, but keep this
# simple, only accept simple RRGGBB hex colors
my %errors;

if (defined $color && $color !~ /^[0-9a-f]{6}$/i) {
  $errors{color} = "Color must be hex RRGGBB";
}

# validated, make it defined to avoid warnings in the HTML generation
defined $color or $color = '';

# print the content type header and the start of out HTML
print "Content-Type: text/html\n\n", <<HTML;
<html>
  <head>
    <title>Sample HTML and Image generation with Imager</title>
  </head>
  <body>
    <form action="/cgi-bin/samp-form.cgi">
HTML

# link to the image if we got a good color
# START LINK GENERATION (see the POD)
if ($color && !keys %errors) {
  # since color only contains word characters it doesn't need to be
  # escaped, in most cases you'd load URI::Escape and call uri_escape() on it
  print <<HTML;
<img src="/cgi-bin/samp-image.cgi?color=$color" width="40" height="40" alt="color sample" />
HTML
}
# END LINK GENERATION

# finish off the page
# one reason template systems are handy...
my $color_encoded = encode_entities($color);
my $color_msg_encoded = encode_entities($errors{color} || '');

print <<HTML;
<p>Color: <input type="text" name="color" value="$color_encoded" size="6" />
$color_msg_encoded</p>
<input type="submit" value="Show Color" />
</html>
</body>
HTML

=head1 NAME

samp-form.cgi - demonstrates interaction of HTML generation with image generation

=head1 SYNOPSIS

  /cgi-bin/samp-form.cgi?color=RRGGBB

=head1 DESCRIPTION

This is the HTML side of a sample for Imager that demonstrates
generating an image linked from a HTML form.

See samp-image.cgi for the image generation side of this sample.

One common mistake seen in generating images is attempting to generate
the image inline, for example:

  # DON'T DO THIS, IT'S WRONG
  my $img = Imager->new(...);
  ...  draw on the image  ...  
  print '<img src="',$img->write(fd=>fileno(STDOUT), type="jpeg"),'" />';

This sample code demonstrates one of the possible correct ways to
generate an image linked from a HTML page.

This has the limitation that some processing is done twice, for
example, the validation of the parameters, but it's good when the same
image will never be generated again.

The basic approach is to have one program generate the HTML which
links to a second program that generates the image.

This sample is only intended to demonstrate embedding a generated
image in a page, it's missing some best practice:

=over

=item *

a templating system, like HTML::Mason, or Template::Toolkit should be
used to generate the HTML, so that the HTML can be maintained
separately from the code.  Such a system should also be able to HTML
or URI escape values embedded in the page to avoid the separate code
used above.

=item *

a more complex system would probably do some validation as part of
business rules, in a module.

=back

=head1 ANOTHER APPROACH

A different way of doing this is to have the HTML generation script
write the images to a directory under the web server document root,
for example, the code from C<# START LINK GENERATION> to C<# END LINK
# GENERATION> in samp-form.cgi would be replaced with something like:

  if ($color && !keys %errors) {
    # make a fairly unique filename
    # in this case we could also use:
    #   my $filename = lc($color) . ".jpg";
    # but that's not a general solution
    use Time::HiRes;
    my $filename = time . $$ . ".jpg";
    my $image_path = $docroot . "/images/dynamic/" . $filename;
    my $image_url = "/images/dynamic/" . $filename;
    
    my $im = Imager->new(xsize=>40, ysize=>40);
    $im->box(filled=>1, color=>$color);

    $im->write(file=>$image_path)
      or die "Cannot write to $image_path:", $im->errstr, "\n";

    print <<HTML;
  <img src="$image_url" width="40" height="40" alt="color sample" />
  HTML
  }

This has the advantage that you aren't handling a second potentially
expensive CGI request to generate the image, but it means you need
some mechanism to manage the files (for example, a cron job to delete
old files), and you need to make some directory under the document
root writable by the user that your web server runs CGI programs as,
which may be a security concern.

Also, if you're generating large numbers of large images, you may end
up using significant disk space.

=head1 SECURITY

It's important to remember that any value supplied by the user can be
abused by the user, in this example there's only one parameter, the
color of the sample image, but in a real application the values
supplied coule include font filenames, URLs, image filename and so on.
It's important that these are validated and in some cases limited to
prevent a user from using your program to obtain access or deny access
to things they shouldn't be able to.

For example of limiting a parameter, you might have a select like:

  <!-- don't do this, it's wrong -->
  <select name="font">
    <option value="arial.ttf">Arial</option>
    <option value="arialb.ttf">Arial Black</option>
    ...
  </select>

and then build a font filename with:

  my $fontname = $cgi->param('font');
  my $fontfile=$fontpath . $fontname;

but watch out when the user manually supplies font with a value like 
C<../../../some_file_that_crashes_freetype>.

So limit the values and validate them:

  <select name="font">
    <option value="arial">Arial</option>
    <option value="arialb.ttf">Arial Bold</option>
    ...
  </select>

and code like:

  my $fontname = $cgi->param('font');
  $fontname =~ /^\w+$/ or $fontname = 'arial'; # use a default if invalid
  -e $fontpath . $fontname . ".ttf" or $fontname = 'arial';
  my $fontfile = $fontpath . $fontname . '.ttf';

or use a lookup table:

  my %fonts = (
    arial => "arial.ttf",
    arialb => "arialb.ttf",
    xfont_helv => "x11/helv.pfb",
    );
  ...

  my $fontname = $cgi->param('font');
  exists $fonts{$fontname} or $fontname = 'arial';
  my $fontfile = $fontpath . $fonts{$fontname};

Remember that with perl your code isn't in a sandbox, it's up to you
to prevent shooting yourself in the foot.

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
