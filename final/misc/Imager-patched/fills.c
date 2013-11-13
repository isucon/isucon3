#define IMAGER_NO_CONTEXT
#include "imager.h"
#include "imageri.h"

/*
=head1 NAME

fills.c - implements the basic general fills

=head1 SYNOPSIS

  i_fill_t *fill;
  i_color c1, c2;
  i_fcolor fc1, fc2;
  int combine;
  fill = i_new_fill_solidf(&fc1, combine);
  fill = i_new_fill_solid(&c1, combine);
  fill = i_new_fill_hatchf(&fc1, &fc2, combine, hatch, cust_hash, dx, dy);
  fill = i_new_fill_hatch(&c1, &c2, combine, hatch, cust_hash, dx, dy);
  fill = i_new_fill_image(im, matrix, xoff, yoff, combine);
  fill = i_new_fill_opacity(fill, alpha_mult);
  i_fill_destroy(fill);

=head1 DESCRIPTION

Implements the basic general fills, which can be used for filling some
shapes and for flood fills.

Each fill can implement up to 3 functions:

=over

=item fill_with_color

called for fills on 8-bit images.  This can be NULL in which case the
fill_with_colorf function is called.

=item fill_with_fcolor

called for fills on non-8-bit images or when fill_with_color is NULL.

=item destroy

called by i_fill_destroy() if non-NULL, to release any extra resources
that the fill may need.

=back

fill_with_color and fill_with_fcolor are basically the same function
except that the first works with lines of i_color and the second with
lines of i_fcolor.

If the combines member if non-zero the line data is populated from the
target image before calling fill_with_*color.

fill_with_color needs to fill the I<data> parameter with the fill
pixels.  If combines is non-zero it the fill pixels should be combined
with the existing data.

The current fills are:

=over

=item *

solid fill

=item *

hatched fill

=item *

fountain fill

=back

Fountain fill is implemented by L<filters.c>.

Other fills that could be implemented include:

=over

=item *

image - an image tiled over the fill area, with an offset either
horizontally or vertically.

=item *

checkerboard - combine 2 fills in a checkerboard

=item *

combine - combine the levels of 2 other fills based in the levels of
an image

=item *

regmach - use the register machine to generate colors

=back

=over

=cut
*/

static i_color fcolor_to_color(const i_fcolor *c) {
  int ch;
  i_color out;

  for (ch = 0; ch < MAXCHANNELS; ++ch)
    out.channel[ch] = SampleFTo8(c->channel[ch]);

  return out;
}

static i_fcolor color_to_fcolor(const i_color *c) {
  int ch;
  i_fcolor out;

  for (ch = 0; ch < MAXCHANNELS; ++ch)
    out.channel[ch] = Sample8ToF(c->channel[ch]);

  return out;
}

/* alpha combine in with out */
#define COMBINE(out, in, channels) \
  { \
    int ch; \
    for (ch = 0; ch < (channels); ++ch) { \
      (out).channel[ch] = ((out).channel[ch] * (255 - (in).channel[3]) \
        + (in).channel[ch] * (in).channel[3]) / 255; \
    } \
  }

/* alpha combine in with out, in this case in is a simple array of
   samples, potentially not integers - the mult combiner uses doubles
   for accuracy */
#define COMBINEA(out, in, channels) \
  { \
    int ch; \
    for (ch = 0; ch < (channels); ++ch) { \
      (out).channel[ch] = ((out).channel[ch] * (255 - (in)[3]) \
        + (in)[ch] * (in)[3]) / 255; \
    } \
  }

#define COMBINEF(out, in, channels) \
  { \
    int ch; \
    for (ch = 0; ch < (channels); ++ch) { \
      (out).channel[ch] = (out).channel[ch] * (1.0 - (in).channel[3]) \
        + (in).channel[ch] * (in).channel[3]; \
    } \
  }

typedef struct
{
  i_fill_t base;
  i_color c;
  i_fcolor fc;
} i_fill_solid_t;

static void fill_solid(i_fill_t *, i_img_dim x, i_img_dim y, i_img_dim width,
		       int channels, i_color *);
static void fill_solidf(i_fill_t *, i_img_dim x, i_img_dim y, i_img_dim width,
			int channels, i_fcolor *);

static i_fill_solid_t base_solid_fill =
{
  {
    fill_solid,
    fill_solidf,
    NULL,
    NULL,
    NULL,
  },
};

