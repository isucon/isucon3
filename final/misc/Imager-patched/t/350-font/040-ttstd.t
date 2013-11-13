#!perl -w
use strict;
use Imager::Test qw(std_font_tests std_font_test_count);
use Imager::Font;
use Test::More;

$Imager::formats{tt}
	or plan skip_all => "No tt available";

Imager->open_log(log => "testout/t37std.log");

plan tests => std_font_test_count();

my $font = Imager::Font->new(file => "fontfiles/dodge.ttf",
			     type => "tt");
my $name_font =
  Imager::Font->new(file => "fontfiles/ImUgly.ttf",
		    type => "tt");

SKIP:
{
  $font
    or skip "Cannot load font", std_font_test_count();
  std_font_tests
    ({
      font => $font,
      has_chars => [ 1, 1, 1 ],
      glyph_name_font => $name_font,
      glyph_names => [ qw(A uni2010 A) ],
     });
}

Imager->close_log;
