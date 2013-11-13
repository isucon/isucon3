#!perl -w
######################### We start with some black magic to print on failure.

# this used to do the check for the load of Imager, but I want to be able 
# to count tests, which means I need to load Imager first
# since many of the early tests already do this, we don't really need to

use strict;
use Imager;
use IO::Seekable;

my $buggy_giflib_file = "buggy_giflib.txt";

-d "testout" or mkdir "testout";

Imager::init("log"=>"testout/t50basicoo.log");

# single image/file types
my @types = qw( jpeg png raw pnm gif tiff bmp tga );

# multiple image/file formats
my @mtypes = qw(tiff gif);

my %hsh=%Imager::formats;

my $test_num = 0;
my $count;
for my $type (@types) {
  $count += 31 if $hsh{$type};
}
for my $type (@mtypes) {
  $count += 7 if $hsh{$type};
}

print "1..$count\n";

print "# avaliable formats:\n";
for(keys %hsh) { print "# $_\n"; }

#print Dumper(\%hsh);

my $img = Imager->new();

my %files;
@files{@types} = ({ file => "JPEG/testimg/209_yonge.jpg"  },
		  { file => "testimg/test.png"  },
		  { file => "testimg/test.raw", xsize=>150, ysize=>150, type=>'raw', interleave => 0},
		  { file => "testimg/penguin-base.ppm"  },
		  { file => "GIF/testimg/expected.gif"  },
		  { file => "TIFF/testimg/comp8.tif" },
                  { file => "testimg/winrgb24.bmp" },
                  { file => "testimg/test.tga" }, );
my %writeopts =
  (
   gif=> { make_colors=>'webmap', translate=>'closest', gifquant=>'gen',
         gif_delay=>20 },
  );

for my $type (@types) {
  next unless $hsh{$type};
  print "# type $type\n";
  my %opts = %{$files{$type}};
  my @a = map { "$_=>${opts{$_}}" } keys %opts;
  print "#opening Format: $type, options: @a\n";
  ok($img->read( %opts ), "reading from file", $img);
  #or die "failed: ",$img->errstr,"\n";

  my %mopts = %opts;
  delete $mopts{file};

  # read from a file handle
  my $fh = IO::File->new($opts{file}, "r");
  if (ok($fh, "opening $opts{file}")) {
    binmode $fh;
    my $fhimg = Imager->new;
    if (ok($fhimg->read(fh=>$fh, %mopts), "read from fh")) {
      ok($fh->seek(0, SEEK_SET), "seek after read");
      if (ok($fhimg->read(fh=>$fh, %mopts, type=>$type), "read from fh")) {
	ok(Imager::i_img_diff($img->{IMG}, $fhimg->{IMG}) == 0,
	   "image comparison after fh read");
      }
      else {
	skip("no image to compare");
      }
      ok($fh->seek(0, SEEK_SET), "seek after read");
    }

    # read from a fd
    my $fdimg = Imager->new;
    if (ok($fdimg->read(fd=>fileno($fh), %mopts, type=>$type), "read from fd")) {
      ok(Imager::i_img_diff($img->{IMG}, $fdimg->{IMG}) == 0,
         "image comparistion after fd read");
    }
    else {
      skip("no image to compare");
    }
    ok($fh->seek(0, SEEK_SET), "seek after fd read");
    ok($fh->close, "close fh after reads");
  }
  else {
    skip("couldn't open the damn file: $!", 7);
  }

  # read from a memory buffer
  open DATA, "< $opts{file}"
    or die "Cannot open $opts{file}: $!";
  binmode DATA;
  my $data = do { local $/; <DATA> };
  close DATA;
  my $bimg = Imager->new;
  
  if (ok($bimg->read(data=>$data, %mopts, type=>$type), "read from buffer", 
	 $img)) {
    ok(Imager::i_img_diff($img->{IMG}, $bimg->{IMG}) == 0,
       "comparing buffer read image");
  }
  else {
    skip("nothing to compare");
  }
  
  # read from callbacks, both with minimum and maximum reads
  my $buf = $data;
  my $seekpos = 0;
  my $reader_min = 
    sub { 
      my ($size, $maxread) = @_;
      my $out = substr($buf, $seekpos, $size);
      $seekpos += length $out;
      $out;
    };
  my $reader_max = 
    sub { 
      my ($size, $maxread) = @_;
      my $out = substr($buf, $seekpos, $maxread);
      $seekpos += length $out;
      $out;
    };
  my $seeker =
    sub {
      my ($offset, $whence) = @_;
      #print "io_seeker($offset, $whence)\n";
      if ($whence == SEEK_SET) {
	$seekpos = $offset;
      }
      elsif ($whence == SEEK_CUR) {
	$seekpos += $offset;
      }
      else { # SEEK_END
	$seekpos = length($buf) + $offset;
      }
      #print "-> $seekpos\n";
      $seekpos;
    };
  my $cbimg = Imager->new;
  ok($cbimg->read(callback=>$reader_min, seekcb=>$seeker, type=>$type, %mopts),
     "read from callback min", $cbimg);
  ok(Imager::i_img_diff($cbimg->{IMG}, $img->{IMG}) == 0,
     "comparing mincb image");
  $seekpos = 0;
  ok($cbimg->read(callback=>$reader_max, seekcb=>$seeker, type=>$type, %mopts),
     "read from callback max", $cbimg);
  ok(Imager::i_img_diff($cbimg->{IMG}, $img->{IMG}) == 0,
     "comparing maxcb image");
}

