#!perl -w
use strict;
use Test::More tests => 106;
use Imager::Test qw(is_image test_image);

BEGIN { use_ok('Imager::File::ICO'); }

-d 'testout' or mkdir 'testout', 0777;

my $im = Imager->new;
# type=>'ico' or 'cur' and read ico and cur since they're pretty much
# the same
ok($im->read(file => "testimg/rgba3232.ico", type=>"ico", ico_masked => 0),
   "read 32 bit")
  or print "# ", $im->errstr, "\n";
is($im->getwidth, 32, "check width");
is($im->getwidth, 32, "check height");
is($im->type, 'direct', "check type");
is($im->tags(name => 'ico_bits'), 32, "check ico_bits tag");
is($im->tags(name => 'i_format'), 'ico', "check i_format tag");
my $mask = '.*
..........................******
..........................******
..........................******
..........................******
...........................*****
............................****
............................****
.............................***
.............................***
.............................***
.............................***
..............................**
..............................**
...............................*
...............................*
................................
................................
................................
................................
................................
................................
*...............................
**..............................
**..............................
***.............................
***.............................
****............................
****............................
*****...........................
*****...........................
*****...........................
*****...........................';
is($im->tags(name => 'ico_mask'), $mask, "check ico_mask_tag");

# compare the pixels
# ppm can't store 4 channels
SKIP:
{
  my $work = $im->convert(preset=>'noalpha');
  my $comp = Imager->new;
  $comp->read(file => "testimg/rgba3232.ppm")
    or skip "could not read 24-bit comparison file:". $comp->errstr, 1;
  is(Imager::i_img_diff($comp->{IMG}, $work->{IMG}), 0,
     "compare image data");
}

ok($im->read(file => 'testimg/pal83232.ico', type=>'ico', ico_masked => 0),
   "read 8 bit")
  or print "# ", $im->errstr, "\n";
is($im->getwidth, 32, "check width");
is($im->getwidth, 32, "check height");
is($im->type, 'paletted', "check type");
is($im->colorcount, 256, "color count");
is($im->tags(name => 'ico_bits'), 8, "check ico_bits tag");
is($im->tags(name => 'i_format'), 'ico', "check i_format tag");
SKIP:
{
  my $comp = Imager->new;
  $comp->read(file => "testimg/pal83232.ppm")
    or skip "could not read 8-bit comparison file:". $comp->errstr, 1;
  is(Imager::i_img_diff($comp->{IMG}, $im->{IMG}), 0,
     "compare image data");
}
$im->write(file=>'testout/pal83232.ppm');

ok($im->read(file => 'testimg/pal43232.ico', type=>'ico', ico_masked => 0),
   "read 4 bit")
  or print "# ", $im->errstr, "\n";
is($im->getwidth, 32, "check width");
is($im->getwidth, 32, "check height");
is($im->type, 'paletted', "check type");
is($im->colorcount, 16, "color count");
is($im->tags(name => 'ico_bits'), 4, "check ico_bits tag");
is($im->tags(name => 'i_format'), 'ico', "check i_format tag");
SKIP:
{
  my $comp = Imager->new;
  $comp->read(file => "testimg/pal43232.ppm")
    or skip "could not read 4-bit comparison file:". $comp->errstr, 1;
  is(Imager::i_img_diff($comp->{IMG}, $im->{IMG}), 0,
     "compare image data");
}

$im->write(file=>'testout/pal43232.ppm');
ok($im->read(file => 'testimg/pal13232.ico', type=>'ico', ico_masked => 0),
   "read 1 bit")
  or print "# ", $im->errstr, "\n";
is($im->getwidth, 32, "check width");
is($im->getwidth, 32, "check height");
is($im->type, 'paletted', "check type");
is($im->colorcount, 2, "color count");
is($im->tags(name => 'cur_bits'), 1, "check ico_bits tag");
is($im->tags(name => 'i_format'), 'cur', "check i_format tag");
$im->write(file=>'testout/pal13232.ppm');

# combo was created with the GIMP, which has a decent mechanism for selecting
# the output format
# you get different size icon images by making different size layers.
my @imgs = Imager->read_multi(file => 'testimg/combo.ico', type=>'ico', 
			      ico_masked => 0);
