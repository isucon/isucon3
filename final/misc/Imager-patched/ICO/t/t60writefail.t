#!perl -w
use strict;
use Test::More tests => 69;
use Imager ':handy';

# this file tries to cover as much of the write error handling cases in 
# msicon.c/imicon.c as possible.
#
# coverage checked with gcc/gcov

# image too big for format tests, for each entry point
{
  my $im = Imager->new(xsize => 257, ysize => 256);
  my $data;
  ok(!$im->write(data => \$data, type=>'ico'),
     "image too large");
  is($im->errstr, "image too large for ico file", "check message");
}

{
  my $im = Imager->new(xsize => 257, ysize => 256);
  my $data;
  ok(!Imager->write_multi({ data => \$data, type=>'ico' }, $im, $im),
     "image too large");
  is(Imager->errstr, "image too large for ico file", "check message");
  Imager->_set_error('');
}

{
  my $im = Imager->new(xsize => 257, ysize => 256);
  my $data;
  ok(!$im->write(data => \$data, type=>'cur'),
     "image too large");
  is($im->errstr, "image too large for ico file", "check message");
}

{
  my $im = Imager->new(xsize => 257, ysize => 256);
  my $data;
  ok(!Imager->write_multi({ data => \$data, type=>'cur' }, $im),
     "image too large");
  is(Imager->errstr, "image too large for ico file", "check message");
  Imager->_set_error('');
}

# low level write failure tests for each entry point (fail on close)
{
  my $im = Imager->new(xsize => 10, ysize => 10);
  ok(!$im->write(callback => \&write_failure, type=>'ico'),
     "low level write failure (ico)");
  is($im->errstr, "error closing output: synthetic error", "check message");
}

{
  my $im = Imager->new(xsize => 10, ysize => 10);
  ok(!$im->write(callback => \&write_failure, type=>'cur'),
     "low level write failure (cur)");
  is($im->errstr, "error closing output: synthetic error", "check message");
}

{
  my $im = Imager->new(xsize => 10, ysize => 10);
  ok(!Imager->write_multi({ callback => \&write_failure, type=>'ico' }, $im, $im),
     "low level write_multi failure (ico)");
  is(Imager->errstr, "error closing output: synthetic error", "check message");
  Imager->_set_error('');
}

{
  my $im = Imager->new(xsize => 10, ysize => 10);
  ok(!Imager->write_multi({ callback => \&write_failure, type=>'cur' }, $im, $im),
     "low level write_multi failure (cur)");
  is(Imager->errstr, "error closing output: synthetic error", "check message");
  Imager->_set_error('');
}

# low level write failure tests for each entry point (fail on write)
{
  my $im = Imager->new(xsize => 10, ysize => 10);
  my $io = Imager::io_new_cb(\&write_failure, undef, undef, undef, 1);
  $io->set_buffered(0);
  ok(!$im->write(io => $io, type=>'ico'),
     "low level write failure (ico)");
  is($im->errstr, "Write failure: synthetic error", "check message");
}

{
  my $im = Imager->new(xsize => 10, ysize => 10);
  my $io = Imager::io_new_cb(\&write_failure, undef, undef, undef, 1);
  $io->set_buffered(0);
  ok(!$im->write(io => $io, type=>'cur'),
     "low level write failure (cur)");
  is($im->errstr, "Write failure: synthetic error", "check message");
}

{
  my $im = Imager->new(xsize => 10, ysize => 10);
  my $io = Imager::io_new_cb(\&write_failure, undef, undef, undef, 1);
  $io->set_buffered(0);
  ok(!Imager->write_multi({ io => $io, type=>'ico' }, $im, $im),
     "low level write_multi failure (ico)");
  is(Imager->errstr, "Write failure: synthetic error", "check message");
  Imager->_set_error('');
}

{
  my $im = Imager->new(xsize => 10, ysize => 10);
  my $io = Imager::io_new_cb(\&write_failure, undef, undef, undef, 1);
  $io->set_buffered(0);
  ok(!Imager->write_multi({ io => $io, type=>'cur' }, $im, $im),
     "low level write_multi failure (cur)");
  is(Imager->errstr, "Write failure: synthetic error", "check message");
  Imager->_set_error('');
}

{
  my $im = Imager->new(xsize => 10, ysize => 10);
  ok(!$im->write(type => 'ico', io => limited_write_io(6)),
     "second write (resource) should fail (ico)");
  is($im->errstr, "Write failure: limit reached", "check message");
  $im->_set_error('');

  ok(!$im->write(type => 'cur', io => limited_write_io(6)),
     "second (resource) write should fail (cur)");
  is($im->errstr, "Write failure: limit reached", "check message");
  $im->_set_error('');

  ok(!$im->write(type => 'ico', io => limited_write_io(22)),
     "third write (bmi) should fail (32-bit)");
  is($im->errstr, "Write failure: limit reached", "check message");
  $im->_set_error('');

  ok(!$im->write(type => 'ico', io => limited_write_io(62)),
     "fourth write (data) should fail (32-bit)");
  is($im->errstr, "Write failure: limit reached", "check message");
  $im->_set_error('');

  ok(!$im->write(type => 'ico', io => limited_write_io(462)),
     "mask write should fail (32-bit)");
  is($im->errstr, "Write failure: limit reached", "check message");
}

