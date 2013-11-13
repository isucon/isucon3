#!perl -w
use strict;
use Imager;
use Imager::Test qw(is_image is_color3);
use Test::More tests => 103;

-d 'testout' or mkdir 'testout', 0777;

Imager::init_log('testout/10read.log', 2);

{
  my $im_verb = Imager->new;
  ok($im_verb->read(file => 'testimg/verb.rgb'), "read verbatim")
    or print "# ", $im_verb->errstr, "\n";
  is($im_verb->getchannels, 3, "check channels");
  is($im_verb->getwidth, 20, "check width");
  is($im_verb->getheight, 20, "check height");
  is_color3($im_verb->getpixel(x => 0, 'y' => 0), 255, 0, 0, "check 0,0");
  is_color3($im_verb->getpixel(x => 1, 'y' => 2), 255, 255, 0, "check 0,2");
  is_color3($im_verb->getpixel(x => 2, 'y' => 4), 0, 255, 255, "check 2,5");
  is($im_verb->tags(name => 'i_format'), 'sgi', "check i_format tag");
  is($im_verb->tags(name => 'sgi_rle'), 0, "check sgi_rgb");
  is($im_verb->tags(name => 'sgi_pixmin'), 0, "check pixmin");
  is($im_verb->tags(name => 'sgi_pixmax'), 255, "check pixmax");
  is($im_verb->tags(name => 'sgi_bpc'), 1, "check bpc");
  is($im_verb->tags(name => 'i_comment'), 'test image', 
     "check name string");

  my $im_rle = Imager->new;
  ok($im_rle->read(file => 'testimg/rle.rgb'), "read rle")
    or print "# ", $im_rle->errstr, "\n";
  is($im_rle->tags(name => 'sgi_rle'), 1, "check sgi_rgb");

  my $im_rleagr = Imager->new;
  ok($im_rleagr->read(file => 'testimg/rleagr.rgb'), "read rleagr")
    or print "# ", $im_rleagr->errstr, "\n";

  my $im6 = Imager->new;
  ok($im6->read(file => 'testimg/verb6.rgb'), "read verbatim 6-bit")
    or print "# ", $im6->errstr, "\n";
  is($im6->tags(name => 'sgi_pixmax'), 63, "check pixmax");

  is_image($im_verb, $im_rle, "compare verbatim to rle");
  is_image($im_verb, $im_rleagr, "compare verbatim to rleagr");
  is_image($im_verb, $im6, "compare verbatim to verb 6-bit");

  my $im_verb12 = Imager->new;
  ok($im_verb12->read(file => 'testimg/verb12.rgb'), "read verbatim 12")
    or print "# ", $im_verb12->errstr, "\n";
  is($im_verb12->bits, 16, "check bits on verb12");
  is($im_verb12->tags(name => 'sgi_pixmax'), 4095, "check pixmax");

  my $im_verb16 = Imager->new;
  ok($im_verb16->read(file => 'testimg/verb16.rgb'), "read verbatim 16")
    or print "# ", $im_verb16->errstr, "\n";
  is($im_verb16->bits, 16, "check bits on verb16");
  is($im_verb16->tags(name => 'sgi_pixmax'), 65535, "check pixmax");
  
  is_image($im_verb, $im_verb12, "compare verbatim to verb12");
  is_image($im_verb, $im_verb16, "compare verbatim to verb16");

  my $im_rle6 = Imager->new;
  ok($im_rle6->read(file => 'testimg/rle6.rgb'), "read rle 6 bit");
  is($im_rle6->tags(name => 'sgi_pixmax'), 63, 'check pixmax');
  is_image($im_verb, $im_rle6, 'compare verbatim to rle6');
  
  my $im_rle12 = Imager->new;
  ok($im_rle12->read(file => 'testimg/rle12.rgb'), 'read rle 12 bit')
    or print "# ", $im_rle12->errstr, "\n";
  is($im_rle12->tags(name => 'sgi_pixmax'), 4095, 'check pixmax');
  is_image($im_verb, $im_rle12, 'compare verbatim to rle12');

  my $im_rle16 = Imager->new;
  ok($im_rle16->read(file => 'testimg/rle16.rgb'), 'read rle 16 bit')
    or print "# ", $im_rle16->errstr, "\n";
  is($im_rle16->tags(name => 'sgi_pixmax'), 65535, 'check pixmax');
  is($im_rle16->tags(name => 'sgi_bpc'), 2, "check bpc");
  is_image($im_verb, $im_rle16, 'compare verbatim to rle16');
}

{
  # short read tests, each is source file, limit, match, description
  my @tests =
    (
     [ 
      'verb.rgb', 100, 
      'SGI image: could not read header', 'header',
     ],
     [ 
      'verb.rgb', 512, 
       'SGI image: cannot read image data', 
       'verbatim image data' 
     ],
     [
      'rle.rgb', 512,
      'SGI image: short read reading RLE start table',
      'rle start table'
     ],
     [
      'rle.rgb', 752,
      'SGI image: short read reading RLE length table',
      'rle length table'
     ],
     [
      'rle.rgb', 0x510,
      "SGI image: cannot read RLE data",
      'read rle data'
     ],
     [
      'rle.rgb', 0x50E,
      "SGI image: cannot seek to RLE data",
      'seek rle data'
     ],
     [
      'verb16.rgb', 512,
      'SGI image: cannot read image data',
      'read image data (16-bit)'
     ],
     [
      'rle16.rgb', 512,
      'SGI image: short read reading RLE start table',
      'rle start table (16-bit)',
     ],
     [
      'rle16.rgb', 0x42f,
      'SGI image: cannot seek to RLE data',
      'seek RLE data (16-bit)'
     ],
     [
      'rle16.rgb', 0x64A,
      'SGI image: cannot read RLE data',
      'read rle image data (16-bit)'
     ],
    );
  for my $test (@tests) {
    my ($src, $size, $match, $desc) = @$test;
    open SRC, "< testimg/$src"
      or die "Cannot open testimg/$src: $!";
    binmode SRC;
    my $data;
    read(SRC, $data, $size) == $size
      or die "Could not read $size bytes from $src";
    close SRC;
    my $im = Imager->new;
    ok(!$im->read(data => $data, type => 'sgi'),
       "read: $desc");
    is($im->errstr, $match, "error match: $desc");
  }
}

