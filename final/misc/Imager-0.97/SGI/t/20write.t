#!perl -w
use strict;
use Imager;
use Test::More tests => 57;
use Imager::Test qw(test_image test_image_16 is_image);
use IO::Seekable;

-d 'testout' or mkdir 'testout', 0777;

Imager::init_log('testout/20write.log', 2);

{
  my $im = test_image();
  $im->line(x1 => 0, y1 => 0, x2 => 150, y2 => 150, color => 'FF0000');
  ok($im->write(file => 'testout/20verb.rgb'), "write 8-bit verbatim")
    or print "# ", $im->errstr, "\n";
  my $im2 = Imager->new;
  ok($im2->read(file => 'testout/20verb.rgb'), "read it back")
    or print "# ", $im2->errstr, "\n";
  is_image($im, $im2, "compare");
  is($im2->tags(name => 'sgi_rle'), 0, "check not rle");
  is($im2->tags(name => 'sgi_bpc'), 1, "check bpc");
  is($im2->tags(name => 'i_comment'), undef, "no namestr");
  
  ok($im->write(file => 'testout/20rle.rgb', 
		sgi_rle => 1, 
		i_comment => "test"), "write 8-bit rle")
    or print "# ", $im->errstr, "\n";
  my $im3 = Imager->new;
  ok($im3->read(file => 'testout/20rle.rgb'), "read it back")
    or print "# ", $im3->errstr, "\n";
  is_image($im, $im3, "compare");
  is($im3->tags(name => 'sgi_rle'), 1, "check not rle");
  is($im3->tags(name => 'sgi_bpc'), 1, "check bpc");
  is($im3->tags(name => 'i_comment'), 'test', "check i_comment set");
}

{
  my $im = test_image_16();
  $im->line(x1 => 0, y1 => 0, x2 => 150, y2 => 150, color => 'FF0000');
  ok($im->write(file => 'testout/20verb16.rgb'), "write 16-bit verbatim")
    or print "# ", $im->errstr, "\n";
  my $im2 = Imager->new;
  ok($im2->read(file => 'testout/20verb16.rgb'), "read it back")
    or print "# ", $im2->errstr, "\n";
  is_image($im, $im2, "compare");
  is($im2->tags(name => 'sgi_rle'), 0, "check not rle");
  is($im2->tags(name => 'sgi_bpc'), 2, "check bpc");
  is($im2->tags(name => 'i_comment'), undef, "no namestr");
  
  ok($im->write(file => 'testout/20rle16.rgb', 
		sgi_rle => 1, 
		i_comment => "test"), "write 16-bit rle")
    or print "# ", $im->errstr, "\n";
  my $im3 = Imager->new;
  ok($im3->read(file => 'testout/20rle16.rgb'), "read it back")
    or print "# ", $im3->errstr, "\n";
  is_image($im, $im3, "compare");
  is($im3->tags(name => 'sgi_rle'), 1, "check not rle");
  is($im3->tags(name => 'sgi_bpc'), 2, "check bpc");
  is($im3->tags(name => 'i_comment'), 'test', "check i_comment set");

  my $imbig = Imager->new(xsize => 300, ysize => 300, bits => 16);
  $imbig->paste(src => $im, tx => 0,   ty => 0);
  $imbig->paste(src => $im, tx => 150, ty => 0);
  $imbig->paste(src => $im, tx => 0,   ty => 150);
  $imbig->paste(src => $im, tx => 150, ty => 150);
  for my $t (0 .. 74) {
    $imbig->line(x1 => $t*4, y1 => 0, x2 => 3+$t*4, y2 => 299, 
		 color => [ 255 - $t, 0, 0 ]);
  }
  my $data;
  ok($imbig->write(data => \$data, type => 'sgi', sgi_rle => 1),
     "write larger image");
  cmp_ok(length($data), '>', 0x10000, "check output large enough for test");
  print "# ", length $data, "\n";
  my $imbigcmp = Imager->new;
  ok($imbigcmp->read(data => $data), "read larger image");
  is_image($imbig, $imbigcmp, "check large image matches");
}

