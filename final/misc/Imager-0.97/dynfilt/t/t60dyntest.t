#!perl -w
use strict;
use lib '../t';
use Test::More tests => 8;
BEGIN { use_ok(Imager => qw(:default)); }
use Config;
use Imager::Test qw(test_image);

#$Imager::DEBUG=1;

-d "testout" or mkdir "testout";

Imager->open_log(log => 'testout/t60dyntest.log');

my $img=Imager->new() || die "unable to create image object\n";

$img->read(file=>'../testimg/penguin-base.ppm',type=>'pnm') 
  || die "failed: ",$img->{ERRSTR},"\n";

my $plug='./dyntest.'.$Config{'so'};
ok(load_plugin($plug), "load plugin")
  || die "unable to load plugin: $Imager::ERRSTR\n";

my %hsh=(a=>35,b=>200,type=>'lin_stretch');
ok($img->filter(%hsh), "call filter");

$img->write(type=>'pnm',file=>'testout/linstretch.ppm') 
  || die "error in write()\n";

ok(unload_plugin($plug), "unload plugin")
  || die "unable to unload plugin: $Imager::ERRSTR\n";

{
  my $flines = "./flines.$Config{so}";
  ok(load_plugin($flines), "load flines");
  my $im = test_image();
  ok($im->filter(type => "flines"), "do the flines test");
  ok($im->write(file => "testout/flines.ppm"), "save flines result");
  ok(unload_plugin($flines), "unload flines");
}

Imager->close_log;

unless ($ENV{IMAGER_KEEP_FILES}) {
  unlink "testout/linstretch.ppm";
  unlink "testout/flines.ppm";
  unlink "testout/t60dyntest.log";
  rmdir "testout";
}

