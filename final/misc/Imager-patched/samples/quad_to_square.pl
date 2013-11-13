#!/usr/bin/perl -w
use strict;
# Convert quadrilateral to square

use Imager;

my $src=Imager->new();
$src->open(file=>"oldmap_200px.jpg");

# example co-ordinates of quadrilateral
my $x0=12; my $y0=4; # top left
my $x1=157; my $y1=0; # top right
my $x2=140; my $y2=150; # bottom right
my $x3=27; my $y3=159; # bottom left

my $code=<<EOF;
xa=((h-y)*x0+y*x3)/h; ya=((h-y)*y0+y*y3)/h;
xb=((h-y)*x1+y*x2)/h; yb=((h-y)*y1+y*y2)/h;
xc=((w-x)*x0+x*x1)/w; yc=((w-x)*y0+x*y1)/w;
xd=((w-x)*x3+x*x2)/w; yd=((w-x)*y3+x*y2)/w;

d=det(xa-xb,ya-yb,xc-xd,yc-yd);
d=if(d==0,1,d);

px=det(det(xa,ya,xb,yb),xa-xb,det(xc,yc,xd,yd),xc-xd)/d;
py=det(det(xa,ya,xb,yb),ya-yb,det(xc,yc,xd,yd),yc-yd)/d;
return getp1(px,py);
EOF

my $newimg=Imager::transform2({
expr=>$code,
width=>200,
height=>200,
constants=>{x0=>$x0,y0=>$y0,
x1=>$x1,y1=>$y1,
x2=>$x2,y2=>$y2,
x3=>$x3,y3=>$y3}},
($src));
$newimg->write(file=>"output_imager.jpg");

=head1 NAME

quad_to_square.pl - transform an arbitrary quadrilateral to a square.

=head1 SYNOPSIS

  perl quad_to_square.pl

=head1 DESCRIPTION

=for stopwords Fairhurst resized

Courtesy Richard Fairhurst:

I've been using it to rectify ("square up") a load of roughly scanned
maps, so that an arbitrary quadrilateral is resized into a square. The
transform2 function is ideal for that.

Thought you might be interested to see what people are doing with
Imager - feel free to include this in the sample code.

=head1 AUTHOR

Richard Fairhurst

=cut