for my $type (@types) {
  next unless $hsh{$type};

  print "# write tests for $type\n";
  # test writes
  next unless $hsh{$type};
  my $file = "testout/t50out.$type";
  my $wimg = Imager->new;
  # if this doesn't work, we're so screwed up anyway
  
  ok($wimg->read(file=>"testimg/penguin-base.ppm"),
     "cannot read base file", $wimg);

  # first to a file
  print "# writing $type to a file\n";
  my %extraopts;
  %extraopts = %{$writeopts{$type}} if $writeopts{$type};
  ok($wimg->write(file=>$file, %extraopts),
     "writing $type to a file $file", $wimg);

  print "# writing $type to a FH\n";
  # to a FH
  my $fh = IO::File->new($file, "w+")
    or die "Could not create $file: $!";
  binmode $fh;
  ok($wimg->write(fh=>$fh, %extraopts, type=>$type),
     "writing $type to a FH", $wimg);
  ok($fh->seek(0, SEEK_END) > 0,
     "seek after writing $type to a FH");
  ok(print($fh "SUFFIX\n"),
     "write to FH after writing $type");
  ok($fh->close, "closing FH after writing $type");

  if (ok(open(DATA, "< $file"), "opening data source")) {
    binmode DATA;
    my $data = do { local $/; <DATA> };
    close DATA;

    # writing to a buffer
    print "# writing $type to a buffer\n";
    my $buf = '';
    ok($wimg->write(data=>\$buf, %extraopts, type=>$type),
       "writing $type to a buffer", $wimg);
    $buf .= "SUFFIX\n";
    open DATA, "> testout/t50_buf.$type"
      or die "Cannot create $type buffer file: $!";
    binmode DATA;
    print DATA $buf;
    close DATA;
    ok($data eq $buf, "comparing file data to buffer");

    $buf = '';
    my $seekpos = 0;
    my $did_close;
    my $writer = 
      sub {
	my ($what) = @_;
	if ($seekpos > length $buf) {
	  $buf .= "\0" x ($seekpos - length $buf);
	}
	substr($buf, $seekpos, length $what) = $what;
	$seekpos += length $what;
	$did_close = 0; # the close must be last
	1;
      };
    my $reader_min = 
      sub { 
	my ($size, $maxread) = @_;
	my $out = substr($buf, $seekpos, $size);
	$seekpos += length $out;
	$out;
      };
    my $reader_max = 
      sub { 
	my ($size, $maxread) = @_;
	my $out = substr($buf, $seekpos, $maxread);
	$seekpos += length $out;
	$out;
      };
    use IO::Seekable;
    my $seeker =
      sub {
	my ($offset, $whence) = @_;
	#print "io_seeker($offset, $whence)\n";
	if ($whence == SEEK_SET) {
	  $seekpos = $offset;
	}
	elsif ($whence == SEEK_CUR) {
	  $seekpos += $offset;
	}
	else { # SEEK_END
	  $seekpos = length($buf) + $offset;
	}
	#print "-> $seekpos\n";
	$seekpos;
      };

    my $closer = sub { ++$did_close; };

    print "# writing $type via callbacks (mb=1)\n";
    ok($wimg->write(writecb=>$writer, seekcb=>$seeker, closecb=>$closer,
		    readcb=>$reader_min,
		    %extraopts, type=>$type, maxbuffer=>1),
       "writing $type to callback (mb=1)", $wimg);

    ok($did_close, "checking closecb called");
    $buf .= "SUFFIX\n";
    ok($data eq $buf, "comparing callback output to file data");
    print "# writing $type via callbacks (no mb)\n";
    $buf = '';
    $did_close = 0;
    $seekpos = 0;
    # we don't use the closecb here - used to make sure we don't get 
    # a warning/error on an attempt to call an undef close sub
    ok($wimg->write(writecb=>$writer, seekcb=>$seeker, readcb=>$reader_min,
		    %extraopts, type=>$type),
       "writing $type to callback (no mb)", $wimg);
    $buf .= "SUFFIX\n";
    ok($data eq $buf, "comparing callback output to file data");
  }
  else {
    skip("couldn't open data source", 7);
  }
}

