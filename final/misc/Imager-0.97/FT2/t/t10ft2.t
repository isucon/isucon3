#!perl -w
use strict;
use Test::More tests => 204;
use Cwd qw(getcwd abs_path);

use Imager qw(:all);

use Imager::Test qw(diff_text_with_nul is_color3 is_color4 isnt_image is_image);

-d "testout" or mkdir "testout";

my @test_output;

push @test_output, "t38ft2font.log";

Imager->open_log(log => "testout/t38ft2font.log");

my $deffont = "fontfiles/dodge.ttf";

my @base_color = (64, 255, 64);

SKIP:
{
  ok($Imager::formats{ft2}, "ft2 should be in %formats");

  my $fontname=$ENV{'TTFONTTEST'} || $deffont;

  -f $fontname or skip("cannot find fontfile $fontname", 189);

  print STDERR "FreeType2 runtime ", Imager::Font::FT2::i_ft2_version(1), 
    " compile-time ", Imager::Font::FT2::i_ft2_version(0), "\n";

  my $bgcolor=i_color_new(255,0,0,0);
  my $overlay=Imager::ImgRaw::new(200,70,3);
  
  my $ttraw=Imager::Font::FT2::i_ft2_new($fontname, 0);
  
  $ttraw or print Imager::_error_as_msg(),"\n";
  ok($ttraw, "loaded raw font");

  my @bbox=Imager::Font::FT2::i_ft2_bbox($ttraw, 50.0, 0, 'XMCLH', 0);
  print "#bbox @bbox\n";
  
  is(@bbox, 8, "i_ft2_bbox() returns 8 values");

  ok(Imager::Font::FT2::i_ft2_cp($ttraw,$overlay,5,50,1,50.0,50, 'XMCLH',1,1, 0, 0), "drawn to channel");
  i_line($overlay,0,50,100,50,$bgcolor,1);

  push @test_output, "t38ft2font.ppm";
  open(FH,">testout/t38ft2font.ppm") || die "cannot open testout/t38ft2font.ppm\n";
  binmode(FH);
  my $IO = Imager::io_new_fd(fileno(FH));
  ok(i_writeppm_wiol($overlay, $IO), "saved image");
  close(FH);

  $bgcolor=i_color_set($bgcolor,200,200,200,0);
  my $backgr=Imager::ImgRaw::new(500,300,3);
  
  #     i_tt_set_aa(2);
  ok(Imager::Font::FT2::i_ft2_text($ttraw,$backgr,100,150,NC(255, 64, 64),200.0,50, 'MAW',1,1,0, 0), "drew MAW");
  Imager::Font::FT2::i_ft2_settransform($ttraw, [0.9659, 0.2588, 0, -0.2588, 0.9659, 0 ]);
  ok(Imager::Font::FT2::i_ft2_text($ttraw,$backgr,100,150,NC(0, 128, 0),200.0,50, 'MAW',0,1, 0, 0), "drew rotated MAW");
  i_line($backgr, 0,150, 499, 150, NC(0, 0, 255),1);

  push @test_output, "t38ft2font2.ppm";
  open(FH,">testout/t38ft2font2.ppm") || die "cannot open testout/t38ft2font.ppm\n";
  binmode(FH);
  $IO = Imager::io_new_fd(fileno(FH));
  ok(i_writeppm_wiol($backgr,$IO), "saved second image");
  close(FH);

  my $oof = Imager::Font->new(file=>$fontname, type=>'ft2', 'index'=>0);

  ok($oof, "loaded OO font");

  my $im = Imager->new(xsize=>400, ysize=>250);
  
  ok($im->string(font=>$oof,
                 text=>"Via OO",
                 'x'=>20,
                 'y'=>20,
                 size=>60,
                 color=>NC(255, 128, 255),
                 aa => 1,
                 align=>0), "drawn through OO interface");
  ok($oof->transform(matrix=>[1, 0.1, 0, 0, 1, 0]),
     "set matrix via OO interface");
  ok($im->string(font=>$oof,
                 text=>"Shear",
                 'x'=>20,
                 'y'=>40,
                 size=>60,
                 sizew=>50,
                 channel=>1,
                 aa=>1,
                 align=>1), "drawn transformed through OO");
  use Imager::Matrix2d ':handy';
  ok($oof->transform(matrix=>m2d_rotate(degrees=>-30)),
     "set transform from m2d module");
  ok($im->string(font=>$oof,
                 text=>"SPIN",
                 'x'=>20,
                 'y'=>50,
                 size=>50,
                 sizew=>40,
                 color=>NC(255,255,0),
                 aa => 1,
                 align=>0, vlayout=>0), "drawn first rotated");

  ok($im->string(font=>$oof,
                 text=>"SPIN",
                 'x'=>20,
                 'y'=>50,
                 size=>50,
                 sizew=>40,
            channel=>2,
                 aa => 1,
                 align=>0, vlayout=>0), "drawn second rotated");
  
  $oof->transform(matrix=>m2d_identity());
  $oof->hinting(hinting=>1);

  # UTF8 testing
  # the test font (dodge.ttf) only supports one character above 0xFF that
  # I can see, 0x2010 HYPHEN (which renders the same as 0x002D HYPHEN MINUS)
  # an attempt at utf8 support
  # first attempt to use native perl UTF8
 SKIP:
  {
    skip("no native UTF8 support in this version of perl", 1) 
      unless $] >= 5.006;
    my $text;
    # we need to do this in eval to prevent compile time errors in older
    # versions
    eval q{$text = "A\x{2010}A"}; # A, HYPHEN, A in our test font
    #$text = "A".chr(0x2010)."A"; # this one works too
    unless (ok($im->string(font=>$oof,
                           text=>$text,
                           'x'=>20,
                           'y'=>200,
                           size=>50,
                           color=>NC(0,255,0),
                           aa=>1), "drawn UTF natively")) {
      print "# ",$im->errstr,"\n";
    }

  }

  # an attempt using emulation of UTF8
  my $text = pack("C*", 0x41, 0xE2, 0x80, 0x90, 0x41);
  #my $text = "A\xE2\x80\x90\x41\x{2010}";
  #substr($text, -1, 0) = '';
  unless (ok($im->string(font=>$oof,
                         text=>$text,
                         'x'=>20,
                         'y'=>230,
                         size=>50,
                         color=>NC(255,128,0),
                         aa=>1, 
                         utf8=>1), "drawn UTF emulated")) {
    print "# ",$im->errstr,"\n";
  }

  # just a bit of fun
  # well it was - it demostrates what happens when you combine
  # transformations and font hinting
  for my $steps (0..39) {
    $oof->transform(matrix=>m2d_rotate(degrees=>-$steps+5));
    # demonstrates why we disable hinting on a doing a transform
    # if the following line is enabled then the 0 degrees output sticks 
    # out a bit
    # $oof->hinting(hinting=>1);
    $im->string(font=>$oof,
                text=>"SPIN",
                'x'=>160,
                'y'=>70,
                size=>65,
                color=>NC(255, $steps * 5, 200-$steps * 5),
                aa => 1,
                align=>0, );
  }

  push @test_output, "t38_oo.ppm";
  $im->write(file=>'testout/t38_oo.ppm')
    or print "# could not save OO output: ",$im->errstr,"\n";
  
  my (@got) = $oof->has_chars(string=>"\x01H");
  ok(@got == 2, "has_chars returned 2 items");
  ok(!$got[0], "have no chr(1)");
  ok($got[1], "have 'H'");
  is($oof->has_chars(string=>"H\x01"), "\x01\x00",
     "scalar has_chars()");

  print "# OO bounding boxes\n";
  @bbox = $oof->bounding_box(string=>"hello", size=>30);
  my $bbox = $oof->bounding_box(string=>"hello", size=>30);

  is(@bbox, 8, "list bbox returned 8 items");
  ok($bbox->isa('Imager::Font::BBox'), "scalar bbox returned right class");
  ok($bbox->start_offset == $bbox[0], "start_offset");
  ok($bbox->end_offset == $bbox[2], "end_offset");
  ok($bbox->global_ascent == $bbox[3], "global_ascent");
  ok($bbox->global_descent == $bbox[1], "global_descent");
  ok($bbox->ascent == $bbox[5], "ascent");
  ok($bbox->descent == $bbox[4], "descent");
  ok($bbox->advance_width == $bbox[6], "advance_width");

  print "# aligned text output\n";
  my $alimg = Imager->new(xsize=>300, ysize=>300);
  $alimg->box(color=>'40FF40', filled=>1);

  $oof->transform(matrix=>m2d_identity());
  $oof->hinting(hinting=>1);
  
  align_test('left', 'top', 10, 10, $oof, $alimg);
  align_test('start', 'top', 10, 40, $oof, $alimg);
  align_test('center', 'top', 150, 70, $oof, $alimg);
  align_test('end', 'top', 290, 100, $oof, $alimg);
  align_test('right', 'top', 290, 130, $oof, $alimg);

  align_test('center', 'top', 150, 160, $oof, $alimg);
  align_test('center', 'center', 150, 190, $oof, $alimg);
  align_test('center', 'bottom', 150, 220, $oof, $alimg);
  align_test('center', 'baseline', 150, 250, $oof, $alimg);
  
  push @test_output, "t38aligned.ppm";
  ok($alimg->write(file=>'testout/t38aligned.ppm'), 
     "saving aligned output image");
  
  my $exfont = Imager::Font->new(file=>'fontfiles/ExistenceTest.ttf',
                                 type=>'ft2');
  SKIP:
  {
    ok($exfont, "loaded existence font")
      or diag(Imager->errstr);
    $exfont
      or skip("couldn't load test font", 11);

    # the test font is known to have a shorter advance width for that char
    my @bbox = $exfont->bounding_box(string=>"/", size=>100);
    is(@bbox, 8, "should be 8 entries");
    isnt($bbox[6], $bbox[2], "different advance width");
    my $bbox = $exfont->bounding_box(string=>"/", size=>100);
    ok($bbox->pos_width != $bbox->advance_width, "OO check");

    cmp_ok($bbox->right_bearing, '<', 0, "check right bearing");

    cmp_ok($bbox->display_width, '>', $bbox->advance_width,
           "check display width (roughly)");

    # check with a char that fits inside the box
    $bbox = $exfont->bounding_box(string=>"!", size=>100);
    print "# pos width ", $bbox->pos_width, "\n";
    is($bbox->pos_width, $bbox->advance_width, 
       "check backwards compatibility");
    cmp_ok($bbox->left_bearing, '>', 0, "left bearing positive");
    cmp_ok($bbox->right_bearing, '>', 0, "right bearing positive");
    cmp_ok($bbox->display_width, '<', $bbox->advance_width,
           "display smaller than advance");

    # name tests
    # make sure the number of tests on each branch match
    if (Imager::Font::FT2::i_ft2_can_face_name()) {
      my $facename = Imager::Font::FT2::i_ft2_face_name($exfont->{id});
      print "# face name '$facename'\n";
      is($facename, 'ExistenceTest', "test face name");
      $facename = $exfont->face_name;
      is($facename, 'ExistenceTest', "test face name OO");
    }
    else {
      # make sure we get the error we expect
      my $facename = Imager::Font::FT2::i_ft2_face_name($exfont->{id});
      my ($msg) = Imager::_error_as_msg();
      ok(!defined($facename), "test face name not supported");
      print "# $msg\n";
      ok(scalar($msg =~ /or later required/), "test face name not supported");
    }
  }

  SKIP:
  {
    Imager::Font::FT2->can_glyph_names
        or skip("FT2 compiled without glyph names support", 9);
        
    # FT2 considers POST tables in TTF fonts unreliable, so use
    # a type 1 font, see below for TTF test 
    my $exfont = Imager::Font->new(file=>'fontfiles/ExistenceTest.pfb',
                               type=>'ft2');
  SKIP:
    {
      ok($exfont, "load Type 1 via FT2")
        or skip("couldn't load type 1 with FT2", 8);
      my @glyph_names = 
        Imager::Font::FT2::i_ft2_glyph_name($exfont->{id}, "!J/");
      #use Data::Dumper;
      #print Dumper \@glyph_names;
      is($glyph_names[0], 'exclam', "check exclam name");
      ok(!defined($glyph_names[1]), "check for no J name");
      is($glyph_names[2], 'slash', "check slash name");

      # oo interfaces
      @glyph_names = $exfont->glyph_names(string=>"!J/");
      is($glyph_names[0], 'exclam', "check exclam name OO");
      ok(!defined($glyph_names[1]), "check for no J name OO");
      is($glyph_names[2], 'slash', "check slash name OO");

      # make sure a missing string parameter is handled correctly
      eval {
        $exfont->glyph_names();
      };
      is($@, "", "correct error handling");
      cmp_ok(Imager->errstr, '=~', qr/no string parameter/, "error message");
    }
  
    # freetype 2 considers truetype glyph name tables unreliable
    # due to some specific fonts, supplying reliable_only=>0 bypasses
    # that check and lets us get the glyph names even for truetype fonts
    # so we can test this stuff <sigh>
    # we can't use ExistenceTest.ttf since that's generated with 
    # AppleStandardEncoding since the same .sfd needs to generate
    # a .pfb file, NameTest.ttf uses a Unicode encoding
    
    # we were using an unsigned char to store a unicode character
    # https://rt.cpan.org/Ticket/Display.html?id=7949
    $exfont = Imager::Font->new(file=>'fontfiles/NameTest.ttf',
                                type=>'ft2');
  SKIP:
    {
      ok($exfont, "load TTF via FT2")
        or skip("could not load TTF with FT2", 1);
      my $text = pack("C*", 0xE2, 0x80, 0x90); # "\x{2010}" as utf-8
      my @names = $exfont->glyph_names(string=>$text,
                                       utf8=>1, reliable_only=>0);
      is($names[0], "hyphentwo", "check utf8 glyph name");
    }
  }

  # check that error codes are translated correctly
  my $errfont = Imager::Font->new(file=>"t/t10ft2.t", type=>"ft2");
  is($errfont, undef, "new font vs non font");
  cmp_ok(Imager->errstr, '=~', qr/unknown file format/, "check error message");

  # Multiple Master tests
  # we check a non-MM font errors correctly
  print "# check that the methods act correctly for a non-MM font\n";
  ok(!$exfont->is_mm, "exfont not MM");
  ok((() = $exfont->mm_axes) == 0, "exfont has no MM axes");
  cmp_ok(Imager->errstr, '=~', qr/no multiple masters/, 
         "and returns correct error when we ask");
  ok(!$exfont->set_mm_coords(coords=>[0, 0]), "fail setting axis on exfont");
  cmp_ok(Imager->errstr, '=~', qr/no multiple masters/, 
         "and returns correct error when we ask");

  # try a MM font now - test font only has A defined
  print "# Try a multiple master font\n";
  my $mmfont = Imager::Font->new(file=>"fontfiles/MMOne.pfb", type=>"ft2", 
                                 color=>"white", aa=>1, size=>60);
  ok($mmfont, "loaded MM font")
    or print "# ", Imager->errstr, "\n";
  ok($mmfont->is_mm, "font is multiple master");
  my @axes = $mmfont->mm_axes;
  is(@axes, 2, "check we got both axes");
  is($axes[0][0], "Weight", "name of first axis");
  is($axes[0][1],  50, "min for first axis");
  is($axes[0][2], 999, "max for first axis");
  is($axes[1][0], "Slant", "name of second axis");
  is($axes[1][1],   0, "min for second axis");
  is($axes[1][2], 999, "max for second axis");
  my $mmim = Imager->new(xsize=>200, ysize=>200);
  $mmim->string(font=>$mmfont, x=>0, 'y'=>50, text=>"A");
  ok($mmfont->set_mm_coords(coords=>[ 700, 0 ]), "set to bold, unsloped");
  $mmim->string(font=>$mmfont, x=>0, 'y'=>100, text=>"A", color=>'blue');
  my @weights = qw(50 260 525 760 999);
  my @slants = qw(0 333 666 999);
  for my $windex (0 .. $#weights) {
    my $weight = $weights[$windex];
    for my $sindex (0 .. $#slants) {
      my $slant = $slants[$sindex];
      $mmfont->set_mm_coords(coords=>[ $weight, $slant ]);
      $mmim->string(font=>$mmfont, x=>30+32*$windex, 'y'=>50+45*$sindex,
                    text=>"A");
    }
  }

  push @test_output, "t38mm.ppm";
  ok($mmim->write(file=>"testout/t38mm.ppm"), "save MM output");

 SKIP:
  { print "# alignment tests\n";
    my $font = Imager::Font->new(file=>'fontfiles/ImUgly.ttf', type=>'ft2');
    ok($font, "loaded deffont OO")
      or skip("could not load font:".Imager->errstr, 4);
    my $im = Imager->new(xsize=>140, ysize=>150);
    my %common = 
      (
       font=>$font, 
       size=>40, 
       aa=>1,
      );
    $im->line(x1=>0, y1=>40, x2=>139, y2=>40, color=>'blue');
    $im->line(x1=>0, y1=>90, x2=>139, y2=>90, color=>'blue');
    $im->line(x1=>0, y1=>110, x2=>139, y2=>110, color=>'blue');
    for my $args ([ x=>5,   text=>"A", color=>"white" ],
                  [ x=>40,  text=>"y", color=>"white" ],
                  [ x=>75,  text=>"A", channel=>1 ],
                  [ x=>110, text=>"y", channel=>1 ]) {
      ok($im->string(%common, @$args, 'y'=>40), "A no alignment");
      ok($im->string(%common, @$args, 'y'=>90, align=>1), "A align=1");
      ok($im->string(%common, @$args, 'y'=>110, align=>0), "A align=0");
    }
    push @test_output, "t38align.ppm";
    ok($im->write(file=>'testout/t38align.ppm'), "save align image");
  }


  { # outputting a space in non-AA could either crash 
    # or fail (ft 2.2+)
    my $font = Imager::Font->new(file=>'fontfiles/ImUgly.ttf', type=>'ft2');
    my $im = Imager->new(xsize => 100, ysize => 100);
    ok($im->string(x => 10, y => 10, string => "test space", aa => 0,
		   color => '#FFF', size => 8, font => $font),
       "draw space non-antialiased (color)");
    ok($im->string(x => 10, y => 50, string => "test space", aa => 0,
		   channel => 0, size => 8, font => $font),
       "draw space non-antialiased (channel)");
  }

  { # cannot output "0"
    # https://rt.cpan.org/Ticket/Display.html?id=21770
    my $font = Imager::Font->new(file=>'fontfiles/ImUgly.ttf', type=>'ft2');
    ok($font, "loaded imugly");
    my $imbase = Imager->new(xsize => 100, ysize => 100);
    my $im = $imbase->copy;
    ok($im->string(x => 10, y => 50, string => "0", aa => 0,
		   color => '#FFF', size => 20, font => $font),
       "draw '0'");
    ok(Imager::i_img_diff($im->{IMG}, $imbase->{IMG}),
       "make sure we actually drew it");
    $im = $imbase->copy;
    ok($im->string(x => 10, y => 50, string => 0.0, aa => 0,
		   color => '#FFF', size => 20, font => $font),
       "draw 0.0");
    ok(Imager::i_img_diff($im->{IMG}, $imbase->{IMG}),
       "make sure we actually drew it");
  }
  { # string output cut off at NUL ('\0')
    # https://rt.cpan.org/Ticket/Display.html?id=21770 cont'd
    my $font = Imager::Font->new(file=>'fontfiles/ImUgly.ttf', type=>'ft2');
    ok($font, "loaded imugly");

    diff_text_with_nul("a\\0b vs a", "a\0b", "a", 
		       font => $font, color => '#FFFFFF');
    diff_text_with_nul("a\\0b vs a", "a\0b", "a", 
		       font => $font, channel => 1);

    # UTF8 encoded \x{2010}
    my $dash = pack("C*", 0xE2, 0x80, 0x90);
    diff_text_with_nul("utf8 dash\0dash vs dash", "$dash\0$dash", $dash,
		       font => $font, color => '#FFFFFF', utf8 => 1);
    diff_text_with_nul("utf8 dash\0dash vs dash", "$dash\0$dash", $dash,
		       font => $font, channel => 1, utf8 => 1);
  }

  { # RT 11972
    # when rendering to a transparent image the coverage should be
    # expressed in terms of the alpha channel rather than the color
    my $font = Imager::Font->new(file=>'fontfiles/ImUgly.ttf', type=>'ft2');
    my $im = Imager->new(xsize => 40, ysize => 20, channels => 4);
    ok($im->string(string => "AB", size => 20, aa => 1, color => '#F00',
		   x => 0, y => 15, font => $font),
       "draw to transparent image");
    my $im_noalpha = $im->convert(preset => 'noalpha');
    my $im_pal = $im->to_paletted(make_colors => 'mediancut');
    my @colors = $im_pal->getcolors;
    is(@colors, 2, "should be only 2 colors");
    @colors = sort { ($a->rgba)[0] <=> ($b->rgba)[0] } @colors;
    is_color3($colors[0], 0, 0, 0, "check we got black");
    is_color3($colors[1], 255, 0, 0, "and red");
  }

  { # RT 27546
    my $im = Imager->new(xsize => 100, ysize => 100, channels => 4);
    $im->box(filled => 1, color => '#ff0000FF');
    my $font = Imager::Font->new(file=>'fontfiles/ImUgly.ttf', type=>'ft2');
    ok($im->string(x => 0, 'y' => 40, text => 'test', 
		   size => 11, sizew => 11, font => $font, aa => 1),
       'draw on translucent image')
  }

  { # RT 60199
    # not ft2 specific, but Imager
    my $im = Imager->new(xsize => 100, ysize => 100);
    my $font = Imager::Font->new(file=>'fontfiles/ImUgly.ttf', type=>'ft2');
    my $imcopy = $im->copy;
    ok($im, "make test image");
    ok($font, "make test font");
    ok($im->align_string(valign => "center", halign => "center",
			 x => 50, y => 50, string => "0", color => "#FFF",
			 font => $font),
       "draw 0 aligned");
    ok(Imager::i_img_diff($im->{IMG}, $imcopy->{IMG}),
       "make sure we drew the '0'");
  }

 SKIP:
  { # RT 60509
    # checks that a c:foo or c:\foo path is handled correctly on win32
    my $type = "ft2";
    $^O eq "MSWin32" || $^O eq "cygwin"
      or skip("only for win32", 2);
    my $dir = getcwd
      or skip("Cannot get cwd", 2);
    if ($^O eq "cygwin") {
      $dir = Cygwin::posix_to_win_path($dir);
    }
    my $abs_path = abs_path($deffont);
    my $font = Imager::Font->new(file => $abs_path, type => $type);
    ok($font, "found font by absolute path")
      or print "# path $abs_path\n";
    undef $font;

    $^O eq "cygwin"
      and skip("cygwin doesn't support drive relative DOSsish paths", 1);
    my ($drive) = $dir =~ /^([a-z]:)/i
      or skip("cwd has no drive letter", 2);
    my $drive_path = $drive . $deffont;
    $font = Imager::Font->new(file => $drive_path, type => $type);
    ok($font, "found font by drive relative path")
      or print "# path $drive_path\n";
  }
  { # RT 71469
    my $font1 = Imager::Font->new(file => $deffont, type => "ft2", index => 0);
    my $font2 = Imager::Font::FT2->new(file => $deffont, index => 0);

    for my $font ($font1, $font2) {
      print "# ", join(",", $font->{color}->rgba), "\n";

      my $im = Imager->new(xsize => 20, ysize => 20, channels => 4);

      ok($im->string(text => "T", font => $font, y => 15),
	 "draw with default color")
	or print "# ", $im->errstr, "\n";
      my $work = Imager->new(xsize => 20, ysize => 20);
      my $cmp = $work->copy;
      $work->rubthrough(src => $im);
      isnt_image($work, $cmp, "make sure something was drawn");
    }
  }

  { # RT 73359
    # non-AA font drawing isn't normal mode

    Imager->log("testing no-aa normal output\n");

    my $font = Imager::Font->new(file => "fontfiles/ImUgly.ttf", type => "ft2");

    ok($font, "make a work font");

    my %common =
      (
       x => 10,
       font => $font,
       size => 25,
       aa => 0,
       align => 0,
      );

    # build our comparison image
    my $cmp = Imager->new(xsize => 120, ysize => 100);
    my $layer = Imager->new(xsize => 120, ysize => 100, channels => 4);
    ok($layer->string(%common, y => 10, text => "full", color => "#8080FF"),
       "draw non-aa text at full coverage to layer image");
    ok($layer->string(%common, y => 40, text => "half", color => "#FF808080"),
       "draw non-aa text at half coverage to layer image");
    ok($layer->string(%common, y => 70, text => "quarter", color => "#80FF8040"),
       "draw non-aa text at zero coverage to layer image");
    ok($cmp->rubthrough(src => $layer), "rub layer onto comparison image");

    my $im = Imager->new(xsize => 120, ysize => 100);
    ok($im->string(%common, y => 10, text => "full", color => "#8080FF"),
       "draw non-aa text at full coverage");
    ok($im->string(%common, y => 40, text => "half", color => "#FF808080"),
       "draw non-aa text at half coverage");
    ok($im->string(%common, y => 70, text => "quarter", color => "#80FF8040"),
       "draw non-aa text at zero coverage");
    is_image($im, $cmp, "check the result");

    push @test_output, "noaanorm.ppm", "noaacmp.ppm";
    ok($cmp->write(file => "testout/noaacmp.ppm"), "save cmp image")
      or diag "Saving cmp image: ", $cmp->errstr;
    ok($im->write(file => "testout/noaanorm.ppm"), "save test image")
      or diag "Saving result image: ", $im->errstr;
  }
}

