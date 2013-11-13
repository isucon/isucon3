#!perl -w
use strict;
use Test::More tests => 25;

BEGIN { use_ok('Imager::File::CUR'); }

-d 'testout' or mkdir 'testout', 0777;

my $im = Imager->new;

ok($im->read(file => 'testimg/pal43232.cur', type=>'cur'),
   "read 4 bit");
is($im->getwidth, 32, "check width");
is($im->getheight, 32, "check width");
is($im->type, 'paletted', "check type");
is($im->tags(name => 'cur_bits'), 4, "check cur_bits tag");
is($im->tags(name => 'i_format'), 'cur', "check i_format tag");
is($im->tags(name => 'cur_hotspotx'), 1, "check cur_hotspotx tag");
is($im->tags(name => 'cur_hotspoty'), 18, "check cur_hotspoty tag");
my $mask = ".*" . ("\n" . "." x 32) x 32;
is($im->tags(name => 'cur_mask'), $mask, "check cur_mask tag");

# these should get pushed back into range on saving
$im->settag(name => 'cur_hotspotx', value => 32);
$im->settag(name => 'cur_hotspoty', value => -1);
ok($im->write(file=>'testout/hotspot.cur', type=>'cur'),
   "save with oor hotspot")
  or print "# ",$im->errstr, "\n";
{
  my $im2 = Imager->new;
  ok($im2->read(file=>'testout/hotspot.cur', type=>'cur'),
     "re-read the hotspot set cursor")
    or print "# ", $im->errstr, "\n";
  is($im2->tags(name => 'cur_hotspotx'), 31, "check cur_hotspotx tag");
  is($im2->tags(name => 'cur_hotspoty'), 0, "check cur_hotspoty tag");
}

$im->settag(name => 'cur_hotspotx', value => -1);
$im->settag(name => 'cur_hotspoty', value => 32);
ok($im->write(file=>'testout/hotspot2.cur', type=>'cur'),
   "save with oor hotspot")
  or print "# ",$im->errstr, "\n";

{
  my $im2 = Imager->new;
  ok($im2->read(file=>'testout/hotspot2.cur', type=>'cur'),
     "re-read the hotspot set cursor")
    or print "# ", $im->errstr, "\n";
  is($im2->tags(name => 'cur_hotspotx'), 0, "check cur_hotspotx tag");
  is($im2->tags(name => 'cur_hotspoty'), 31, "check cur_hotspoty tag");
}

{
  my $data = '';
  ok($im->write(data => \$data, type => 'cur'),
     "write single to data");
  print "# ", length $data, " bytes written\n";
  my $im2 = Imager->new;
  ok($im2->read(data => $data), "read back in");
  is(Imager::i_img_diff($im->{IMG}, $im2->{IMG}), 0, "check image");
}

{
  my $data = '';
  ok(Imager->write_multi({ type => 'cur', data => \$data }, $im, $im),
     "write multiple images");
  print "# ", length $data, " bytes written\n";
  my @im = Imager->read_multi(type => 'cur', data => $data)
    or print "# ", Imager->errstr, "\n";
  is(@im, 2, "read them back in");
  is(Imager::i_img_diff($im->{IMG}, $im[0]{IMG}), 0, "check first image");
  is(Imager::i_img_diff($im->{IMG}, $im[1]{IMG}), 0, "check second image");
}