my $img2 =  $img->crop(width=>50, height=>50);
$img2 -> write(file=> 'testout/t50.ppm', type=>'pnm');

undef($img);

# multi image/file tests
print "# multi-image write tests\n";
for my $type (@mtypes) {
  next unless $hsh{$type};
  print "# $type\n";

  my $file = "testout/t50out.$type";
  my $wimg = Imager->new;

  # if this doesn't work, we're so screwed up anyway
  ok($wimg->read(file=>"testout/t50out.$type"),
     "reading base file", $wimg);

  ok(my $wimg2 = $wimg->copy, "copying base image", $wimg);
  ok($wimg2->flip(dir=>'h'), "flipping base image", $wimg2);

  my @out = ($wimg, $wimg2);
  my %extraopts;
  %extraopts = %{$writeopts{$type}} if $writeopts{$type};
  ok(Imager->write_multi({ file=>"testout/t50_multi.$type", %extraopts },
                         @out),
     "writing multiple to a file", "Imager");

  # make sure we get the same back
  my @images = Imager->read_multi(file=>"testout/t50_multi.$type");
  if (ok(@images == @out, "checking read image count")) {
    for my $i (0 .. $#out) {
      my $diff = Imager::i_img_diff($out[$i]{IMG}, $images[$i]{IMG});
      print "# diff $diff\n";
      ok($diff == 0, "comparing image $i");
    }
  }
  else {
    skip("wrong number of images read", 2);
  }
}


Imager::malloc_state();

#print "ok 2\n";

sub ok {
  my ($ok, $msg, $img, $why, $skipcount) = @_;

  ++$test_num;
  if ($ok) {
    print "ok $test_num # $msg\n";
    Imager::i_log_entry("ok $test_num # $msg\n", 0);
  }
  else {
    my $err;
    $err = $img->errstr if $img;
    # VMS (if we ever support it) wants the whole line in one print
    my $line = "not ok $test_num # line ".(caller)[2].": $msg";
    $line .= ": $err" if $err;
    print $line, "\n";
    Imager::i_log_entry($line."\n", 0);
  }
  skip($why, $skipcount) if defined $why;
  $ok;
}

sub skip {
  my ($why, $skipcount) = @_;

  $skipcount ||= 1;
  for (1.. $skipcount) {
    ++$test_num;
    print "ok $test_num # skipped $why\n";
  }
}