{ # 1 bit write fails
  my $im = Imager->new(xsize => 10, ysize => 10, type => 'paletted');
  my $red = NC(255, 0, 0);
  my $blue = NC(0, 0, 255);
  $im->addcolors(colors => [ $red, $blue ]);
  $im->box(filled => 1, color => $red, ymax => 5);
  $im->box(filled => 1, color => $blue, ymin => 6);
  ok(!$im->write(type => 'ico', io => limited_write_io(22)),
     "third write (bmi) should fail (1-bit)");
  is($im->errstr, "Write failure: limit reached", "check message");
  
  ok(!$im->write(type => 'ico', io => limited_write_io(66)),
     "fourth write (palette) should fail (1-bit)");
  is($im->errstr, "Write failure: limit reached", "check message");
  ok(!$im->write(type => 'ico', io => limited_write_io(74)),
     "fifth write (image) should fail (1-bit)");
  is($im->errstr, "Write failure: limit reached", "check message");
  my $data;
  ok($im->write(data => \$data, type => 'ico'), "write 1 bit successfully");
  my $read = Imager->new;
  ok($read->read(data => $data), "read it back");
  is($read->type, 'paletted', "check type");
  is($read->tags(name => 'ico_bits'), 1, "check bits");
  is(Imager::i_img_diff($read, $im), 0, "check image correct");
}

{ # 4 bit write fails
  my $im = Imager->new(xsize => 10, ysize => 10, type => 'paletted');
  my $red = NC(255, 0, 0);
  my $blue = NC(0, 0, 255);
  $im->addcolors(colors => [ ($red, $blue) x 8 ]);
  $im->box(filled => 1, color => $red, ymax => 5);
  $im->box(filled => 1, color => $blue, ymin => 6);
  ok(!$im->write(type => 'ico', io => limited_write_io(22)),
     "third write (bmi) should fail (4-bit)");
  is($im->errstr, "Write failure: limit reached", "check message");
  
  ok(!$im->write(type => 'ico', io => limited_write_io(66)),
     "fourth write (palette) should fail (4-bit)");
  is($im->errstr, "Write failure: limit reached", "check message");
  ok(!$im->write(type => 'ico', io => limited_write_io(130)),
     "fifth write (image) should fail (4-bit)");
  is($im->errstr, "Write failure: limit reached", "check message");
  my $data;
  ok($im->write(data => \$data, type => 'ico'), "write 4 bit successfully");
  my $read = Imager->new;
  ok($read->read(data => $data), "read it back");
  is($read->type, 'paletted', "check type");
  is($read->tags(name => 'ico_bits'), 4, "check bits");
  is(Imager::i_img_diff($read, $im), 0, "check image correct");
}

{ # 8 bit write fails
  my $im = Imager->new(xsize => 10, ysize => 10, type => 'paletted');
  my $red = NC(255, 0, 0);
  my $blue = NC(0, 0, 255);
  $im->addcolors(colors => [ ($red, $blue) x 9 ]);
  $im->box(filled => 1, color => $red, ymax => 5);
  $im->box(filled => 1, color => $blue, ymin => 6);
  ok(!$im->write(type => 'ico', io => limited_write_io(22)),
     "third write (bmi) should fail (8-bit)");
  is($im->errstr, "Write failure: limit reached", "check message");
  
  ok(!$im->write(type => 'ico', io => limited_write_io(62)),
     "fourth write (palette) should fail (8-bit)");
  is($im->errstr, "Write failure: limit reached", "check message");
  ok(!$im->write(type => 'ico', io => limited_write_io(62 + 1024)),
     "fifth write (image) should fail (8-bit)");
  is($im->errstr, "Write failure: limit reached", "check message");
  ok(!$im->write(type => 'ico', io => limited_write_io(62 + 1024 + 10)),
     "sixth write (zeroes) should fail (8-bit)");
  is($im->errstr, "Write failure: limit reached", "check message");
  my $data;
  ok($im->write(data => \$data, type => 'ico'), "write 8 bit successfully");
  my $read = Imager->new;
  ok($read->read(data => $data), "read it back");
  is($read->type, 'paletted', "check type");
  is($read->tags(name => 'ico_bits'), 8, "check bits");
  is(Imager::i_img_diff($read, $im), 0, "check image correct");
}

# write callback that fails
sub write_failure {
  print "# synthesized write failure\n";
  Imager::i_push_error(0, "synthetic error");
  return;
}

sub limited_write_io {
  my ($limit) = @_;

  my $io = Imager::io_new_cb(limited_write($limit), undef, undef, undef, 1);
  $io->set_buffered(0);

  return $io;
}

sub limited_write {
  my ($limit) = @_;

  return
     sub {
       my ($data) = @_;
       $limit -= length $data;
       if ($limit >= 0) {
         print "# write of ", length $data, " bytes successful ($limit left)\n";
         return 1;
       }
       else {
         print "# write of ", length $data, " bytes failed\n";
         Imager::i_push_error(0, "limit reached");
         return;
       }
     };
}
