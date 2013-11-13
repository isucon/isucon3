#define IMAGER_NO_CONTEXT

#include "imager.h"
#include "imageri.h"

static int i_ppix_d(i_img *im, i_img_dim x, i_img_dim y, const i_color *val);
static int i_gpix_d(i_img *im, i_img_dim x, i_img_dim y, i_color *val);
static i_img_dim i_glin_d(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_color *vals);
static i_img_dim i_plin_d(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, const i_color *vals);
static int i_ppixf_d(i_img *im, i_img_dim x, i_img_dim y, const i_fcolor *val);
static int i_gpixf_d(i_img *im, i_img_dim x, i_img_dim y, i_fcolor *val);
static i_img_dim i_glinf_d(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_fcolor *vals);
static i_img_dim i_plinf_d(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, const i_fcolor *vals);
static i_img_dim i_gsamp_d(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_sample_t *samps, const int *chans, int chan_count);
static i_img_dim i_gsampf_d(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_fsample_t *samps, const int *chans, int chan_count);
static i_img_dim i_psamp_d(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, const i_sample_t *samps, const int *chans, int chan_count);
static i_img_dim i_psampf_d(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, const i_fsample_t *samps, const int *chans, int chan_count);

/*
=item IIM_base_8bit_direct (static)

A static i_img object used to initialize direct 8-bit per sample images.

=cut
*/
static i_img IIM_base_8bit_direct =
{
  0, /* channels set */
  0, 0, 0, /* xsize, ysize, bytes */
  ~0U, /* ch_mask */
  i_8_bits, /* bits */
  i_direct_type, /* type */
  0, /* virtual */
  NULL, /* idata */
  { 0, 0, NULL }, /* tags */
  NULL, /* ext_data */

  i_ppix_d, /* i_f_ppix */
  i_ppixf_d, /* i_f_ppixf */
  i_plin_d, /* i_f_plin */
  i_plinf_d, /* i_f_plinf */
  i_gpix_d, /* i_f_gpix */
  i_gpixf_d, /* i_f_gpixf */
  i_glin_d, /* i_f_glin */
  i_glinf_d, /* i_f_glinf */
  i_gsamp_d, /* i_f_gsamp */
  i_gsampf_d, /* i_f_gsampf */

  NULL, /* i_f_gpal */
  NULL, /* i_f_ppal */
  NULL, /* i_f_addcolors */
  NULL, /* i_f_getcolors */
  NULL, /* i_f_colorcount */
  NULL, /* i_f_maxcolors */
  NULL, /* i_f_findcolor */
  NULL, /* i_f_setcolors */

  NULL, /* i_f_destroy */

  i_gsamp_bits_fb,
  NULL, /* i_f_psamp_bits */

  i_psamp_d,
  i_psampf_d
};

/*static void set_8bit_direct(i_img *im) {
  im->i_f_ppix = i_ppix_d;
  im->i_f_ppixf = i_ppixf_d;
  im->i_f_plin = i_plin_d;
  im->i_f_plinf = i_plinf_d;
  im->i_f_gpix = i_gpix_d;
  im->i_f_gpixf = i_gpixf_d;
  im->i_f_glin = i_glin_d;
  im->i_f_glinf = i_glinf_d;
  im->i_f_gpal = NULL;
  im->i_f_ppal = NULL;
  im->i_f_addcolor = NULL;
  im->i_f_getcolor = NULL;
  im->i_f_colorcount = NULL;
  im->i_f_findcolor = NULL;
  }*/

/*
=item im_img_8_new(ctx, x, y, ch)
X<im_img_8_new API>X<i_img_8_new API>
=category Image creation/destruction
=synopsis i_img *img = im_img_8_new(aIMCTX, width, height, channels);
=synopsis i_img *img = i_img_8_new(width, height, channels);

Creates a new image object I<x> pixels wide, and I<y> pixels high with
I<ch> channels.

=cut
*/

i_img *
im_img_8_new(pIMCTX, i_img_dim x,i_img_dim y,int ch) {
  i_img *im;

  im_log((aIMCTX, 1,"im_img_8_new(x %" i_DF ", y %" i_DF ", ch %d)\n",
	  i_DFc(x), i_DFc(y), ch));

  im = im_img_empty_ch(aIMCTX, NULL,x,y,ch);
  
  im_log((aIMCTX, 1,"(%p) <- IIM_new\n",im));
  return im;
}

/* 
=item i_img_empty(im, x, y)

Re-new image reference (assumes 3 channels)

   im - Image pointer
   x - xsize of destination image
   y - ysize of destination image

**FIXME** what happens if a live image is passed in here?

Should this just call i_img_empty_ch()?

=cut
*/

