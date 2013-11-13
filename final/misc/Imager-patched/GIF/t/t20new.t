#!perl -w
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)


use strict;
use Test::More tests => 21;

use Imager qw(:all :handy);
use Imager::Test qw(test_image is_color3);

-d "testout" or mkdir "testout";

Imager::init('log'=>'testout/t70newgif.log');

my $green=i_color_new(0,255,0,0);
my $blue=i_color_new(0,0,255,0);

{
  my $img = test_image();
  
  ok($img->write(file=>'testout/t70newgif.gif',type=>'gif',gifplanes=>1,gifquant=>'lm',lmfixed=>[$green,$blue]))
    or print "# failed: ",$img->{ERRSTR}, "\n";
}

SKIP:
{
  # make sure the palette is loaded properly (minimal test)
  my $im2 = Imager->new();
  my $map;
  ok($im2->read(file=>'testimg/bandw.gif', colors=>\$map))
    or skip("Can't load bandw.gif", 5);
  # check the palette
  ok($map)
    or skip("No palette", 4);
  is(@$map, 2)
    or skip("Bad map count", 3);
  my @sorted = sort { comp_entry($a,$b) } @$map;
  # first entry must be #000000 and second #FFFFFF
  is_color3($sorted[0], 0,0,0, "check first palette entry");
  is_color3($sorted[1], 255,255,255, "check second palette entry");
}

{
  # test the read_multi interface
  my @imgs = Imager->read_multi();
  ok(!@imgs, "read with no sources should fail");
  like(Imager->errstr, qr/callback parameter missing/, "check error");
  print "# ",Imager->errstr,"\n";

  @imgs = Imager->read_multi(type=>'gif');
  ok(!@imgs, "read multi no source but type should fail");
  like(Imager->errstr, qr/file/, "check error");

  # kill warning
  *NONESUCH = \20;
  @imgs = Imager->read_multi(type=>'gif', fh=>*NONESUCH);
  ok(!@imgs, "read from bad fh");
  like(Imager->errstr, qr/fh option not open/, "check message");
  print "# ",Imager->errstr,"\n";
  {
    @imgs = Imager->read_multi(type=>'gif', file=>'testimg/screen2.gif');
    is(@imgs, 2, "should read 2 images");
    isa_ok($imgs[0], "Imager");
    isa_ok($imgs[1], "Imager");
    is($imgs[0]->type, "paletted");
    is($imgs[1]->type, "paletted");
    my @left = $imgs[0]->tags(name=>'gif_left');
    is(@left, 1);
    my $left = $imgs[1]->tags(name=>'gif_left');
    is($left, 3);
  }
  {
    open FH, "< testimg/screen2.gif" 
      or die "Cannot open testimg/screen2.gif: $!";
    binmode FH;
    my $cb = 
      sub {
	my $tmp;
	read(FH, $tmp, $_[0]) and $tmp
      };
    @imgs = Imager->read_multi(type=>'gif',
			       callback => $cb);
    close FH;
    is(@imgs, 2, "read multi from callback");
    
    open FH, "< testimg/screen2.gif" 
      or die "Cannot open testimg/screen2.gif: $!";
    binmode FH;
    my $data = do { local $/; <FH>; };
    close FH;
    @imgs = Imager->read_multi(type=>'gif',
			       data=>$data);
    is(@imgs, 2, "read multi from data");
  }
}

sub comp_entry {
  my ($l, $r) = @_;
  my @l = $l->rgba;
  my @r = $r->rgba;
  return $l[0] <=> $r[0]
    || $l[1] <=> $r[1]
      || $l[2] <=> $r[2];
}