/*
=item i_fill_destroy(fill)
=order 90
=category Fills
=synopsis i_fill_destroy(fill);

Call to destroy any fill object.

=cut
*/

void
i_fill_destroy(i_fill_t *fill) {
  if (fill->destroy)
    (fill->destroy)(fill);
  myfree(fill);
}

/*
=item i_new_fill_solidf(color, combine)

=category Fills
=synopsis i_fill_t *fill = i_new_fill_solidf(&fcolor, combine);

Create a solid fill based on a float color.

If combine is non-zero then alpha values will be combined.

=cut
*/

i_fill_t *
i_new_fill_solidf(const i_fcolor *c, int combine) {
  int ch;
  i_fill_solid_t *fill = mymalloc(sizeof(i_fill_solid_t)); /* checked 14jul05 tonyc */
  
  *fill = base_solid_fill;
  if (combine) {
    i_get_combine(combine, &fill->base.combine, &fill->base.combinef);
  }

  fill->fc = *c;
  for (ch = 0; ch < MAXCHANNELS; ++ch) {
    fill->c.channel[ch] = SampleFTo8(c->channel[ch]);
  }
  
  return &fill->base;
}

/*
=item i_new_fill_solid(color, combine)

=category Fills
=synopsis i_fill_t *fill = i_new_fill_solid(&color, combine);

Create a solid fill based on an 8-bit color.

If combine is non-zero then alpha values will be combined.

=cut
*/

i_fill_t *
i_new_fill_solid(const i_color *c, int combine) {
  int ch;
  i_fill_solid_t *fill = mymalloc(sizeof(i_fill_solid_t)); /* checked 14jul05 tonyc */

  *fill = base_solid_fill;
  if (combine) {
    i_get_combine(combine, &fill->base.combine, &fill->base.combinef);
  }

  fill->c = *c;
  for (ch = 0; ch < MAXCHANNELS; ++ch) {
    fill->fc.channel[ch] = Sample8ToF(c->channel[ch]);
  }
  
  return &fill->base;
}

static unsigned char
builtin_hatches[][8] =
{
  {
    /* 1x1 checkerboard */
    0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55,
  },
  {
    /* 2x2 checkerboard */
    0xCC, 0xCC, 0x33, 0x33, 0xCC, 0xCC, 0x33, 0x33,
  },
  {
    /* 4 x 4 checkerboard */
    0xF0, 0xF0, 0xF0, 0xF0, 0x0F, 0x0F, 0x0F, 0x0F,
  },
  {
    /* single vertical lines */
    0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
  },
  {
    /* double vertical lines */
    0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 
  },
  {
    /* quad vertical lines */
    0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55,
  },
  {
    /* single hlines */
    0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  },
  {
    /* double hlines */
    0xFF, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00,
  },
  {
    /* quad hlines */
    0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00,
  },
  {
    /* single / */
    0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80,
  },
  {
    /* single \ */
    0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01,
  },
  {
    /* double / */
    0x11, 0x22, 0x44, 0x88, 0x11, 0x22, 0x44, 0x88,
  },
  {
    /* double \ */
    0x88, 0x44, 0x22, 0x11, 0x88, 0x44, 0x22, 0x11,
  },
  {
    /* single grid */
    0xFF, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,
  },
  {
    /* double grid */
    0xFF, 0x88, 0x88, 0x88, 0xFF, 0x88, 0x88, 0x88,
  },
  {
    /* quad grid */
    0xFF, 0xAA, 0xFF, 0xAA, 0xFF, 0xAA, 0xFF, 0xAA,
  },
  {
    /* single dots */
    0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  },
  {
    /* 4 dots */
    0x88, 0x00, 0x00, 0x00, 0x88, 0x00, 0x00, 0x00,
  },
  {
    /* 16 dots */
    0xAA, 0x00, 0xAA, 0x00, 0xAA, 0x00, 0xAA, 0x00,
  },
  {
    /* simple stipple */
    0x48, 0x84, 0x00, 0x00, 0x84, 0x48, 0x00, 0x00,
  },
  {
    /* weave */
    0x55, 0xFD, 0x05, 0xFD, 0x55, 0xDF, 0x50, 0xDF,
  },
  {
    /* single cross hatch */
    0x82, 0x44, 0x28, 0x10, 0x28, 0x44, 0x82, 0x01,
  },
  {
    /* double cross hatch */
    0xAA, 0x44, 0xAA, 0x11, 0xAA, 0x44, 0xAA, 0x11,
  },
  {
    /* vertical lozenge */
    0x11, 0x11, 0x11, 0xAA, 0x44, 0x44, 0x44, 0xAA,
  },
  {
    /* horizontal lozenge */
    0x88, 0x70, 0x88, 0x07, 0x88, 0x70, 0x88, 0x07,
  },
  {
    /* scales overlapping downwards */
    0x80, 0x80, 0x41, 0x3E, 0x08, 0x08, 0x14, 0xE3,
  },
  {
    /* scales overlapping upwards */
    0xC7, 0x28, 0x10, 0x10, 0x7C, 0x82, 0x01, 0x01,
  },
  {
    /* scales overlapping leftwards */
    0x83, 0x84, 0x88, 0x48, 0x38, 0x48, 0x88, 0x84,
  },
  {
    /* scales overlapping rightwards */
    0x21, 0x11, 0x12, 0x1C, 0x12, 0x11, 0x21, 0xC1,
  },
  {
    /* denser stipple */
    0x44, 0x88, 0x22, 0x11, 0x44, 0x88, 0x22, 0x11,
  },
  {
    /* L-shaped tiles */
    0xFF, 0x84, 0x84, 0x9C, 0x94, 0x9C, 0x90, 0x90,
  },
  {
    /* wider stipple */
    0x80, 0x40, 0x20, 0x00, 0x02, 0x04, 0x08, 0x00,
  },
};

