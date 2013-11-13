#!perl -w
use strict;
use blib;
use Imager;
use Test::More tests => 9;

BEGIN { use_ok('Imager::CountColor' => 'count_color') }

my $black = Imager::Color->new(0, 0, 0);
my $blue = Imager::Color->new(0, 0, 255);
my $red = Imager::Color->new(255, 0, 0);
my $im = Imager->new(xsize=>50, ysize=>50);
is(count_color($im, $black), 2500, "check black vs black image");
is(count_color($im, $red), 0, "check red vs black image");
$im->box(filled=>1, color=>$blue, xmin=>25);
is(count_color($im, $black), 1250, "check black vs black/blue image");
is(count_color($im, $red), 0, "check red vs black/blue image");
is(count_color($im, $blue), 1250, "check blue vs black/blue image");
$im->box(filled=>1, color=>$red, ymin=>25);
is(count_color($im, $black), 625, "check black vs black/blue/red image");
is(count_color($im, $blue), 625, "check black vs black/blue/red image");
is(count_color($im, $red), 1250, "check black vs black/blue/red image");