{
  # grey scale check
  my $im = test_image()->convert(preset=>'grey');
  ok($im->write(file => 'testout/20vgray8.bw'), "write 8-bit verbatim grey")
    or print "# ", $im->errstr, "\n";
  my $im2 = Imager->new;
  ok($im2->read(file => 'testout/20vgray8.bw'), "read it back")
    or print "# ", $im2->errstr, "\n";
  is_image($im, $im2, "compare");
  is($im2->tags(name => 'i_format'), 'sgi', "check we saved as SGI");
  is($im2->tags(name => 'sgi_rle'), 0, "check not rle");
  is($im2->tags(name => 'sgi_bpc'), 1, "check bpc");
  is($im2->tags(name => 'i_comment'), undef, "no namestr");
}

{
  # write failure tests
  my $rgb8 = test_image();
  my $rgb16 = test_image_16();
  my $rgb8rle = $rgb8->copy;
  $rgb8rle->settag(name => 'sgi_rle', value => 1);
  my $grey8 = $rgb8->convert(preset => 'grey');
  my $grey16 = $rgb16->convert(preset => 'grey');
  my $grey16rle = $grey16->copy;
  $grey16rle->settag(name => 'sgi_rle', value => 1);

  my @tests =
    (
     # each entry is: image, limit, expected msg, description
     [ 
      $rgb8, 500, 
      'SGI image: cannot write header', 
      'writing header' 
     ],
     [ 
      $rgb8, 1024, 
      'SGI image: error writing image data', 
      '8-bit image data' 
     ],
     [
      $grey8, 513,
      'SGI image: error writing image data',
      '8-bit image data (grey)'
     ],
     [
      $rgb8rle, 513,
      'SGI image: error writing offsets/lengths',
      'rle tables, 8 bit',
     ],
     [
      $rgb8rle, 4112,
      'SGI image: error writing RLE data',
      '8-bit rle data',
     ],
     [
      $rgb8rle, 14707,
      'SGI image: cannot write final RLE table',
      '8-bit rewrite RLE table',
     ],
     [
      $rgb16, 513,
      'SGI image: error writing image data',
      '16-bit image data',
     ],
     [
      $grey16rle, 513,
      'SGI image: error writing offsets/lengths',
      'rle tables, 16 bit',
     ],
     [
      $grey16rle, 1713,
      'SGI image: error writing RLE data',
      '16-bit rle data',
     ],
     [
      $grey16rle, 10871,
      'SGI image: cannot write final RLE table',
      '16-bit rewrite RLE table',
     ],
    );
  for my $test (@tests) {
    my ($im, $limit, $expected_msg, $desc) = @$test;
    my $io = limited_write_io($limit);
    ok(!$im->write(type => 'sgi', io => $io),
       "write should fail - $desc");
    is($im->errstr, "$expected_msg: limit reached", "check error - $desc");
  }
}


{ # check close failures are handled correctly
  my $im = test_image();
  my $fail_close = sub {
    Imager::i_push_error(0, "synthetic close failure");
    return 0;
  };
  ok(!$im->write(type => "sgi", callback => sub { 1 },
		 closecb => $fail_close),
     "check failing close fails");
    like($im->errstr, qr/synthetic close failure/,
	 "check error message");
}

sub limited_write_io {
  my ($limit) = @_;

  my ($writecb, $seekcb) = limited_write($limit);

  my $io = Imager::io_new_cb($writecb, undef, $seekcb, undef, 1);
  $io->set_buffered(0);

  return $io;
}

sub limited_write {
  my ($limit) = @_;

  my $pos = 0;
  my $written = 0;
  return
    (
     # write callback
     sub {
       my ($data) = @_;
       # limit total written so we can fail the offset table write for RLE
       $written += length $data;
       if ($written <= $limit) {
	 $pos += length $data;
         print "# write of ", length $data, " bytes successful (", 
	   $limit - $written, " left)\n";
         return 1;
       }
       else {
         print "# write of ", length $data, " bytes failed\n";
         Imager::i_push_error(0, "limit reached");
         return;
       }
     },
     # seek cb
     sub {
       my ($position, $whence) = @_;

       if ($whence == SEEK_SET) {
	 $pos = $position;
	 print "# seek to $pos\n";
       }
       elsif ($whence == SEEK_END) {
	 die "SEEK_END not supported\n";
       }
       elsif ($whence == SEEK_CUR) {
	 die "SEEK_CUR not supported\n";
       }
       else {
	 die "Invalid seek whence $whence";
       }

       $pos;
     }
    )
}