i_img *
im_img_empty(pIMCTX, i_img *im,i_img_dim x,i_img_dim y) {
  im_log((aIMCTX, 1,"i_img_empty(*im %p, x %" i_DF ", y %" i_DF ")\n",
	  im, i_DFc(x), i_DFc(y)));
  return im_img_empty_ch(aIMCTX, im, x, y, 3);
}

/* 
=item i_img_empty_ch(im, x, y, ch)

Re-new image reference 

   im - Image pointer
   x  - xsize of destination image
   y  - ysize of destination image
   ch - number of channels

=cut
*/

i_img *
im_img_empty_ch(pIMCTX, i_img *im,i_img_dim x,i_img_dim y,int ch) {
  size_t bytes;

  im_log((aIMCTX, 1,"i_img_empty_ch(*im %p, x %" i_DF ", y %" i_DF ", ch %d)\n",
	  im, i_DFc(x), i_DFc(y), ch));

  if (x < 1 || y < 1) {
    im_push_error(aIMCTX, 0, "Image sizes must be positive");
    return NULL;
  }
  if (ch < 1 || ch > MAXCHANNELS) {
    im_push_errorf(aIMCTX, 0, "channels must be between 1 and %d", MAXCHANNELS);
    return NULL;
  }
  /* check this multiplication doesn't overflow */
  bytes = x*y*ch;
  if (bytes / y / ch != x) {
    im_push_errorf(aIMCTX, 0, "integer overflow calculating image allocation");
    return NULL;
  }

  if (im == NULL)
    im = im_img_alloc(aIMCTX);

  memcpy(im, &IIM_base_8bit_direct, sizeof(i_img));
  i_tags_new(&im->tags);
  im->xsize    = x;
  im->ysize    = y;
  im->channels = ch;
  im->ch_mask  = MAXINT;
  im->bytes=bytes;
  if ( (im->idata=mymalloc(im->bytes)) == NULL) 
    im_fatal(aIMCTX, 2,"malloc() error\n"); 
  memset(im->idata,0,(size_t)im->bytes);
  
  im->ext_data = NULL;

  im_img_init(aIMCTX, im);
  
  im_log((aIMCTX, 1,"(%p) <- i_img_empty_ch\n",im));
  return im;
}

/*
=head2 8-bit per sample image internal functions

These are the functions installed in an 8-bit per sample image.

=over

=item i_ppix_d(im, x, y, col)

Internal function.

This is the function kept in the i_f_ppix member of an i_img object.
It does a normal store of a pixel into the image with range checking.

Returns 0 if the pixel could be set, -1 otherwise.

=cut
*/
static
int
i_ppix_d(i_img *im, i_img_dim x, i_img_dim y, const i_color *val) {
  int ch;
  
  if ( x>-1 && x<im->xsize && y>-1 && y<im->ysize ) {
    for(ch=0;ch<im->channels;ch++)
      if (im->ch_mask&(1<<ch)) 
	im->idata[(x+y*im->xsize)*im->channels+ch]=val->channel[ch];
    return 0;
  }
  return -1; /* error was clipped */
}

/*
=item i_gpix_d(im, x, y, &col)

Internal function.

This is the function kept in the i_f_gpix member of an i_img object.
It does normal retrieval of a pixel from the image with range checking.

Returns 0 if the pixel could be set, -1 otherwise.

=cut
*/
static
int 
i_gpix_d(i_img *im, i_img_dim x, i_img_dim y, i_color *val) {
  int ch;
  if (x>-1 && x<im->xsize && y>-1 && y<im->ysize) {
    for(ch=0;ch<im->channels;ch++) 
      val->channel[ch]=im->idata[(x+y*im->xsize)*im->channels+ch];
    return 0;
  }
  for(ch=0;ch<im->channels;ch++) val->channel[ch] = 0;
  return -1; /* error was cliped */
}

/*
=item i_glin_d(im, l, r, y, vals)

Reads a line of data from the image, storing the pixels at vals.

The line runs from (l,y) inclusive to (r,y) non-inclusive

vals should point at space for (r-l) pixels.

l should never be less than zero (to avoid confusion about where to
put the pixels in vals).

Returns the number of pixels copied (eg. if r, l or y is out of range)

=cut
*/
static
i_img_dim
i_glin_d(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_color *vals) {
  int ch;
  i_img_dim count, i;
  unsigned char *data;
  if (y >=0 && y < im->ysize && l < im->xsize && l >= 0) {
    if (r > im->xsize)
      r = im->xsize;
    data = im->idata + (l+y*im->xsize) * im->channels;
    count = r - l;
    for (i = 0; i < count; ++i) {
      for (ch = 0; ch < im->channels; ++ch)
	vals[i].channel[ch] = *data++;
    }
    return count;
  }
  else {
    return 0;
  }
}

