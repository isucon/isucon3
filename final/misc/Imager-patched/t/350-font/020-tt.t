#!perl -w
use strict;
use Test::More tests => 97;

$|=1;

BEGIN { use_ok(Imager => ':all') }
use Imager::Test qw(diff_text_with_nul is_color3 is_image);

-d "testout" or mkdir "testout";

init_log("testout/t35ttfont.log",2);

SKIP:
{
  skip("freetype 1.x unavailable or disabled", 96) 
    unless $Imager::formats{"tt"};
  print "# has tt\n";
  
  my $deffont = './fontfiles/dodge.ttf';
  my $fontname=$ENV{'TTFONTTEST'} || $deffont;

  if (!ok(-f $fontname, "check test font file exists")) {
    print "# cannot find fontfile for truetype test $fontname\n";
    skip('Cannot load test font', 89);
  }

  #i_init_fonts();
  #     i_tt_set_aa(1);
  
  my $bgcolor = i_color_new(255,0,0,0);
  my $overlay = Imager::ImgRaw::new(320,140,3);
  i_box_filled($overlay, 0, 0, 319, 139, i_color_new(128, 128, 128));
  
  my $ttraw = Imager::i_tt_new($fontname);
  ok($ttraw, "create font");

  my @bbox = i_tt_bbox($ttraw,50.0,'XMCLH',0);
  is(@bbox, 8, "bounding box");
  print "#bbox: ($bbox[0], $bbox[1]) - ($bbox[2], $bbox[3])\n";

  ok(i_tt_cp($ttraw,$overlay,5,50,1,50.0,'XM CLH',6,1,0), "cp output");
  ok(i_tt_cp($ttraw,$overlay,5,120,1,50.0,'XM CLH',6,0,0), "cp output (non AA)");
  i_line($overlay,0,50,100,50,$bgcolor,1);

  open(FH,">testout/t35ttfont.ppm") || die "cannot open testout/t35ttfont.ppm\n";
  binmode(FH);
  my $IO = Imager::io_new_fd( fileno(FH) );
  ok(i_writeppm_wiol($overlay, $IO), "save t35ttfont.ppm");
  close(FH);

  $bgcolor=i_color_set($bgcolor,200,200,200,0);
  my $backgr=Imager::ImgRaw::new(500,300,3);
  
  #     i_tt_set_aa(2);
  
  ok(i_tt_text($ttraw,$backgr,100,120,$bgcolor,50.0,'te st',5,1,0),
      "normal output");
  ok(i_tt_text($ttraw,$backgr,100,200,$bgcolor,50.0,'te st',5,0,0),
      "normal output (non AA)");

  my $ugly = Imager::i_tt_new("./fontfiles/ImUgly.ttf");
  ok($ugly, "create ugly font");
  # older versions were dropping the bottom of g and the right of a
  ok(i_tt_text($ugly, $backgr,100, 80, $bgcolor, 14, 'g%g', 3, 1, 0), 
     "draw g%g");
  ok(i_tt_text($ugly, $backgr,150, 80, $bgcolor, 14, 'delta', 6, 1, 0),
      "draw delta");
  i_line($backgr,0,20,499,20,i_color_new(0,127,0,0),1);
  ok(i_tt_text($ttraw, $backgr, 20, 20, $bgcolor, 14, 'abcdefghijklmnopqrstuvwxyz{|}', 29, 1, 0), "alphabet");
  ok(i_tt_text($ttraw, $backgr, 20, 50, $bgcolor, 14, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 26, 1, 0), "ALPHABET");
  
  # UTF8 tests
  # for perl < 5.6 we can hand-encode text
  # the following is "A\x{2010}A"
  # 
  my $text = pack("C*", 0x41, 0xE2, 0x80, 0x90, 0x41);
  my $alttext = "A-A";
  
  my @utf8box = i_tt_bbox($ttraw, 50.0, $text, 1);
  is(@utf8box, 8, "utf8 bbox element count");
  my @base = i_tt_bbox($ttraw, 50.0, $alttext, 0);
  is(@base, 8, "alt bbox element count");
  my $maxdiff = $fontname eq $deffont ? 0 : $base[2] / 3;
  print "# (@utf8box vs @base)\n";
  ok(abs($utf8box[2] - $base[2]) <= $maxdiff, 
     "compare box sizes $utf8box[2] vs $base[2] (maxerror $maxdiff)");
  
  # hand-encoded UTF8 drawing
  ok(i_tt_text($ttraw, $backgr, 200, 80, $bgcolor, 14, $text, length($text), 1, 1), "draw hand-encoded UTF8");

  ok(i_tt_cp($ttraw, $backgr, 250, 80, 1, 14, $text, length($text), 1, 1), 
      "cp hand-encoded UTF8");

  # ok, try native perl UTF8 if available
 SKIP:
  {
    skip("perl too old to test native UTF8 support", 5) unless $] >= 5.006;

    my $text;
    # we need to do this in eval to prevent compile time errors in older
    # versions
    eval q{$text = "A\x{2010}A"}; # A, HYPHEN, A in our test font
    #$text = "A".chr(0x2010)."A"; # this one works too
    ok(i_tt_text($ttraw, $backgr, 300, 80, $bgcolor, 14, $text, 0, 1, 0),
       "draw UTF8");
    ok(i_tt_cp($ttraw, $backgr, 350, 80, 0, 14, $text, 0, 1, 0),
       "cp UTF8");
    @utf8box = i_tt_bbox($ttraw, 50.0, $text, 0);
    is(@utf8box, 8, "native utf8 bbox element count");
    ok(abs($utf8box[2] - $base[2]) <= $maxdiff, 
       "compare box sizes native $utf8box[2] vs $base[2] (maxerror $maxdiff)");
    eval q{$text = "A\x{0905}\x{0906}\x{0103}A"}; # Devanagari
    ok(i_tt_text($ugly, $backgr, 100, 160, $bgcolor, 36, $text, 0, 1, 0),
       "more complex output");
  }

  open(FH,">testout/t35ttfont2.ppm") || die "cannot open testout/t35ttfont.ppm\n";
  binmode(FH);
  $IO = Imager::io_new_fd( fileno(FH) );
  ok(i_writeppm_wiol($backgr, $IO), "save t35ttfont2.ppm");
  close(FH);
  
  my $exists_font = "fontfiles/ExistenceTest.ttf";
  my $hcfont = Imager::Font->new(file=>$exists_font, type=>'tt');
 SKIP:
  {
    ok($hcfont, "loading existence test font")
      or skip("could not load test font", 20);

    # list interface
    my @exists = $hcfont->has_chars(string=>'!A');
    ok(@exists == 2, "check return count");
    ok($exists[0], "we have an exclamation mark");
    ok(!$exists[1], "we have no exclamation mark");
    
    # scalar interface
    my $exists = $hcfont->has_chars(string=>'!A');
    ok(length($exists) == 2, "check return length");
    ok(ord(substr($exists, 0, 1)), "we have an exclamation mark");
    ok(!ord(substr($exists, 1, 1)), "we have no upper-case A");
    
    my $face_name = Imager::i_tt_face_name($hcfont->{id});
    print "# face $face_name\n";
    is($face_name, 'ExistenceTest', "face name (function)");
    $face_name = $hcfont->face_name;
    is($face_name, 'ExistenceTest', "face name (OO)");
    
    # FT 1.x cheats and gives names even if the font doesn't have them
    my @glyph_names = $hcfont->glyph_names(string=>"!J/");
    is($glyph_names[0], 'exclam', "check exclam name OO");
    ok(!defined($glyph_names[1]), "check for no J name OO");
    is($glyph_names[2], 'slash', "check slash name OO");
    
    print "# ** name table of the test font **\n";
    Imager::i_tt_dump_names($hcfont->{id});

    # the test font is known to have a shorter advance width for that char
    my @bbox = $hcfont->bounding_box(string=>"/", size=>100);
    is(@bbox, 8, "should be 8 entries");
    isnt($bbox[6], $bbox[2], "different advance width from pos width");
    print "# @bbox\n";
    my $bbox = $hcfont->bounding_box(string=>"/", size=>100);
    isnt($bbox->pos_width, $bbox->advance_width, "OO check");

    cmp_ok($bbox->right_bearing, '<', 0, "check right bearing");

    cmp_ok($bbox->display_width, '>', $bbox->advance_width,
           "check display width (roughly)");

    # check with a char that fits inside the box
    $bbox = $hcfont->bounding_box(string=>"!", size=>100);
    print "# @$bbox\n";
    print "# pos width ", $bbox->pos_width, "\n";
    is($bbox->pos_width, $bbox->advance_width, 
       "check backwards compatibility");
    cmp_ok($bbox->left_bearing, '>', 0, "left bearing positive");
    cmp_ok($bbox->right_bearing, '>', 0, "right bearing positive");
    cmp_ok($bbox->display_width, '<', $bbox->advance_width,
           "display smaller than advance");
  }
  undef $hcfont;
  
  my $name_font = "fontfiles/NameTest.ttf";
  $hcfont = Imager::Font->new(file=>$name_font, type=>'tt');
 SKIP:
  {
    ok($hcfont, "loading name font")
      or skip("could not load name font $name_font", 3);
    # make sure a missing string parameter is handled correctly
    eval {
      $hcfont->glyph_names();
    };
    is($@, "", "correct error handling");
    cmp_ok(Imager->errstr, '=~', qr/no string parameter/, "error message");
    
    my $text = pack("C*", 0xE2, 0x80, 0x90); # "\x{2010}" as utf-8
    my @names = $hcfont->glyph_names(string=>$text, utf8=>1);
    is($names[0], "hyphentwo", "check utf8 glyph name");
  }

  undef $hcfont;
  
 SKIP:
  { print "# alignment tests\n";
    my $font = Imager::Font->new(file=>'fontfiles/ImUgly.ttf', type=>'tt');
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
    ok($im->write(file=>'testout/t35align.ppm'), "save align image");
  }

  { # Ticket #14804 Imager::Font->new() doesn't report error details
    # when using freetype 1
    # make sure we're using C locale for messages
    use POSIX qw(setlocale LC_ALL);
    setlocale(LC_ALL, "C");

    my $font = Imager::Font->new(file=>'t/350-font/020-tt.t', type=>'tt');
    ok(!$font, "font creation should have failed for invalid file");
    cmp_ok(Imager->errstr, 'eq', 'Invalid file format.',
	  "test error message");

    setlocale(LC_ALL, "");
  }

  { # check errstr set correctly
    my $font = Imager::Font->new(file=>$fontname, type=>'tt',
				size => undef);
    ok($font, "made size error test font");
    my $im = Imager->new(xsize=>100, ysize=>100);
    ok($im, "made size error test image");
    ok(!$im->string(font=>$font, x=>10, 'y'=>50, string=>"Hello"),
       "drawing should fail with no size");
    is($im->errstr, "No font size provided", "check error message");

    # try no string
    ok(!$im->string(font=>$font, x=>10, 'y'=>50, size=>15),
       "drawing should fail with no string");
    is($im->errstr, "missing required parameter 'string'",
       "check error message");
  }

  { # introduced in 0.46 - outputting just space crashes
    my $im = Imager->new(xsize=>100, ysize=>100);
    my $font = Imager::Font->new(file=>'fontfiles/ImUgly.ttf', size=>14);
    ok($im->string(font=>$font, x=> 5, 'y' => 50, string=>' '),
      "outputting just a space was crashing");
  }

  { # string output cut off at NUL ('\0')
    # https://rt.cpan.org/Ticket/Display.html?id=21770 cont'd
    my $font = Imager::Font->new(file=>'fontfiles/ImUgly.ttf', type=>'tt');
    ok($font, "loaded imugly");

    diff_text_with_nul("a\\0b vs a", "a\0b", "a", 
		       font => $font, color => '#FFFFFF');
    diff_text_with_nul("a\\0b vs a", "a\0b", "a", 
		       font => $font, channel => 1);

    # UTF8 encoded \x{2010}
    my $dash = pack("C*", 0xE2, 0x80, 0x90);
    diff_text_with_nul("utf8 dash\\0dash vs dash", "$dash\0$dash", $dash,
		       font => $font, color => '#FFFFFF', utf8 => 1);
    diff_text_with_nul("utf8 dash\\0dash vs dash", "$dash\0$dash", $dash,
		       font => $font, channel => 1, utf8 => 1);
  }

 SKIP:
  { # RT 11972
    # when rendering to a transparent image the coverage should be
    # expressed in terms of the alpha channel rather than the color
    my $font = Imager::Font->new(file=>'fontfiles/ImUgly.ttf', type=>'tt');
    ok($font, "loaded fontfiles/ImUgly.ttf")
      or skip("Could not load test font: ".Imager->errstr, 4);
    my $im = Imager->new(xsize => 40, ysize => 20, channels => 4);
    ok($im->string(string => "AB", size => 20, aa => 1, color => '#F00',
		   x => 0, y => 15, font => $font),
       "draw to transparent image");
    #$im->write(file => "foo.png");
    my $im_noalpha = $im->convert(preset => 'noalpha');
    my $im_pal = $im->to_paletted(make_colors => 'mediancut');
    my @colors = $im_pal->getcolors;
    is(@colors, 2, "should be only 2 colors");
    @colors = sort { ($a->rgba)[0] <=> ($b->rgba)[0] } @colors;
    is_color3($colors[0], 0, 0, 0, "check we got black");
    is_color3($colors[1], 255, 0, 0, "and red");
  }

 SKIP:
  { # RT 71564
    my $noalpha = Imager::Color->new(255, 255, 255, 0);
    my $font = Imager::Font->new(file=>'fontfiles/ImUgly.ttf', type=>'tt',
				 color => $noalpha);
    ok($font, "loaded fontfiles/ImUgly.ttf")
      or skip("Could not load test font: ".Imager->errstr, 4);
    {
      my $im = Imager->new(xsize => 40, ysize => 20);
      my $copy = $im->copy;
      ok($im->string(string => "AB", size => 20, aa => 1,
		     x => 0, y => 15, font => $font),
	 "draw with transparent color, aa");
      is_image($im, $copy, "should draw nothing");
    }
    {
      my $im = Imager->new(xsize => 40, ysize => 20);
      my $copy = $im->copy;
      ok($im->string(string => "AB", size => 20, aa => 0,
		     x => 0, y => 15, font => $font),
	 "draw with transparent color, non-aa");
      is_image($im, $copy, "should draw nothing");
    }
  }

  ok(1, "end of code");
}
