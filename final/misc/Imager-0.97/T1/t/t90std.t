#!perl -w
use strict;
use Imager::Test qw(std_font_tests std_font_test_count);
use Imager::Font;
use Test::More tests => std_font_test_count();

Imager->open_log(log => "testout/t90std.log");

my $font = Imager::Font->new(file => "fontfiles/dcr10.pfb",
			     type => "t1");

SKIP:
{
  $font
    or skip "Cannot load font", std_font_test_count();
  std_font_tests({ font => $font,
		   has_chars => [ 1, '', 1 ]});
}

Imager->close_log;