/*
=item i_plin_d(im, l, r, y, vals)

Writes a line of data into the image, using the pixels at vals.

The line runs from (l,y) inclusive to (r,y) non-inclusive

vals should point at (r-l) pixels.

l should never be less than zero (to avoid confusion about where to
get the pixels in vals).

Returns the number of pixels copied (eg. if r, l or y is out of range)

=cut
*/
static
i_img_dim
i_plin_d(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, const i_color *vals) {
  int ch;
  i_img_dim count, i;
  unsigned char *data;
  if (y >=0 && y < im->ysize && l < im->xsize && l >= 0) {
    if (r > im->xsize)
      r = im->xsize;
    data = im->idata + (l+y*im->xsize) * im->channels;
    count = r - l;
    for (i = 0; i < count; ++i) {
      for (ch = 0; ch < im->channels; ++ch) {
	if (im->ch_mask & (1 << ch)) 
	  *data = vals[i].channel[ch];
	++data;
      }
    }
    return count;
  }
  else {
    return 0;
  }
}

/*
=item i_ppixf_d(im, x, y, val)

=cut
*/
static
int
i_ppixf_d(i_img *im, i_img_dim x, i_img_dim y, const i_fcolor *val) {
  int ch;
  
  if ( x>-1 && x<im->xsize && y>-1 && y<im->ysize ) {
    for(ch=0;ch<im->channels;ch++)
      if (im->ch_mask&(1<<ch)) {
	im->idata[(x+y*im->xsize)*im->channels+ch] = 
          SampleFTo8(val->channel[ch]);
      }
    return 0;
  }
  return -1; /* error was clipped */
}

/*
=item i_gpixf_d(im, x, y, val)

=cut
*/
static
int
i_gpixf_d(i_img *im, i_img_dim x, i_img_dim y, i_fcolor *val) {
  int ch;
  if (x>-1 && x<im->xsize && y>-1 && y<im->ysize) {
    for(ch=0;ch<im->channels;ch++) {
      val->channel[ch] = 
        Sample8ToF(im->idata[(x+y*im->xsize)*im->channels+ch]);
    }
    return 0;
  }
  return -1; /* error was cliped */
}

/*
=item i_glinf_d(im, l, r, y, vals)

Reads a line of data from the image, storing the pixels at vals.

The line runs from (l,y) inclusive to (r,y) non-inclusive

vals should point at space for (r-l) pixels.

l should never be less than zero (to avoid confusion about where to
put the pixels in vals).

Returns the number of pixels copied (eg. if r, l or y is out of range)

=cut
*/
static
i_img_dim
i_glinf_d(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_fcolor *vals) {
  int ch;
  i_img_dim count, i;
  unsigned char *data;
  if (y >=0 && y < im->ysize && l < im->xsize && l >= 0) {
    if (r > im->xsize)
      r = im->xsize;
    data = im->idata + (l+y*im->xsize) * im->channels;
    count = r - l;
    for (i = 0; i < count; ++i) {
      for (ch = 0; ch < im->channels; ++ch)
	vals[i].channel[ch] = Sample8ToF(*data++);
    }
    return count;
  }
  else {
    return 0;
  }
}

/*
=item i_plinf_d(im, l, r, y, vals)

Writes a line of data into the image, using the pixels at vals.

The line runs from (l,y) inclusive to (r,y) non-inclusive

vals should point at (r-l) pixels.

l should never be less than zero (to avoid confusion about where to
get the pixels in vals).

Returns the number of pixels copied (eg. if r, l or y is out of range)

=cut
*/
static
i_img_dim
i_plinf_d(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, const i_fcolor *vals) {
  int ch;
  i_img_dim count, i;
  unsigned char *data;
  if (y >=0 && y < im->ysize && l < im->xsize && l >= 0) {
    if (r > im->xsize)
      r = im->xsize;
    data = im->idata + (l+y*im->xsize) * im->channels;
    count = r - l;
    for (i = 0; i < count; ++i) {
      for (ch = 0; ch < im->channels; ++ch) {
	if (im->ch_mask & (1 << ch)) 
	  *data = SampleFTo8(vals[i].channel[ch]);
	++data;
      }
    }
    return count;
  }
  else {
    return 0;
  }
}

