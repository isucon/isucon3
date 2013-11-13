#!perl -w
#
# this tests both the Inline interface and the API with IMAGER_NO_CONTEXT
use strict;
use Test::More;
use Imager::Test qw(is_color3 is_color4);
eval "require Inline::C;";
plan skip_all => "Inline required for testing API" if $@;

eval "require Parse::RecDescent;";
plan skip_all => "Could not load Parse::RecDescent" if $@;

use Cwd 'getcwd';
plan skip_all => "Inline won't work in directories with spaces"
  if getcwd() =~ / /;

plan skip_all => "perl 5.005_04, 5.005_05 too buggy"
  if $] =~ /^5\.005_0[45]$/;

-d "testout" or mkdir "testout";

plan tests => 5;
require Inline;
Inline->import(C => Config => AUTO_INCLUDE => "#define IMAGER_NO_CONTEXT\n");
Inline->import(with => 'Imager');
Inline->import("FORCE"); # force rebuild
#Inline->import(C => Config => OPTIMIZE => "-g");

Inline->bind(C => <<'EOS');
#include <math.h>

Imager make_10x10() {
  dIMCTX;
  i_img *im = i_img_8_new(10, 10, 3);
  i_color c;
  c.channel[0] = c.channel[1] = c.channel[2] = 255;
  i_box_filled(im, 0, 0, im->xsize-1, im->ysize-1, &c);

  return im;
}

void error_dIMCTX() {
  dIMCTX;
  im_clear_error(aIMCTX);
  im_push_error(aIMCTX, 0, "test1");
  im_push_errorf(aIMCTX, 0, "test%d", 2);

  im_log((aIMCTX, 0, "test logging\n"));
}

void error_dIMCTXim(Imager im) {
  dIMCTXim(im);
  im_clear_error(aIMCTX);
  im_push_error(aIMCTX, 0, "test1");
}

int context_refs() {
  dIMCTX;

  im_context_refinc(aIMCTX, "context_refs");
  im_context_refdec(aIMCTX, "context_refs");

  return 1;
}

EOS

Imager->open_log(log => "testout/t84inlinectx.log");

my $im2 = make_10x10();
ok($im2, "make an image");
is_color3($im2->getpixel(x => 0, y => 0), 255, 255, 255,
	  "check the colors");
error_dIMCTX();
is(_get_error(), "test2: test1", "check dIMCTX");

my $im = Imager->new(xsize => 1, ysize => 1);
error_dIMCTXim($im);
is(_get_error(), "test1", "check dIMCTXim");

ok(context_refs(), "check refcount functions");

Imager->close_log();

unless ($ENV{IMAGER_KEEP_FILES}) {
  unlink "testout/t84inlinectx.log";
}

sub _get_error {
  my @errors = Imager::i_errors();
  return join(": ", map $_->[0], @errors);
}