typedef struct
{
  i_fill_t base;
  i_color fg, bg;
  i_fcolor ffg, fbg;
  unsigned char hatch[8];
  i_img_dim dx, dy;
} i_fill_hatch_t;

static void fill_hatch(i_fill_t *fill, i_img_dim x, i_img_dim y,
		       i_img_dim width, int channels, i_color *data);
static void fill_hatchf(i_fill_t *fill, i_img_dim x, i_img_dim y,
			i_img_dim width, int channels, i_fcolor *data);
static
i_fill_t *
i_new_hatch_low(const i_color *fg, const i_color *bg, const i_fcolor *ffg, const i_fcolor *fbg, 
                int combine, int hatch, const unsigned char *cust_hatch,
                i_img_dim dx, i_img_dim dy);

/*
=item i_new_fill_hatch(C<fg>, C<bg>, C<combine>, C<hatch>, C<cust_hatch>, C<dx>, C<dy>)

=category Fills
=synopsis i_fill_t *fill = i_new_fill_hatch(&fg_color, &bg_color, combine, hatch, custom_hatch, dx, dy);

Creates a new hatched fill with the C<fg> color used for the 1 bits in
the hatch and C<bg> for the 0 bits.  If C<combine> is non-zero alpha
values will be combined.

If C<cust_hatch> is non-NULL it should be a pointer to 8 bytes of the
hash definition, with the high-bits to the left.

If C<cust_hatch> is NULL then one of the standard hatches is used.

(C<dx>, C<dy>) are an offset into the hatch which can be used to hatch
adjoining areas out of alignment, or to align the origin of a hatch
with the the side of a filled area.

=cut
*/
i_fill_t *
i_new_fill_hatch(const i_color *fg, const i_color *bg, int combine, int hatch, 
            const unsigned char *cust_hatch, i_img_dim dx, i_img_dim dy) {
  return i_new_hatch_low(fg, bg, NULL, NULL, combine, hatch, cust_hatch, 
                         dx, dy);
}

/*
=item i_new_fill_hatchf(C<fg>, C<bg>, C<combine>, C<hatch>, C<cust_hatch>, C<dx>, C<dy>)

=category Fills
=synopsis i_fill_t *fill = i_new_fill_hatchf(&fg_fcolor, &bg_fcolor, combine, hatch, custom_hatch, dx, dy);

Creates a new hatched fill with the C<fg> color used for the 1 bits in
the hatch and C<bg> for the 0 bits.  If C<combine> is non-zero alpha
values will be combined.

If C<cust_hatch> is non-NULL it should be a pointer to 8 bytes of the
hash definition, with the high-bits to the left.

If C<cust_hatch> is NULL then one of the standard hatches is used.

(C<dx>, C<dy>) are an offset into the hatch which can be used to hatch
adjoining areas out of alignment, or to align the origin of a hatch
with the the side of a filled area.

=cut
*/
i_fill_t *
i_new_fill_hatchf(const i_fcolor *fg, const i_fcolor *bg, int combine, int hatch, 
		  const unsigned char *cust_hatch, i_img_dim dx, i_img_dim dy) {
  return i_new_hatch_low(NULL, NULL, fg, bg, combine, hatch, cust_hatch, 
                         dx, dy);
}