/*
=item i_gsamp_d(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_sample_t *samps, int *chans, int chan_count)

Reads sample values from im for the horizontal line (l, y) to (r-1,y)
for the channels specified by chans, an array of int with chan_count
elements.

Returns the number of samples read (which should be (r-l) * bits_set(chan_mask)

=cut
*/
static
i_img_dim
i_gsamp_d(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_sample_t *samps, 
              const int *chans, int chan_count) {
  int ch;
  i_img_dim count, i, w;
  unsigned char *data;

  if (y >=0 && y < im->ysize && l < im->xsize && l >= 0) {
    if (r > im->xsize)
      r = im->xsize;
    data = im->idata + (l+y*im->xsize) * im->channels;
    w = r - l;
    count = 0;

    if (chans) {
      /* make sure we have good channel numbers */
      for (ch = 0; ch < chan_count; ++ch) {
        if (chans[ch] < 0 || chans[ch] >= im->channels) {
	  dIMCTXim(im);
          im_push_errorf(aIMCTX, 0, "No channel %d in this image", chans[ch]);
          return 0;
        }
      }
      for (i = 0; i < w; ++i) {
        for (ch = 0; ch < chan_count; ++ch) {
          *samps++ = data[chans[ch]];
          ++count;
        }
        data += im->channels;
      }
    }
    else {
      if (chan_count <= 0 || chan_count > im->channels) {
	dIMCTXim(im);
	im_push_errorf(aIMCTX, 0, "chan_count %d out of range, must be >0, <= channels", 
		      chan_count);
	return 0;
      }
      for (i = 0; i < w; ++i) {
        for (ch = 0; ch < chan_count; ++ch) {
          *samps++ = data[ch];
          ++count;
        }
        data += im->channels;
      }
    }

    return count;
  }
  else {
    return 0;
  }
}

/*
=item i_gsampf_d(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_fsample_t *samps, int *chans, int chan_count)

Reads sample values from im for the horizontal line (l, y) to (r-1,y)
for the channels specified by chan_mask, where bit 0 is the first
channel.

Returns the number of samples read (which should be (r-l) * bits_set(chan_mask)

=cut
*/
static
i_img_dim
i_gsampf_d(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_fsample_t *samps, 
           const int *chans, int chan_count) {
  int ch;
  i_img_dim count, i, w;
  unsigned char *data;
  for (ch = 0; ch < chan_count; ++ch) {
    if (chans[ch] < 0 || chans[ch] >= im->channels) {
      dIMCTXim(im);
      im_push_errorf(aIMCTX, 0, "No channel %d in this image", chans[ch]);
    }
  }
  if (y >=0 && y < im->ysize && l < im->xsize && l >= 0) {
    if (r > im->xsize)
      r = im->xsize;
    data = im->idata + (l+y*im->xsize) * im->channels;
    w = r - l;
    count = 0;

    if (chans) {
      /* make sure we have good channel numbers */
      for (ch = 0; ch < chan_count; ++ch) {
        if (chans[ch] < 0 || chans[ch] >= im->channels) {
	  dIMCTXim(im);
          im_push_errorf(aIMCTX, 0, "No channel %d in this image", chans[ch]);
          return 0;
        }
      }
      for (i = 0; i < w; ++i) {
        for (ch = 0; ch < chan_count; ++ch) {
          *samps++ = Sample8ToF(data[chans[ch]]);
          ++count;
        }
        data += im->channels;
      }
    }
    else {
      if (chan_count <= 0 || chan_count > im->channels) {
	dIMCTXim(im);
	im_push_errorf(aIMCTX, 0, "chan_count %d out of range, must be >0, <= channels", 
		      chan_count);
	return 0;
      }
      for (i = 0; i < w; ++i) {
        for (ch = 0; ch < chan_count; ++ch) {
          *samps++ = Sample8ToF(data[ch]);
          ++count;
        }
        data += im->channels;
      }
    }
    return count;
  }
  else {
    return 0;
  }
}

/*
=item i_psamp_d(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_sample_t *samps, int *chans, int chan_count)

Writes sample values to im for the horizontal line (l, y) to (r-1,y)
for the channels specified by chans, an array of int with chan_count
elements.

Returns the number of samples written (which should be (r-l) *
bits_set(chan_mask)

=cut
*/