{
  # each entry is: source file, patches, expected error, description
  my @tests =
    (
     [
      'verb.rgb',
      { 0 => '00 00' },
      'SGI image: invalid magic number',
      'bad magic',
     ],
     [
      'verb.rgb',
      { 104 => '00 00 00 01' },
      'SGI image: invalid value for colormap (1)',
      'invalid colormap field',
     ],
     [
      'verb.rgb',
      { 3 => '03' },
      'SGI image: invalid value for BPC (3)',
      'invalid bpc field',
     ],
     [
      'verb.rgb',
      { 2 => '03' },
      'SGI image: invalid storage type field',
      'invalid storage type field',
     ],
     [
      'verb.rgb',
      { 4 => '00 04' },
      'SGI image: invalid dimension field',
      'invalid dimension field',
     ],
     [
      'rle.rgb',
      { 0x2f0 => '00 00 00 2b' },
      'SGI image: ridiculous RLE line length 43',
      'invalid rle length',
     ],
     [
      'rle.rgb',
      { 0x3E0 => '95' },
      'SGI image: literal run overflows scanline',
      'literal run overflow scanline',
     ],
     [
      'rle.rgb',
      { 0x3E0 => '87' },
      'SGI image: literal run consumes more data than available',
      'literal run consuming too much data',
     ],
     [
      'rle.rgb',
      { 0x3E0 => '15' },
      'SGI image: RLE run overflows scanline',
      'RLE run overflows scanline',
     ],
     [
      'rle.rgb',
      { 0x3E0 => '81 FF 12 00 01' },
      'SGI image: RLE run has no data for pixel',
      'RLE run has no data for pixel',
     ],
     [
      'rle.rgb',
      { 0x3E0 => '81 FF 12 00' },
      'SGI image: incomplete RLE scanline',
      'incomplete RLE scanline',
     ],
     [
      'rle.rgb',
      { 0x2F0 => '00 00 00 06' },
      'SGI image: unused RLE data',
      'unused RLE data',
     ],
     [
      'verb.rgb',
      { 0x0c => '00 00 00 FF 00 00 00 00' },
      'SGI image: invalid pixmin >= pixmax',
      'bad pixmin/pixmax',
     ],
     [
      'rle16.rgb',
      { 0x2f0 => '00 00 00 0B' },
      'SGI image: invalid RLE length value for BPC=2',
      'bad RLE table (length) (bpc=2)'
     ],
     [
      'rle16.rgb',
      { 0x2f0 => '00 00 00 53' },
      'SGI image: ridiculous RLE line length 83',
      'way too big RLE line length (16-bit)'
     ],
     [
      'rle16.rgb',
      { 0x426 => '00 95' },
      'SGI image: literal run overflows scanline',
      'literal overflow scanline (bpc=2)'
     ],
     [
      'rle16.rgb',
      { 0x426 => '00 93' },
      'SGI image: literal run consumes more data than available',
      'literal overflow data (bpc=2)'
     ],
     [
      'rle16.rgb',
      { 0x3EA => '00 15' },
      'SGI image: RLE run overflows scanline',
      'rle overflow scanline (bpc=2)'
     ],
     [
      'rle16.rgb',
      { 0x3EA => '00 15' },
      'SGI image: RLE run overflows scanline',
      'rle overflow scanline (bpc=2)'
     ],
     [
      'rle16.rgb',
      { 0x3EA => '00 83 ff ff ff ff ff ff 00 01' },
      'SGI image: RLE run has no data for pixel',
      'rle code no argument (bpc=2)'
     ],
     [
      'rle16.rgb',
      { 0x3EA => '00 14 ff ff 00 00' },
      'SGI image: unused RLE data',
      'unused RLE data (bpc=2)'
     ],
     [
      'rle16.rgb',
      { 0x3EA => '00 12 ff ff' },
      'SGI image: incomplete RLE scanline',
      'incomplete rle scanline (bpc=2)'
     ],
    );

  # invalid file tests - take our original files and patch them a
  # little to make them invalid
    my $test_index = 0;
  for my $test (@tests) {
    my ($filename, $patches, $error, $desc) = @$test;

    my $data = load_patched_file("testimg/$filename", $patches);
    my $im = Imager->new;
    ok(!$im->read(data => $data, type=>'sgi'),
       "$test_index - $desc:should fail to read");
    is($im->errstr, $error, "$test_index - $desc:check message");
    ++$test_index;
  }
}

sub load_patched_file {
  my ($filename, $patches) = @_;

  open IMDATA, "< $filename"
    or die "Cannot open $filename: $!";
  binmode IMDATA;
  my $data = do { local $/; <IMDATA> };
  for my $offset (keys %$patches) {
    (my $hdata = $patches->{$offset}) =~ tr/ //d;
    my $pdata = pack("H*", $hdata);
    substr($data, $offset, length $pdata) = $pdata;
  }

  return $data;
}