Imager->close_log();

END {
  unless ($ENV{IMAGER_KEEP_FILES}) {
    unlink map "testout/$_", @test_output;
  }
}

sub align_test {
  my ($h, $v, $x, $y, $f, $img) = @_;

  my @pos = $f->align(halign=>$h, valign=>$v, 'x'=>$x, 'y'=>$y,
                      image=>$img, size=>15, color=>'FFFFFF',
                      string=>"x$h ${v}y", channel=>1, aa=>1);
  @pos = $img->align_string(halign=>$h, valign=>$v, 'x'=>$x, 'y'=>$y,
                      font=>$f, size=>15, color=>'FF99FF',
                      string=>"x$h ${v}y", aa=>1);
  if (ok(@pos == 4, "$h $v aligned output")) {
    # checking corners
    my $cx = int(($pos[0] + $pos[2]) / 2);
    my $cy = int(($pos[1] + $pos[3]) / 2);
    
    print "# @pos cx $cx cy $cy\n";
    okmatchcolor($img, $cx, $pos[1]-1, @base_color, "outer top edge");
    okmatchcolor($img, $cx, $pos[3], @base_color, "outer bottom edge");
    okmatchcolor($img, $pos[0]-1, $cy, @base_color, "outer left edge");
    okmatchcolor($img, $pos[2], $cy, @base_color, "outer right edge");
    
    okmismatchcolor($img, $cx, $pos[1], @base_color, "inner top edge");
    okmismatchcolor($img, $cx, $pos[3]-1, @base_color, "inner bottom edge");
    okmismatchcolor($img, $pos[0], $cy, @base_color, "inner left edge");
#    okmismatchcolor($img, $pos[2]-1, $cy, @base_color, "inner right edge");
# XXX: This gets triggered by a freetype2 bug I think 
#    $ rpm -qa | grep freetype
#    freetype-2.1.3-6
#
# (addi: 4/1/2004).

    cross($img, $x, $y, 'FF0000');
    cross($img, $cx, $pos[1]-1, '0000FF');
    cross($img, $cx, $pos[3], '0000FF');
    cross($img, $pos[0]-1, $cy, '0000FF');
    cross($img, $pos[2], $cy, '0000FF');
  }
  else {
    SKIP: { skip("couldn't draw text", 7) };
  }
}

sub okmatchcolor {
  my ($img, $x, $y, $r, $g, $b, $about) = @_;

  my $c = $img->getpixel('x'=>$x, 'y'=>$y);
  my ($fr, $fg, $fb) = $c->rgba;
  ok($fr == $r && $fg == $g && $fb == $b,
      "want ($r,$g,$b) found ($fr,$fg,$fb)\@($x,$y) $about");
}

sub okmismatchcolor {
  my ($img, $x, $y, $r, $g, $b, $about) = @_;

  my $c = $img->getpixel('x'=>$x, 'y'=>$y);
  my ($fr, $fg, $fb) = $c->rgba;
  ok($fr != $r || $fg != $g || $fb != $b,
      "don't want ($r,$g,$b) found ($fr,$fg,$fb)\@($x,$y) $about");
}

sub cross {
  my ($img, $x, $y, $color) = @_;

  $img->setpixel('x'=>[$x, $x, $x, $x, $x, $x-2, $x-1, $x+1, $x+2], 
                 'y'=>[$y-2, $y-1, $y, $y+1, $y+2, $y, $y, $y, $y], 
                 color => $color);
  
}


