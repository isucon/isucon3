#!perl -w

use strict;
use Test::More tests => 18;

use Imager qw/NC/;
use Imager::Test qw(is_image is_color3);

sub PI () { 3.14159265358979323846 }

-d "testout" or mkdir "testout";

Imager::init_log("testout/t75aapolyaa.log",1);

my $red   = Imager::Color->new(255,0,0);
my $green = Imager::Color->new(0,255,0);
my $blue  = Imager::Color->new(0,0,255);
my $white = Imager::Color->new(255,255,255);

{ # artifacts with multiple vertical lobes
  # https://rt.cpan.org/Ticket/Display.html?id=43518
  # previously this would have a full coverage pixel at (0,0) caused
  # by the (20,0.5) point in the right lobe

  my @pts = 
    (
     [ 0.5, -9 ],
     [ 10, -9 ],
     [ 10, 11 ],
     [ 15, 11 ],
     [ 15, -9 ],
     [ 17, -9 ],
     [ 20, 0.5 ],
     [ 17, 11 ],
     [ 0.5, 11 ],
    );
  my $im = Imager->new(xsize => 10, ysize => 2);
  ok($im->polygon(points => \@pts,
		  color => $white),
     "draw with inside point");
  ok($im->write(file => "testout/t75inside.ppm"), "save to file");
  # both scanlines should be the same
  my $line0 = $im->crop(top => 0, height => 1);
  my $line1 = $im->crop(top => 1, height => 1);
  is_image($line0, $line1, "both scanlines should be the same");
}

{ # check vertical edges are consistent
  my $im = Imager->new(xsize => 10, ysize => 10);
  ok($im->polygon(points => [ [ 0.5, 0 ], [ 9.25, 0 ], 
			      [ 9.25, 10 ], [ 0.5, 10 ] ],
		  color => $white,
		  aa => 1), 
     "draw polygon with mid pixel vertical edges")
    or diag $im->errstr;
  my @line0 = $im->getscanline(y => 0);
  my $im2 = Imager->new(xsize => 10, ysize => 10);
  for my $y (0..9) {
    $im2->setscanline(y => $y, pixels => \@line0);
  }
  is_image($im, $im2, "all scan lines should be the same");
  is_color3($line0[0], 128, 128, 128, "(0,0) should be 50% coverage");
  is_color3($line0[9], 64, 64, 64, "(9,0) should be 25% coverage");
}

{ # check horizontal edges are consistent
  my $im = Imager->new(xsize => 10, ysize => 10);
  ok($im->polygon(points => [ [ 0, 0.5 ], [ 0, 9.25 ],
			      [ 10, 9.25 ], [ 10, 0.5 ] ],
		  color => $white,
		  aa => 1),
     "draw polygon with mid-pixel horizontal edges");
  is_deeply([ $im->getsamples(y => 0, channels => [ 0 ]) ],
	    [ (128) x 10 ],
	    "all of line 0 should be 50% coverage");
  is_deeply([ $im->getsamples(y => 9, channels => [ 0 ]) ],
	    [ (64) x 10 ],
	    "all of line 9 should be 25% coverage");
}

{
  my $img = Imager->new(xsize=>20, ysize=>10);
  my @data = translate(5.5,5,
		       rotate(0,
			      scale(5, 5,
				    get_polygon(n_gon => 5)
				   )
			     )
		      );
  
  
  my ($x, $y) = array_to_refpair(@data);
  ok(Imager::i_poly_aa($img->{IMG}, $x, $y, $white), "primitive poly");

  ok($img->write(file=>"testout/t75.ppm"), "write to file")
    or diag $img->errstr;

  my $zoom = make_zoom($img, 8, \@data, $red);
  ok($zoom, "make zoom of primitive");
  $zoom->write(file=>"testout/t75zoom.ppm") or die $zoom->errstr;
}

{
  my $img = Imager->new(xsize=>300, ysize=>100);

  my $good = 1;
  for my $n (0..55) {
    my @data = translate(20+20*($n%14),18+20*int($n/14),
			 rotate(15*$n/PI,
				scale(15, 15,
				      get_polygon('box')
				     )
			       )
			);
    my ($x, $y) = array_to_refpair(@data);
    Imager::i_poly_aa($img->{IMG}, $x, $y, NC(rand(255), rand(255), rand(255)))
	or $good = 0;
  }
  
  $img->write(file=>"testout/t75big.ppm") or die $img->errstr;

  ok($good, "primitive squares");
}

{
  my $img = Imager->new(xsize => 300, ysize => 300);
  ok($img -> polygon(color=>$white,
		  points => [
			     translate(150,150,
				       rotate(45*PI/180,
					      scale(70,70,
						    get_polygon('wavycircle', 32*8, sub { 1.2+1*cos(4*$_) }))))
			    ],
		 ), "method call")
    or diag $img->errstr();

  $img->write(file=>"testout/t75wave.ppm") or die $img->errstr;
}

