#!perl -w
use strict;
use Imager;
use Test::More tests => 14;

unshift @INC, "t";

ok(Imager::Font->register(type => "test",
			  class=>"GoodTestFont",
			  files => "\\.ppm\$"),
   "register a test font");

ok(Imager::Font->register(type => "bad",
			  class => "BadTestFont",
			  files => "\\.ppm\$"),
   "register a bad test font");

ok(!Imager::Font->register(), "no register parameters");
like(Imager->errstr, qr/No type parameter/, "check message");

ok(!Imager::Font->register(type => "bad1"), "no class parameter");
like(Imager->errstr, qr/No class parameter/, "check message");

ok(!Imager::Font->register(type => "bad2", class => "BadFont", files => "**"),
   "bad files parameter");
is(Imager->errstr, "files isn't a valid regexp", "check message");

Imager::Font->priorities("bad", "test");

# RT #62855
# previously we'd select the first file matched font driver, even if
# it wasn't available, then crash loading it.

SKIP:
{
  my $good;
  ok(eval {
    $good = Imager::Font->new(file => "testimg/penguin-base.ppm");
  }, "load good font avoiding RT 62855")
    or skip("Failed to load", 1);
  ok($good->isa("GoodTestFont"), "and it's the right type");
}


use Imager::Font::Test;

# check string() and align_string() handle an empty image
{
  my $font = Imager::Font::Test->new;
  my $empty = Imager->new;
  ok(!$empty->string(text => "foo", x => 0, y => 10, size => 10, font => $font),
     "can't draw text on an empty image");
  is($empty->errstr, "string: empty input image",
     "check error message");
  ok(!$empty->align_string(text => "foo", x => 0, y => 10, size => 10, font => $font),
     "can't draw text on an empty image");
  is($empty->errstr, "align_string: empty input image",
     "check error message");
}
