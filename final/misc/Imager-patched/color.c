#include "imager.h"
#include <math.h>

/*
=head1 NAME

color.c - color manipulation functions

=head1 SYNOPSIS

  i_fcolor color;
  i_rgb_to_hsvf(&color);
  i_hsv_to_rgbf(&color);

=head1 DESCRIPTION

A collection of utility functions for converting between color spaces.

=over

=cut
*/

#define EPSILON (1e-8)

#define my_max(a, b) ((a) < (b) ? (b) : (a))
#define my_min(a, b) ((a) > (b) ? (b) : (a))

/*
=item i_rgb2hsvf(&color)

Converts the first 3 channels of color into hue, saturation and value.

Each value is scaled into the range 0 to 1.0.

=cut
*/
void i_rgb_to_hsvf(i_fcolor *color) {
  double h = 0, s, v;
  double temp;
  double Cr, Cg, Cb;

  v = my_max(my_max(color->rgb.r, color->rgb.g), color->rgb.b);
  temp = my_min(my_min(color->rgb.r, color->rgb.g), color->rgb.b);
  if (v < EPSILON)
    s = 0;
  else
    s = (v-temp)/v;
  if (s == 0)
    h = 0;
  else {
    Cr = (v - color->rgb.r)/(v-temp);
    Cg = (v - color->rgb.g)/(v-temp);
    Cb = (v - color->rgb.b)/(v-temp);
    if (color->rgb.r == v)
      h = Cb - Cg;
    else if (color->rgb.g == v)
      h = 2 + Cr - Cb;
    else if (color->rgb.b == v)
      h = 4 + Cg - Cr;
    h = 60 * h;
    if (h < 0)
      h += 360;
  }
  color->channel[0] = h / 360.0;
  color->channel[1] = s;
  color->channel[2] = v;
}

/*
=item i_rgb2hsv(&color)

Converts the first 3 channels of color into hue, saturation and value.

Each value is scaled into the range 0 to 255.

=cut
*/
void i_rgb_to_hsv(i_color *color) {
  double h = 0, s, v;
  double temp;
  double Cr, Cg, Cb;

  v = my_max(my_max(color->rgb.r, color->rgb.g), color->rgb.b);
  temp = my_min(my_min(color->rgb.r, color->rgb.g), color->rgb.b);
  if (v == 0)
    s = 0;
  else
    s = (v-temp)*255/v;
  if (s == 0)
    h = 0;
  else {
    Cr = (v - color->rgb.r)/(v-temp);
    Cg = (v - color->rgb.g)/(v-temp);
    Cb = (v - color->rgb.b)/(v-temp);
    if (color->rgb.r == v)
      h = Cb - Cg;
    else if (color->rgb.g == v)
      h = 2 + Cr - Cb;
    else if (color->rgb.b == v)
      h = 4 + Cg - Cr;
    h = h * 60.0;
    if (h < 0)
      h += 360;
  }
  color->channel[0] = h * 255 / 360.0;
  color->channel[1] = s;
  color->channel[2] = v;
}

/*
=item i_hsv_to_rgbf(&color)

Convert a HSV value to an RGB value, each value ranges from 0 to 1.

=cut
*/

void i_hsv_to_rgbf(i_fcolor *color) {
  double h = color->channel[0];
  double s = color->channel[1];
  double v = color->channel[2];

  if (color->channel[1] < EPSILON) {
    /* ignore h in this case */
    color->rgb.r = color->rgb.g = color->rgb.b = v;
  }
  else {
    int i;
    double f, m, n, k;
    h = fmod(h, 1.0) * 6;
    i = floor(h);
    f = h - i;
    m = v * (1 - s);
    n = v * (1 - s * f);
    k = v * (1 - s * (1 - f));
    switch (i) {
    case 0:
      color->rgb.r = v; color->rgb.g = k; color->rgb.b = m;
      break;
    case 1:
      color->rgb.r = n; color->rgb.g = v; color->rgb.b = m;
      break;
    case 2:
      color->rgb.r = m; color->rgb.g = v; color->rgb.b = k;
      break;
    case 3:
      color->rgb.r = m; color->rgb.g = n; color->rgb.b = v;
      break;
    case 4:
      color->rgb.r = k; color->rgb.g = m; color->rgb.b = v;
      break;
    case 5:
      color->rgb.r = v; color->rgb.g = m; color->rgb.b = n;
      break;
    }
  }
}

/*
=item i_hsv_to_rgb(&color)

Convert a HSV value to an RGB value, each value ranges from 0 to 1.

=cut
*/

void i_hsv_to_rgb(i_color *color) {
  double h = color->channel[0];
  double s = color->channel[1];
  double v = color->channel[2];

  if (color->channel[1] == 0) {
    /* ignore h in this case */
    color->rgb.r = color->rgb.g = color->rgb.b = v;
  }
  else {
    int i;
    double f;
    int m, n, k;
    h = h / 255.0 * 6;
    i = h;
    f = h - i;
    m = 0.5 + v * (255 - s) / 255;
    n = 0.5 + v * (255 - s * f) / 255;
    k = 0.5 + v * (255 - s * (1 - f)) / 255;
    switch (i) {
    case 0:
      color->rgb.r = v; color->rgb.g = k; color->rgb.b = m;
      break;
    case 1:
      color->rgb.r = n; color->rgb.g = v; color->rgb.b = m;
      break;
    case 2:
      color->rgb.r = m; color->rgb.g = v; color->rgb.b = k;
      break;
    case 3:
      color->rgb.r = m; color->rgb.g = n; color->rgb.b = v;
      break;
    case 4:
      color->rgb.r = k; color->rgb.g = m; color->rgb.b = v;
      break;
    case 5:
      color->rgb.r = v; color->rgb.g = m; color->rgb.b = n;
      break;
    }
  }
}

/*
=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=head1 SEE ALSO

Imager

=cut
*/