is(scalar(@imgs), 3, "read multiple");
is($imgs[0]->getwidth, 48, "image 0 width");
is($imgs[0]->getheight, 48, "image 0 height");
is($imgs[1]->getwidth, 32, "image 1 width");
is($imgs[1]->getheight, 32, "image 1 height");
is($imgs[2]->getwidth, 16, "image 2 width");
is($imgs[2]->getheight, 16, "image 2 height");
is($imgs[0]->type, 'direct', "image 0 type");
is($imgs[1]->type, 'paletted', "image 1 type");
is($imgs[2]->type, 'paletted', "image 2 type");
is($imgs[1]->colorcount, 256, "image 1 colorcount");
is($imgs[2]->colorcount, 16, "image 2 colorcount");

is_deeply([ $imgs[0]->getpixel(x=>0, 'y'=>0)->rgba ], [ 231, 17, 67, 255 ],
	  "check image data 0(0,0)");
is_deeply([ $imgs[1]->getpixel(x=>0, 'y'=>0)->rgba ], [ 231, 17, 67, 255 ],
	  "check image data 1(0,0)");
is_deeply([ $imgs[2]->getpixel(x=>0, 'y'=>0)->rgba ], [ 231, 17, 67, 255 ],
	  "check image data 2(0,0)");

is_deeply([ $imgs[0]->getpixel(x=>47, 'y'=>0)->rgba ], [ 131, 231, 17, 255 ],
	  "check image data 0(47,0)");
is_deeply([ $imgs[1]->getpixel(x=>31, 'y'=>0)->rgba ], [ 131, 231, 17, 255 ],
	  "check image data 1(31,0)");
is_deeply([ $imgs[2]->getpixel(x=>15, 'y'=>0)->rgba ], [ 131, 231, 17, 255 ],
	  "check image data 2(15,0)");

is_deeply([ $imgs[0]->getpixel(x=>0, 'y'=>47)->rgba ], [ 17, 42, 231, 255 ],
	  "check image data 0(0,47)");
is_deeply([ $imgs[1]->getpixel(x=>0, 'y'=>31)->rgba ], [ 17, 42, 231, 255 ],
	  "check image data 1(0,31)");
is_deeply([ $imgs[2]->getpixel(x=>0, 'y'=>15)->rgba ], [ 17, 42, 231, 255 ],
	  "check image data 2(0,15)");

is_deeply([ $imgs[0]->getpixel(x=>47, 'y'=>47)->rgba ], [ 17, 231, 177, 255 ],
	  "check image data 0(47,47)");
is_deeply([ $imgs[1]->getpixel(x=>31, 'y'=>31)->rgba ], [ 17, 231, 177, 255 ],
	  "check image data 1(31,31)");
is_deeply([ $imgs[2]->getpixel(x=>15, 'y'=>15)->rgba ], [ 17, 231, 177, 255 ],
	  "check image data 2(15,15)");

$im = Imager->new(xsize=>32, ysize=>32);
$im->box(filled=>1, color=>'FF0000');
$im->box(filled=>1, color=>'0000FF', xmin => 6, ymin=>0, xmax => 21, ymax=>15);
$im->box(filled=>1, color=>'00FF00', xmin => 10, ymin=>16, xmax => 25, ymax=>31);

ok($im->write(file=>'testout/t10_32.ico', type=>'ico'),
   "write 32-bit icon");

my $im2 = Imager->new;
ok($im2->read(file=>'testout/t10_32.ico', type=>'ico', ico_masked => 0),
   "read it back in");

is(Imager::i_img_diff($im->{IMG}, $im2->{IMG}), 0,
   "check they're the same");
is($im->bits, $im2->bits, "check same bits");

{
  my $im = Imager->new(xsize => 32, ysize => 32);
  $im->box(filled=>1, color=>'#FF00FF');
  my $data;
  ok(Imager->write_multi({ data => \$data, type=>'ico' }, $im, $im),
     "write multi icons");
  ok(length $data, "and it wrote data");
  my @im = Imager->read_multi(data => $data, ico_masked => 0);
  is(@im, 2, "got all the images back");
  is(Imager::i_img_diff($im->{IMG}, $im[0]{IMG}), 0, "check first image");
  is(Imager::i_img_diff($im->{IMG}, $im[1]{IMG}), 0, "check second image");
}

{ # 1 channel image
  my $im = Imager->new(xsize => 32, ysize => 32, channels => 1);
  $im->box(filled=>1, color => [ 128, 0, 0 ]);
  my $data;
  ok($im->write(data => \$data, type=>'ico'), "write 1 channel image");
  my $im2 = Imager->new;
  ok($im2->read(data => $data, ico_masked => 0), "read it back");
  is($im2->getchannels, 4, "check channels");
  my $imrgb = $im->convert(preset => 'rgb')
    ->convert(preset => 'addalpha');
  is(Imager::i_img_diff($imrgb->{IMG}, $im2->{IMG}), 0,
     "check image matches expected");
}

