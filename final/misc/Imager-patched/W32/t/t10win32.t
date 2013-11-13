#!perl -w
use strict;
use Test::More tests => 59;
use Imager qw(:all);
use Imager::Test qw(diff_text_with_nul isnt_image);
++$|;

ok(-d "testout" or mkdir("testout"), "testout directory");

ok($Imager::formats{w32}, "\$formats{w32} populated");

init_log("testout/t10w32font.log",1);

SKIP:
{
  print "# has w32\n";

  my $fontname=$ENV{'TTFONTTEST'} || 'Times New Roman Bold';
  
  # i_init_fonts(); # unnecessary for Win32 font support

  my $bgcolor=i_color_new(255,0,0,0);
  my $overlay=Imager::ImgRaw::new(200,70,3);
  
  my @bbox=Imager::Font::W32::i_wf_bbox($fontname, 50.0,'XMCLH');
  print "#bbox: ($bbox[0], $bbox[1]) - ($bbox[2], $bbox[3])\n";
  
  ok(Imager::Font::W32::i_wf_cp($fontname,$overlay,5,50,1,50.0,'XMCLH',1,1),
     "i_wf_cp smoke test");
  i_line($overlay,0,50,100,50,$bgcolor, 1);
  
  if (open(FH,">testout/t10font.ppm")) {
    binmode(FH);
    my $io = Imager::io_new_fd(fileno(FH));
    i_writeppm_wiol($overlay,$io);
    close(FH);
  }
  else {
    diag "cannot open testout/t10font.ppm: $!";
  }
  
  $bgcolor=i_color_set($bgcolor,200,200,200,255);
  my $backgr=Imager::ImgRaw::new(500,300,3);
  
  ok(Imager::Font::W32::i_wf_text($fontname,$backgr,100,100,$bgcolor,100,'MAW.',1, 1),
     "i_wf_text smoke test");
  i_line($backgr,0, 100, 499, 100, NC(0, 0, 255), 1);
  
  if (open(FH,">testout/t10font2.ppm")) {
    binmode(FH);
    my $io = Imager::io_new_fd(fileno(FH));
    i_writeppm_wiol($backgr,$io);
    close(FH);
  }
  else {
    diag "cannot open testout/t10font2.ppm: $!";
  }

  my $img = Imager->new(xsize=>200, ysize=>200);
  my $font = Imager::Font->new(face=>$fontname, size=>20);
  ok($img->string('x'=>30, 'y'=>30, string=>"Imager", color=>NC(255, 0, 0), 
	       font=>$font),
     "string with win32 smoke test")
    or diag "simple string output: ",$img->errstr;
  $img->write(file=>'testout/t10_oo.ppm')
    or diag "Cannot save t10_oo.ppm: ", $img->errstr;
  my @bbox2 = $font->bounding_box(string=>'Imager');
  is(@bbox2, 8, "got 8 values from bounding_box");

  # this only applies while the Win32 driver returns 6 values
  # at this point we don't return the advance width from the low level
  # bounding box function, so the Imager::Font::BBox advance method should
  # return end_offset, check it does
  my $bbox = $font->bounding_box(string=>"some text");
  ok($bbox, "got the bounding box object");
  is($bbox->advance_width, $bbox->end_offset, 
     "check advance_width fallback correct");

 SKIP:
  {
    $^O eq 'cygwin' and skip("Too hard to get correct directory for test font on cygwin", 13);
    my $extra_font = "fontfiles/ExistenceTest.ttf";
    unless (ok(Imager::Font::W32::i_wf_addfont($extra_font), "add test font")) {
      diag "adding font resource: ",Imager::_error_as_msg();
      skip("Could not add font resource", 12);
    }
    
    my $namefont = Imager::Font->new(face=>"ExistenceTest");
    ok($namefont, "create font based on added font");
    
    # the test font is known to have a shorter advance width for that char
    @bbox = $namefont->bounding_box(string=>"/", size=>100);
    print "# / box: @bbox\n";
    is(@bbox, 8, "should be 8 entries");
    isnt($bbox[6], $bbox[2], "different advance width");
    $bbox = $namefont->bounding_box(string=>"/", size=>100);
    isnt($bbox->pos_width, $bbox->advance_width, "OO check");
    
    cmp_ok($bbox->right_bearing, '<', 0, "check right bearing");
  
    cmp_ok($bbox->display_width, '>', $bbox->advance_width,
	   "check display width (roughly)");
    
    my $im = Imager->new(xsize=>200, ysize=>200);
    $im->box(filled => 1, color => '#202020');
    $im->box(box => [ 20 + $bbox->neg_width, 100-$bbox->ascent,
		      20+$bbox->advance_width-$bbox->right_bearing, 100-$bbox->descent ],
	     color => '#101010', filled => 1);
    $im->line(color=>'blue', x1=>20, y1=>0, x2=>20, y2=>199);
    my $right = 20 + $bbox->advance_width;
    $im->line(color=>'blue', x1=>$right, y1=>0, x2=>$right, y2=>199);
    $im->line(color=>'blue', x1=>0, y1 => 100, x2=>199, y2 => 100);
    ok($im->string(font=>$namefont, text=>"/", x=>20, y=>100, color=>'white', size=>100),
       "draw / from ExistenceText")
	or diag "draw / from ExistenceTest:", $im->errstr;
    $im->setpixel(x => 20+$bbox->neg_width, y => 100-$bbox->ascent, color => 'red');
    $im->setpixel(x => 20+$bbox->advance_width - $bbox->right_bearing, y => 100-$bbox->descent, color => 'red');
    $im->write(file=>'testout/t10_slash.ppm');
    
    # check with a char that fits inside the box
    $bbox = $namefont->bounding_box(string=>"!", size=>100);
    print "# pos width ", $bbox->pos_width, "\n";
    print "# ! box: @$bbox\n";
    is($bbox->pos_width, $bbox->advance_width, 
     "check backwards compatibility");
    cmp_ok($bbox->left_bearing, '>', 0, "left bearing positive");
    cmp_ok($bbox->right_bearing, '>', 0, "right bearing positive");
    cmp_ok($bbox->display_width, '<', $bbox->advance_width,
	   "display smaller than advance");

    $im = Imager->new(xsize=>200, ysize=>200);
    $im->box(filled => 1, color => '#202020');
    $im->box(box => [ 20 + $bbox->neg_width, 100-$bbox->ascent,
		      20+$bbox->advance_width-$bbox->right_bearing, 100-$bbox->descent ],
	     color => '#101010', filled => 1);
    $im->line(color=>'blue', x1=>20, y1=>0, x2=>20, y2=>199);
    $right = 20 + $bbox->advance_width;
    $im->line(color=>'blue', x1=>$right, y1=>0, x2=>$right, y2=>199);
    $im->line(color=>'blue', x1=>0, y1 => 100, x2=>199, y2 => 100);
    ok($im->string(font=>$namefont, text=>"!", x=>20, y=>100, color=>'white', size=>100),
       "draw / from ExistenceText")
	or diag "draw / from ExistenceTest: ", $im->errstr;
    $im->setpixel(x => 20+$bbox->neg_width, y => 100-$bbox->ascent, color => 'red');
    $im->setpixel(x => 20+$bbox->advance_width - $bbox->right_bearing, y => 100-$bbox->descent, color => 'red');
    $im->write(file=>'testout/t10_bang.ppm');

    Imager::Font::W32::i_wf_delfont("fontfiles/ExistenceTest.ttf");
  }

 SKIP:
  { print "# alignment tests\n";
    my $font = Imager::Font->new(face=>"Arial");
    ok($font, "loaded Arial OO")
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
      print "# ", join(",", @$args), "\n";
      ok($im->string(%common, @$args, 'y'=>40), "A no alignment");
      ok($im->string(%common, @$args, 'y'=>90, align=>1), "A align=1");
      ok($im->string(%common, @$args, 'y'=>110, align=>0), "A align=0");
    }
    ok($im->write(file=>'testout/t10align.ppm'), "save align image");
  }
  { print "# utf 8 support\n";
    my $font = Imager::Font->new(face => "Arial");
    ok($font, "created font");
    my $im = Imager->new(xsize => 100, ysize => 100);
    ok($im->string(string => "\xE2\x98\xBA", size => 80, aa => 1, utf8 => 1, 
		   color => "white", font => $font, x => 5, y => 80),
       "draw in utf8 (hand encoded)")
	or diag "draw utf8 hand-encoded ", $im->errstr;
    ok($im->write(file=>'testout/t10utf8.ppm'), "save utf8 image")
      or diag "save t10utf8.ppm: ", $im->errstr;

    # native perl utf8
    # Win32 only supported on 5.6+
    # since this gets compiled even on older perls we need to be careful 
    # creating the string
    my $text;
    eval q{$text = "\x{263A}"}; # A, HYPHEN, A in our test font
    my $im2 = Imager->new(xsize => 100, ysize => 100);
    ok($im2->string(string => $text, size => 80, aa => 1,
		    color => 'white', font => $font, x => 5, y => 80),
       "draw in utf8 (perl utf8)")
	or diag "draw in utf8: ", $im->errstr;
    ok($im2->write(file=>'testout/t10utf8b.ppm'), "save utf8 image");
    is(Imager::i_img_diff($im->{IMG}, $im2->{IMG}), 0,
       "check result is the same");

    # bounding box
    cmp_ok($font->bounding_box(string=>$text, size => 80)->advance_width, '<', 100,
	   "check we only get width of single char rather than 3");
  }

  { # string output cut off at NUL ('\0')
    # https://rt.cpan.org/Ticket/Display.html?id=21770 cont'd
    my $font = Imager::Font->new(face=>'Arial', type=>'w32');
    ok($font, "loaded Arial");

    diff_text_with_nul("a\\0b vs a", "a\0b - color", "a", 
		       font => $font, color => '#FFFFFF');
    diff_text_with_nul("a\\0b vs a", "a\0b - channel", "a", 
		       font => $font, channel => 1);

    # UTF8 encoded \x{2010}
    my $dash = pack("C*", 0xE2, 0x80, 0x90);
    diff_text_with_nul("utf8 dash\0dash vs dash - color", "$dash\0$dash", $dash,
		       font => $font, color => '#FFFFFF', utf8 => 1);
    diff_text_with_nul("utf8 dash\0dash vs dash - channel", "$dash\0$dash", $dash,
		       font => $font, channel => 1, utf8 => 1);
  }

  { # RT 71469
    my $font1 = Imager::Font->new(face => $fontname, type => "w32");
    my $font2 = Imager::Font::W32->new(face => $fontname );

    for my $font ($font1, $font2) {
      print "# ", join(",", $font->{color}->rgba), "\n";

      my $im = Imager->new(xsize => 20, ysize => 20, channels => 4);

      ok($im->string(text => "T", font => $font, y => 15),
	 "draw with default color")
	or diag "draw with default color: ", $im->errstr;
      my $work = Imager->new(xsize => 20, ysize => 20);
      my $cmp = $work->copy;
      $work->rubthrough(src => $im);
      isnt_image($work, $cmp, "make sure something was drawn");
    }
  }
}