static void fill_image(i_fill_t *fill, i_img_dim x, i_img_dim y,
		       i_img_dim width, int channels, i_color *data);
static void fill_imagef(i_fill_t *fill, i_img_dim x, i_img_dim y,
			i_img_dim width, int channels, i_fcolor *data);
struct i_fill_image_t {
  i_fill_t base;
  i_img *src;
  i_img_dim xoff, yoff;
  int has_matrix;
  double matrix[9];
};

static struct i_fill_image_t
image_fill_proto =
  {
    {
      fill_image,
      fill_imagef,
      NULL
    }
  };

/*
=item i_new_fill_image(C<im>, C<matrix>, C<xoff>, C<yoff>, C<combine>)

=category Fills
=synopsis i_fill_t *fill = i_new_fill_image(src_img, matrix, x_offset, y_offset, combine);

Create an image based fill.

matrix is an array of 9 doubles representing a transformation matrix.

C<xoff> and C<yoff> are the offset into the image to start filling from.

=cut
*/
i_fill_t *
i_new_fill_image(i_img *im, const double *matrix, i_img_dim xoff, i_img_dim yoff, int combine) {
  struct i_fill_image_t *fill = mymalloc(sizeof(*fill)); /* checked 14jul05 tonyc */

  *fill = image_fill_proto;

  if (combine) {
    i_get_combine(combine, &fill->base.combine, &fill->base.combinef);
  }
  else {
    fill->base.combine = NULL;
    fill->base.combinef = NULL;
  }
  fill->src = im;
  if (xoff < 0)
    xoff += im->xsize;
  fill->xoff = xoff;
  if (yoff < 0)
    yoff += im->ysize;
  fill->yoff = yoff;
  if (matrix) {
    fill->has_matrix = 1;
    memcpy(fill->matrix, matrix, sizeof(fill->matrix));
  }
  else
    fill->has_matrix = 0;

  return &fill->base;
}

static void fill_opacity(i_fill_t *fill, i_img_dim x, i_img_dim y,
			 i_img_dim width, int channels, i_color *data);
static void fill_opacityf(i_fill_t *fill, i_img_dim x, i_img_dim y,
			  i_img_dim width, int channels, i_fcolor *data);

struct i_fill_opacity_t {
  i_fill_t base;
  i_fill_t *other_fill;
  double alpha_mult;
};

static struct i_fill_opacity_t
opacity_fill_proto =
  {
    {
      fill_opacity,
      fill_opacityf,
      NULL
    }
  };

i_fill_t *
i_new_fill_opacity(i_fill_t *base_fill, double alpha_mult) {
  struct i_fill_opacity_t *fill = mymalloc(sizeof(*fill));
  *fill = opacity_fill_proto;

  fill->base.combine = base_fill->combine;
  fill->base.combinef = base_fill->combinef;

  fill->other_fill = base_fill;
  fill->alpha_mult = alpha_mult;

  if (!base_fill->f_fill_with_color) {
    /* base fill only does floating, so we only do that too */
    fill->base.f_fill_with_color = NULL;
  }

  return &fill->base;
}

#define T_SOLID_FILL(fill) ((i_fill_solid_t *)(fill))

/*
=back

=head1 INTERNAL FUNCTIONS

=over

=item fill_solid(fill, x, y, width, channels, data)

The 8-bit sample fill function for non-combining solid fills.

=cut
*/
static void
fill_solid(i_fill_t *fill, i_img_dim x, i_img_dim y, i_img_dim width,
	   int channels, i_color *data) {
  i_color c = T_SOLID_FILL(fill)->c;
  i_adapt_colors(channels > 2 ? 4 : 2, 4, &c, 1);
  while (width-- > 0) {
    *data++ = c;
  }
}