static
i_img_dim
i_psamp_d(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, 
	  const i_sample_t *samps, const int *chans, int chan_count) {
  int ch;
  i_img_dim count, i, w;
  unsigned char *data;

  if (y >=0 && y < im->ysize && l < im->xsize && l >= 0) {
    if (r > im->xsize)
      r = im->xsize;
    data = im->idata + (l+y*im->xsize) * im->channels;
    w = r - l;
    count = 0;

    if (chans) {
      /* make sure we have good channel numbers */
      /* and test if all channels specified are in the mask */
      int all_in_mask = 1;
      for (ch = 0; ch < chan_count; ++ch) {
        if (chans[ch] < 0 || chans[ch] >= im->channels) {
	  dIMCTXim(im);
          im_push_errorf(aIMCTX, 0, "No channel %d in this image", chans[ch]);
          return -1;
        }
	if (!((1 << chans[ch]) & im->ch_mask))
	  all_in_mask = 0;
      }
      if (all_in_mask) {
	for (i = 0; i < w; ++i) {
	  for (ch = 0; ch < chan_count; ++ch) {
	    data[chans[ch]] = *samps++;
	    ++count;
	  }
	  data += im->channels;
	}
      }
      else {
	for (i = 0; i < w; ++i) {
	  for (ch = 0; ch < chan_count; ++ch) {
	    if (im->ch_mask & (1 << (chans[ch])))
	      data[chans[ch]] = *samps;
	    ++samps;
	    ++count;
	  }
	  data += im->channels;
	}
      }
    }
    else {
      if (chan_count <= 0 || chan_count > im->channels) {
	dIMCTXim(im);
	im_push_errorf(aIMCTX, 0, "chan_count %d out of range, must be >0, <= channels", 
		      chan_count);
	return -1;
      }
      for (i = 0; i < w; ++i) {
	unsigned mask = 1;
        for (ch = 0; ch < chan_count; ++ch) {
	  if (im->ch_mask & mask)
	    data[ch] = *samps;
	  ++samps;
          ++count;
	  mask <<= 1;
        }
        data += im->channels;
      }
    }

    return count;
  }
  else {
    dIMCTXim(im);
    i_push_error(0, "Image position outside of image");
    return -1;
  }
}

/*
=item i_psampf_d(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, const i_fsample_t *samps, int *chans, int chan_count)

Writes sample values to im for the horizontal line (l, y) to (r-1,y)
for the channels specified by chans, an array of int with chan_count
elements.

Returns the number of samples written (which should be (r-l) *
bits_set(chan_mask)

=cut
*/

static
i_img_dim
i_psampf_d(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, 
	  const i_fsample_t *samps, const int *chans, int chan_count) {
  int ch;
  i_img_dim count, i, w;
  unsigned char *data;

  if (y >=0 && y < im->ysize && l < im->xsize && l >= 0) {
    if (r > im->xsize)
      r = im->xsize;
    data = im->idata + (l+y*im->xsize) * im->channels;
    w = r - l;
    count = 0;

    if (chans) {
      /* make sure we have good channel numbers */
      /* and test if all channels specified are in the mask */
      int all_in_mask = 1;
      for (ch = 0; ch < chan_count; ++ch) {
        if (chans[ch] < 0 || chans[ch] >= im->channels) {
	  dIMCTXim(im);
          im_push_errorf(aIMCTX, 0, "No channel %d in this image", chans[ch]);
          return -1;
        }
	if (!((1 << chans[ch]) & im->ch_mask))
	  all_in_mask = 0;
      }
      if (all_in_mask) {
	for (i = 0; i < w; ++i) {
	  for (ch = 0; ch < chan_count; ++ch) {
	    data[chans[ch]] = SampleFTo8(*samps);
	    ++samps;
	    ++count;
	  }
	  data += im->channels;
	}
      }
      else {
	for (i = 0; i < w; ++i) {
	  for (ch = 0; ch < chan_count; ++ch) {
	    if (im->ch_mask & (1 << (chans[ch])))
	      data[chans[ch]] = SampleFTo8(*samps);
	    ++samps;
	    ++count;
	  }
	  data += im->channels;
	}
      }
    }
    else {
      if (chan_count <= 0 || chan_count > im->channels) {
	dIMCTXim(im);
	im_push_errorf(aIMCTX, 0, "chan_count %d out of range, must be >0, <= channels", 
		      chan_count);
	return -1;
      }
      for (i = 0; i < w; ++i) {
	unsigned mask = 1;
        for (ch = 0; ch < chan_count; ++ch) {
	  if (im->ch_mask & mask)
	    data[ch] = SampleFTo8(*samps);
	  ++samps;
          ++count;
	  mask <<= 1;
        }
        data += im->channels;
      }
    }

    return count;
  }
  else {
    dIMCTXim(im);
    i_push_error(0, "Image position outside of image");
    return -1;
  }
}

/*
=back

=head1 AUTHOR

Arnar M. Hrafnkelsson <addi@umich.edu>

Tony Cook <tony@develop-help.com>

=head1 SEE ALSO

L<Imager>

=cut
*/