{ # 2 channel image
  my $base = Imager->new(xsize => 32, ysize => 32, channels => 2);
  $base->box(filled => 1, color => [ 64, 192, 0 ]);
  my $data;
  ok($base->write(data => \$data, type=>'ico'), "write 2 channel image");
  my $read = Imager->new;
  ok($read->read(data => $data, ico_masked => 0), "read it back");
  is($read->getchannels, 4, "check channels");
  my $imrgb = $base->convert(preset => 'rgb');
  is(Imager::i_img_diff($imrgb->{IMG}, $read->{IMG}), 0,
     "check image matches expected");
}

{ # 4 channel image
  my $base = Imager->new(xsize => 32, ysize => 32, channels => 4);
  $base->box(filled=>1, ymax => 15, color => [ 255, 0, 255, 128 ]);
  $base->box(filled=>1, ymin => 16, color => [ 0, 255, 255, 255 ]);
  my $data;
  ok($base->write(data => \$data, type=>'ico'), "write 4 channel image");
  my $read = Imager->new;
  ok($read->read(data => $data, type=>'ico', ico_masked => 0), "read it back")
    or print "# ", $read->errstr, "\n";
  is(Imager::i_img_diff($base->{IMG}, $read->{IMG}), 0,
     "check image matches expected");
}

{ # mask handling
  my $base = Imager->new(xsize => 16, ysize => 16, channels => 3);
  $base->box(filled=>1, xmin => 5, xmax => 10, color => '#0000FF');
  $base->box(filled=>1, ymin => 5, ymax => 10, color => '#0000FF');
  my $mask = <<EOS; # CR in this to test it's skipped correctly
01
0000011111100000
00000111111 00000xx
00000111111000  
00000111111000
0000011111100000
1111111111111111
1111111111111111
1111111111111111
1111111111111111
1111111111111111
1111111111111111
1010101010101010
1010101010101010
1010101010101010
1010101010101010
1010101010101010
EOS
  $mask =~ s/\n/\r\n/g; # to test alternate newline handling is correct
  $base->settag(name => 'ico_mask', value => $mask);
  my $saved_mask = $base->tags(name => 'ico_mask');
  my $data;
  ok($base->write(data => \$data, type => 'ico'),
     "write with mask tag set");
  my $read = Imager->new;
  ok($read->read(data => $data, ico_masked => 0), "read it back");
  my $mask2 = $mask;
  $mask2 =~ tr/01/.*/;
  $mask2 =~ s/\n$//;
  $mask2 =~ tr/\r x//d;
  $mask2 =~ s/^(.{3,19})$/$1 . "." x (16 - length $1)/gem;
  my $read_mask = $read->tags(name => 'ico_mask');
  is($read_mask, $mask2, "check mask is correct");
}

{ # mask too short to handle
  my $mask = "xx";
  my $base = Imager->new(xsize => 16, ysize => 16, channels => 3);
  $base->box(filled=>1, xmin => 5, xmax => 10, color => '#0000FF');
  $base->box(filled=>1, ymin => 5, ymax => 10, color => '#0000FF');
  $base->settag(name => 'ico_mask', value => $mask);
  my $data;
  ok($base->write(data => \$data, type=>'ico'),
     "save icon with short mask tag");
  my $read = Imager->new;
  ok($read->read(data => $data, ico_masked => 0), "read it back");
  my $read_mask = $read->tags(name => 'ico_mask');
  my $expected_mask = ".*" . ( "\n" . "." x 16 ) x 16;
  is($read_mask, $expected_mask, "check the mask");

  # mask that doesn't match what we expect
  $base->settag(name => 'ico_mask', value => 'abcd');
  ok($base->write(data => \$data, type => 'ico'), 
     "write with bad format mask tag");
  ok($read->read(data => $data, ico_masked => 0), "read it back");
  $read_mask = $read->tags(name => 'ico_mask');
  is($read_mask, $expected_mask, "check the mask");

  # mask with invalid char
  $base->settag(name => 'ico_mask', value => ".*\n....xxx..");
  ok($base->write(data => \$data, type => 'ico'), 
     "write with unexpected chars in mask");
  ok($read->read(data => $data, ico_masked => 0), "read it back");
  $read_mask = $read->tags(name => 'ico_mask');
  is($read_mask, $expected_mask, "check the mask");
}