/*
=item fill_solid(fill, x, y, width, channels, data)

The floating sample fill function for non-combining solid fills.

=cut
*/
static void
fill_solidf(i_fill_t *fill, i_img_dim x, i_img_dim y, i_img_dim width,
	    int channels, i_fcolor *data) {
  i_fcolor c = T_SOLID_FILL(fill)->fc;
  i_adapt_fcolors(channels > 2 ? 4 : 2, 4, &c, 1);
  while (width-- > 0) {
    *data++ = c;
  }
}

static i_fill_hatch_t
hatch_fill_proto =
  {
    {
      fill_hatch,
      fill_hatchf,
      NULL
    }
  };

/*
=item i_new_hatch_low(fg, bg, ffg, fbg, combine, hatch, cust_hatch, dx, dy)

Implements creation of hatch fill objects.

=cut
*/
static
i_fill_t *
i_new_hatch_low(const i_color *fg, const i_color *bg, 
		const i_fcolor *ffg, const i_fcolor *fbg, 
                int combine, int hatch, const unsigned char *cust_hatch,
                i_img_dim dx, i_img_dim dy) {
  i_fill_hatch_t *fill = mymalloc(sizeof(i_fill_hatch_t)); /* checked 14jul05 tonyc */

  *fill = hatch_fill_proto;
  /* Some Sun C didn't like the condition expressions that were here.
     See https://rt.cpan.org/Ticket/Display.html?id=21944
   */
  if (fg)
    fill->fg = *fg;
  else
    fill->fg = fcolor_to_color(ffg);
  if (bg)
    fill->bg = *bg;
  else
    fill->bg = fcolor_to_color(fbg);
  if (ffg) 
    fill->ffg = *ffg;
  else
    fill->ffg = color_to_fcolor(fg);
  if (fbg)
    fill->fbg = *fbg;
  else
    fill->fbg = color_to_fcolor(bg);
  if (combine) {
    i_get_combine(combine, &fill->base.combine, &fill->base.combinef);
  }
  else {
    fill->base.combine = NULL;
    fill->base.combinef = NULL;
  }
  if (cust_hatch) {
    memcpy(fill->hatch, cust_hatch, 8);
  }
  else {
    if (hatch > sizeof(builtin_hatches)/sizeof(*builtin_hatches)) 
      hatch = 0;
    memcpy(fill->hatch, builtin_hatches[hatch], 8);
  }
  fill->dx = dx & 7;
  fill->dy = dy & 7;

  return &fill->base;
}

/*
=item fill_hatch(fill, x, y, width, channels, data)

The 8-bit sample fill function for hatched fills.

=cut
*/
static void 
fill_hatch(i_fill_t *fill, i_img_dim x, i_img_dim y, i_img_dim width,
	   int channels, i_color *data) {
  i_fill_hatch_t *f = (i_fill_hatch_t *)fill;
  int byte = f->hatch[(y + f->dy) & 7];
  int xpos = (x + f->dx) & 7;
  int mask = 128 >> xpos;
  i_color fg = f->fg;
  i_color bg = f->bg;

  if (channels < 3) {
    i_adapt_colors(2, 4, &fg, 1);
    i_adapt_colors(2, 4, &bg, 1);
  }

  while (width-- > 0) {
    if (byte & mask)
      *data++ = fg;
    else
      *data++ = bg;
    
    if ((mask >>= 1) == 0)
      mask = 128;
  }
}

/*
=item fill_hatchf(fill, x, y, width, channels, data)

The floating sample fill function for hatched fills.

=cut
*/
static void
fill_hatchf(i_fill_t *fill, i_img_dim x, i_img_dim y, i_img_dim width,
	    int channels, i_fcolor *data) {
  i_fill_hatch_t *f = (i_fill_hatch_t *)fill;
  int byte = f->hatch[(y + f->dy) & 7];
  int xpos = (x + f->dx) & 7;
  int mask = 128 >> xpos;
  i_fcolor fg = f->ffg;
  i_fcolor bg = f->fbg;

  if (channels < 3) {
    i_adapt_fcolors(2, 4, &fg, 1);
    i_adapt_fcolors(2, 4, &bg, 1);
  }
  
  while (width-- > 0) {
    if (byte & mask)
      *data++ = fg;
    else
      *data++ = bg;
    
    if ((mask >>= 1) == 0)
      mask = 128;
  }
}

