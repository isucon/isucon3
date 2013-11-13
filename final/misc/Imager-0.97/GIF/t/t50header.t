#!perl -w
use strict;
use Test::More tests => 4;
use Imager;
use Imager::Test qw(test_image);

# giflib 4.2.0 and 5.0.0 had a bug with producing the wrong
# GIF87a/GIF89a header, test we get the right header
# https://rt.cpan.org/Ticket/Display.html?id=79679
# https://sourceforge.net/tracker/?func=detail&aid=3574283&group_id=102202&atid=631304
my $im = test_image()->to_paletted();

{
  my $data;
  ok($im->write(data => \$data, type => "gif"),
     "write with no tags, should be GIF87a");
  is(substr($data, 0, 6), "GIF87a", "check header is GIF87a");
}

{
  my $data;
  ok($im->write(data => \$data, type => "gif", gif_loop => 1),
     "write with loop tags, should be GIF89a");
  is(substr($data, 0, 6), "GIF89a", "check header is GIF89a");
}