{ # check handling of greyscale paletted
  my $base = Imager->new(xsize => 16, ysize => 16, channels => 1, 
                         type => 'paletted');
  my @grays = map Imager::Color->new($_),
    "000000", "666666", "CCCCCC", "FFFFFF";
  ok($base->addcolors(colors => \@grays), "add some colors");
  $base->box(filled => 1, color => $grays[1], xmax => 7, ymax => 7);
  $base->box(filled => 1, color => $grays[1], xmax => 7, ymin => 8);
  $base->box(filled => 1, color => $grays[1], xmin => 8, ymax => 7);
  $base->box(filled => 1, color => $grays[1], xmin => 8, ymax => 8);
  my $data;
  ok($base->write(data => \$data, type => 'ico'),
     "write grayscale paletted");
  my $read = Imager->new;
  ok($read->read(data => $data, ico_masked => 0), "read it back")
    or print "# ", $read->errstr, "\n";
  is($read->type, 'paletted', "check type");
  is($read->getchannels, 3, "check channels");
  my $as_rgb = $base->convert(preset => 'rgb');
  is(Imager::i_img_diff($base->{IMG}, $read->{IMG}), 0,
     "check the image");
}

{
  # check default mask processing
  #
  # the query at http://www.cpanforum.com/threads/5958 made it fairly
  # obvious that the way Imager handled the mask in 0.59 was confusing
  # when compared with loading other images with some sort of
  # secondary alpha channel (eg. gif)
  # So from 0.60 the mask is applied as an alpha channel by default.
  # make sure that application works.

  # the strange mask checks the optimization paths of the mask application
  my $mask = <<EOS;
01
1001
1100
0011
0000
0010
EOS
  chomp $mask;
  my $im = Imager->new(xsize => 4, ysize => 5, type => 'paletted');
  $im->addcolors(colors => [ '#FF0000' ]);
  $im->box(filled => 1, color => '#FF0000');
  $im->settag(name => 'ico_mask', value => $mask);
  my $imcopy = $im->convert(preset=>'addalpha');
  my $red_alpha = Imager::Color->new(255, 0, 0, 0);
  $imcopy->setpixel( 'x' => [ qw/0 3 0 1 2 3 2/ ],
		     'y' => [ qw/0 0 1 1 2 2 4/ ],
		     color => $red_alpha);
  my $data;
  ok($im->write(data => \$data, type => 'ico'),
     "save icon + mask");
  my $im2 = Imager->new;
  ok($im2->read(data => $data), "read ico with defaults");
  is($im2->type, 'direct', 'expect a direct image');
  is_image($im2, $imcopy, 'check against expected');
}

{
  # read 24-bit images
  my $im = Imager->new;
  ok($im->read(file => 'testimg/rgb1616.ico'), "read 24-bit data image")
    or print "# ", $im->errstr, "\n";
  my $vs = Imager->new(xsize => 16, ysize => 16);
  $vs->box(filled => 1, color => '#333366');
  is_image($im, $vs, "check we got the right colors");
}


{ # check close failures are handled correctly
  my $im = test_image();
  my $fail_close = sub {
    Imager::i_push_error(0, "synthetic close failure");
    return 0;
  };
  ok(!$im->write(type => "ico", callback => sub { 1 },
		 closecb => $fail_close),
     "check failing close fails");
    like($im->errstr, qr/synthetic close failure/,
	 "check error message");
}

{ # RT #69599
  {
    my $ico = Imager->new(file => "testimg/pal256.ico", filetype => "ico");
    ok($ico, "read a 256x256 pixel wide/high icon")
      or diag "Could not read 256x256 pixel icon: ",Imager->errstr;
  }
  SKIP:
  {
    my $im = test_image();
    my $sc = $im->scale(xpixels => 256, ypixels => 256, type => "nonprop")
      or diag("Cannot scale: " . $im->errstr);
    $sc
      or skip("Cannot produce scaled image", 3);
    my $alpha = $sc->convert(preset => "addalpha")
      or diag "Cannot add alpha channel: " . $sc->errstr ;
    
    my $data;
    ok($alpha->write(data => \$data, type => "ico"),
       "save 256x256 image")
      or diag("Cannot save 256x256 icon:" . $alpha->errstr);
    my $read = Imager->new(data => $data, filetype => "ico");
    ok($read, "read 256x256 pixel image back in")
      or diag(Imager->errstr);
    $read
      or skip("Couldn't read to compare", 1);
    is_image($read, $alpha, "check we read what we wrote");
  }
}