/* hopefully this will be inlined  (it is with -O3 with gcc 2.95.4) */
/* linear interpolation */
static i_color interp_i_color(i_color before, i_color after, double pos,
                              int channels) {
  i_color out;
  int ch;

  pos -= floor(pos);
  for (ch = 0; ch < channels; ++ch)
    out.channel[ch] = (1-pos) * before.channel[ch] + pos * after.channel[ch];
  if (channels > 3 && out.channel[3])
    for (ch = 0; ch < channels; ++ch)
      if (ch != 3) {
        int temp = out.channel[ch] * 255 / out.channel[3];
        if (temp > 255)
          temp = 255;
        out.channel[ch] = temp;
      }

  return out;
}

/* hopefully this will be inlined  (it is with -O3 with gcc 2.95.4) */
/* linear interpolation */
static i_fcolor interp_i_fcolor(i_fcolor before, i_fcolor after, double pos,
                                int channels) {
  i_fcolor out;
  int ch;

  pos -= floor(pos);
  for (ch = 0; ch < channels; ++ch)
    out.channel[ch] = (1-pos) * before.channel[ch] + pos * after.channel[ch];
  if (out.channel[3])
    for (ch = 0; ch < channels; ++ch)
      if (ch != 3) {
        int temp = out.channel[ch] / out.channel[3];
        if (temp > 1.0)
          temp = 1.0;
        out.channel[ch] = temp;
      }

  return out;
}

/*
=item fill_image(fill, x, y, width, channels, data, work)

=cut
*/
static void
fill_image(i_fill_t *fill, i_img_dim x, i_img_dim y, i_img_dim width,
	   int channels, i_color *data) {
  struct i_fill_image_t *f = (struct i_fill_image_t *)fill;
  i_img_dim i = 0;
  i_color *out = data;
  int want_channels = channels > 2 ? 4 : 2;
  
  if (f->has_matrix) {
    /* the hard way */
    while (i < width) {
      double rx = f->matrix[0] * (x+i) + f->matrix[1] * y + f->matrix[2];
      double ry = f->matrix[3] * (x+i) + f->matrix[4] * y + f->matrix[5];
      double ix = floor(rx / f->src->xsize);
      double iy = floor(ry / f->src->ysize);
      i_color c[2][2];
      i_color c2[2];
      i_img_dim dy;

      if (f->xoff) {
        rx += iy * f->xoff;
        ix = floor(rx / f->src->xsize);
      }
      else if (f->yoff) {
        ry += ix * f->yoff;
        iy = floor(ry / f->src->ysize);
      }
      rx -= ix * f->src->xsize;
      ry -= iy * f->src->ysize;

      for (dy = 0; dy < 2; ++dy) {
        if ((i_img_dim)rx == f->src->xsize-1) {
          i_gpix(f->src, f->src->xsize-1, ((i_img_dim)ry+dy) % f->src->ysize, &c[dy][0]);
          i_gpix(f->src, 0, ((i_img_dim)ry+dy) % f->src->xsize, &c[dy][1]);
        }
        else {
          i_glin(f->src, (i_img_dim)rx, (i_img_dim)rx+2, ((i_img_dim)ry+dy) % f->src->ysize, 
                 c[dy]);
        }
        c2[dy] = interp_i_color(c[dy][0], c[dy][1], rx, f->src->channels);
      }
      *out++ = interp_i_color(c2[0], c2[1], ry, f->src->channels);
      ++i;
    }
  }
  else {
    /* the easy way */
    /* this should be possible to optimize to use i_glin() */
    while (i < width) {
      i_img_dim rx = x+i;
      i_img_dim ry = y;
      i_img_dim ix = rx / f->src->xsize;
      i_img_dim iy = ry / f->src->ysize;

      if (f->xoff) {
        rx += iy * f->xoff;
        ix = rx / f->src->xsize;
      }
      else if (f->yoff) {
        ry += ix * f->yoff;
        iy = ry / f->src->ysize;
      }
      rx -= ix * f->src->xsize;
      ry -= iy * f->src->ysize;
      i_gpix(f->src, rx, ry, out);
      ++out;
      ++i;
    }
  }
  if (f->src->channels != want_channels)
    i_adapt_colors(want_channels, f->src->channels, data, width);
}

