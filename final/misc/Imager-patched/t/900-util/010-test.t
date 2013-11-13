#!perl -w
use strict;
use Imager;
use Imager::Test qw(test_image test_image_16 test_image_mono test_image_gray test_image_gray_16 test_image_double test_image_named);
use Test::More tests => 60;

# test Imager::Test

for my $named (0, 1) {
  my $named_desc = $named ? " (by name)" : "";
  {
    my $im = $named ? test_image_named("basic") : test_image();
    ok($im, "got basic test image$named_desc");
    is($im->type, "direct", "check basic image type");
    is($im->getchannels, 3, "check basic image channels");
    is($im->bits, 8, "check basic image bits");
    ok(!$im->is_bilevel, "check basic isn't mono");
  }
  {
    my $im = $named ? test_image_named("basic16") : test_image_16();
    ok($im, "got 16-bit basic test image$named_desc");
    is($im->type, "direct", "check 16-bit basic image type");
    is($im->getchannels, 3, "check 16-bit basic image channels");
    is($im->bits, 16, "check 16-bit basic image bits");
    ok(!$im->is_bilevel, "check 16-bit basic isn't mono");
  }
  
  {
    my $im = $named ? test_image_named("basic_double") : test_image_double();
    ok($im, "got double basic test image$named_desc");
    is($im->type, "direct", "check double basic image type");
    is($im->getchannels, 3, "check double basic image channels");
    is($im->bits, "double", "check double basic image bits");
    ok(!$im->is_bilevel, "check double basic isn't mono");
  }
  {
    my $im = $named ? test_image_named("gray") : test_image_gray();
    ok($im, "got gray test image$named_desc");
    is($im->type, "direct", "check gray image type");
    is($im->getchannels, 1, "check gray image channels");
    is($im->bits, 8, "check gray image bits");
    ok(!$im->is_bilevel, "check gray isn't mono");
    $im->write(file => "testout/t03gray.pgm");
  }
  
  {
    my $im = $named ? test_image_named("gray16") : test_image_gray_16();
    ok($im, "got gray test image$named_desc");
    is($im->type, "direct", "check 16-bit gray image type");
    is($im->getchannels, 1, "check 16-bit gray image channels");
    is($im->bits, 16, "check 16-bit gray image bits");
    ok(!$im->is_bilevel, "check 16-bit isn't mono");
    $im->write(file => "testout/t03gray16.pgm");
  }
  
  {
    my $im = $named ? test_image_named("mono") : test_image_mono();
    ok($im, "got mono image$named_desc");
    is($im->type, "paletted", "check mono image type");
    is($im->getchannels, 3, "check mono image channels");
    is($im->bits, 8, "check mono image bits");
    ok($im->is_bilevel, "check mono is mono");
    $im->write(file => "testout/t03mono.pbm");
  }
}