{
  my $img = Imager->new(xsize=>10,ysize=>6);
  my @data = translate(165,5,
		       scale(80,80,
			     get_polygon('wavycircle', 32*8, sub { 1+1*cos(4*$_) })));
  
  ok($img -> polygon(color=>$white,
		points => [
			   translate(165,5,
				     scale(80,80,
					   get_polygon('wavycircle', 32*8, sub { 1+1*cos(4*$_) })))
			  ],
		 ), "bug check")
    or diag $img->errstr();

  make_zoom($img,20,\@data, $blue)->write(file=>"testout/t75wavebug.ppm") or die $img->errstr;

}

{
  my $img = Imager->new(xsize=>300, ysize=>300);
  ok($img->polygon(fill=>{ hatch=>'cross1', fg=>'00FF00', bg=>'0000FF', dx=>3 },
              points => [
                         translate(150,150,
                                   scale(70,70,
                                         get_polygon('wavycircle', 32*8, sub { 1+1*cos(4*$_) })))
                        ],
             ), "poly filled with hatch")
    or diag $img->errstr();
  $img->write(file=>"testout/t75wave_fill.ppm") or die $img->errstr;
}

{
  my $img = Imager->new(xsize=>300, ysize=>300, bits=>16);
  ok($img->polygon(fill=>{ hatch=>'cross1', fg=>'00FF00', bg=>'0000FF' },
              points => [
                         translate(150,150,
                                   scale(70,70,
                                         get_polygon('wavycircle', 32*8, sub { 1+1*cos(5*$_) })))
                        ],
             ), "hatched to 16-bit image")
    or diag $img->errstr();
  $img->write(file=>"testout/t75wave_fill16.ppm") or die $img->errstr;
}

Imager::malloc_state();


#initialized in a BEGIN, later
my %primitives;
my %polygens;

sub get_polygon {
  my $name = shift;
  if (exists $primitives{$name}) {
    return @{$primitives{$name}};
  }

  if (exists $polygens{$name}) {
    return $polygens{$name}->(@_);
  }

  die "polygon spec: $name unknown\n";
}


sub make_zoom {
  my ($img, $sc, $polydata, $linecolor) = @_;

  # scale with nearest neighboor sampling
  my $timg = $img->scale(scalefactor=>$sc, qtype=>'preview');

  # draw the grid
  for(my $lx=0; $lx<$timg->getwidth(); $lx+=$sc) {
    $timg->line(color=>$green, x1=>$lx, x2=>$lx, y1=>0, y2=>$timg->getheight(), antialias=>0);
  }

  for(my $ly=0; $ly<$timg->getheight(); $ly+=$sc) {
    $timg->line(color=>$green, y1=>$ly, y2=>$ly, x1=>0, x2=>$timg->getwidth(), antialias=>0);
  }
  my @data = scale($sc, $sc, @$polydata);
  push(@data, $data[0]);
  my ($x, $y) = array_to_refpair(@data);

  $timg->polyline(color=>$linecolor, 'x'=>$x, 'y'=>$y, antialias=>0);
  return $timg;
}

# utility functions to manipulate point data

sub scale {
  my ($x, $y, @data) = @_;
  return map { [ $_->[0]*$x , $_->[1]*$y ] } @data;
}

sub translate {
  my ($x, $y, @data) = @_;
  map { [ $_->[0]+$x , $_->[1]+$y ] } @data;
}

sub rotate {
  my ($rad, @data) = @_;
  map { [ $_->[0]*cos($rad)+$_->[1]*sin($rad) , $_->[1]*cos($rad)-$_->[0]*sin($rad) ] } @data;
}

sub array_to_refpair {
  my (@x, @y);
  for (@_) {
    push(@x, $_->[0]);
    push(@y, $_->[1]);
  }
  return \@x, \@y;
}



BEGIN {
%primitives = (
	       box => [ [-0.5,-0.5], [0.5,-0.5], [0.5,0.5], [-0.5,0.5] ],
	       triangle => [ [0,0], [1,0], [1,1] ],
	      );

%polygens = (
	     wavycircle => sub {
	       my $numv = shift;
	       my $radfunc = shift;
	       my @radians = map { $_*2*PI/$numv } 0..$numv-1;
	       my @radius  = map { $radfunc->($_) } @radians;
	       map {
		 [ $radius[$_] * cos($radians[$_]), $radius[$_] * sin($radians[$_]) ]
	       } 0..$#radians;
	     },
	     n_gon => sub {
	       my $N = shift;
	       map {
		 [ cos($_*2*PI/$N), sin($_*2*PI/$N) ]
	       } 0..$N-1;
	     },
);
}