/*
=item fill_imagef(fill, x, y, width, channels, data, work)

=cut
*/
static void
fill_imagef(i_fill_t *fill, i_img_dim x, i_img_dim y, i_img_dim width,
	    int channels, i_fcolor *data) {
  struct i_fill_image_t *f = (struct i_fill_image_t *)fill;
  i_img_dim i = 0;
  int want_channels = channels > 2 ? 4 : 2;
  
  if (f->has_matrix) {
    i_fcolor *work_data = data;
    /* the hard way */
    while (i < width) {
      double rx = f->matrix[0] * (x+i) + f->matrix[1] * y + f->matrix[2];
      double ry = f->matrix[3] * (x+i) + f->matrix[4] * y + f->matrix[5];
      double ix = floor(rx / f->src->xsize);
      double iy = floor(ry / f->src->ysize);
      i_fcolor c[2][2];
      i_fcolor c2[2];
      i_img_dim dy;

      if (f->xoff) {
        rx += iy * f->xoff;
        ix = floor(rx / f->src->xsize);
      }
      else if (f->yoff) {
        ry += ix * f->yoff;
        iy = floor(ry / f->src->ysize);
      }
      rx -= ix * f->src->xsize;
      ry -= iy * f->src->ysize;

      for (dy = 0; dy < 2; ++dy) {
        if ((i_img_dim)rx == f->src->xsize-1) {
          i_gpixf(f->src, f->src->xsize-1, ((i_img_dim)ry+dy) % f->src->ysize, &c[dy][0]);
          i_gpixf(f->src, 0, ((i_img_dim)ry+dy) % f->src->xsize, &c[dy][1]);
        }
        else {
          i_glinf(f->src, (i_img_dim)rx, (i_img_dim)rx+2, ((i_img_dim)ry+dy) % f->src->ysize, 
                 c[dy]);
        }
        c2[dy] = interp_i_fcolor(c[dy][0], c[dy][1], rx, f->src->channels);
      }
      *work_data++ = interp_i_fcolor(c2[0], c2[1], ry, f->src->channels);
      ++i;
    }
  }
  else {
    i_fcolor *work_data = data;
    /* the easy way */
    /* this should be possible to optimize to use i_glin() */
    while (i < width) {
      i_img_dim rx = x+i;
      i_img_dim ry = y;
      i_img_dim ix = rx / f->src->xsize;
      i_img_dim iy = ry / f->src->ysize;

      if (f->xoff) {
        rx += iy * f->xoff;
        ix = rx / f->src->xsize;
      }
      else if (f->yoff) {
        ry += ix * f->yoff;
        iy = ry / f->src->xsize;
      }
      rx -= ix * f->src->xsize;
      ry -= iy * f->src->ysize;
      i_gpixf(f->src, rx, ry, work_data);
      ++work_data;
      ++i;
    }
  }
  if (f->src->channels != want_channels)
    i_adapt_fcolors(want_channels, f->src->channels, data, width);
}

static void 
fill_opacity(i_fill_t *fill, i_img_dim x, i_img_dim y, i_img_dim width,
	     int channels, i_color *data) {
  struct i_fill_opacity_t *f = (struct i_fill_opacity_t *)fill;
  int alpha_chan = channels > 2 ? 3 : 1;
  i_color *datap = data;
  
  (f->other_fill->f_fill_with_color)(f->other_fill, x, y, width, channels, data);
  while (width--) {
    double new_alpha = datap->channel[alpha_chan] * f->alpha_mult;
    if (new_alpha < 0) 
      datap->channel[alpha_chan] = 0;
    else if (new_alpha > 255)
      datap->channel[alpha_chan] = 255;
    else datap->channel[alpha_chan] = (int)(new_alpha + 0.5);

    ++datap;
  }
}
static void 
fill_opacityf(i_fill_t *fill, i_img_dim x, i_img_dim y, i_img_dim width,
	      int channels, i_fcolor *data) {
  struct i_fill_opacity_t *f = (struct i_fill_opacity_t *)fill;
  int alpha_chan = channels > 2 ? 3 : 1;
  i_fcolor *datap = data;
  
  (f->other_fill->f_fill_with_fcolor)(f->other_fill, x, y, width, channels, data);
  
  while (width--) {
    double new_alpha = datap->channel[alpha_chan] * f->alpha_mult;
    if (new_alpha < 0) 
      datap->channel[alpha_chan] = 0;
    else if (new_alpha > 1.0)
      datap->channel[alpha_chan] = 1.0;
    else datap->channel[alpha_chan] = new_alpha;

    ++datap;
  }
}

/*
=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=head1 SEE ALSO

Imager(3)

=cut
*/
