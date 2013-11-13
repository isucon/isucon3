/*
=head1 NAME

imgdouble.c - implements double per sample images

=head1 SYNOPSIS

  i_img *im = i_img_double_new(width, height, channels);
  # use like a normal image

=head1 DESCRIPTION

Implements double/sample images.

This basic implementation is required so that we have some larger 
sample image type to work with.

=over

=cut
*/

#define IMAGER_NO_CONTEXT
#include "imager.h"
#include "imageri.h"

static int i_ppix_ddoub(i_img *im, i_img_dim x, i_img_dim y, const i_color *val);
static int i_gpix_ddoub(i_img *im, i_img_dim x, i_img_dim y, i_color *val);
static i_img_dim i_glin_ddoub(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_color *vals);
static i_img_dim i_plin_ddoub(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, const i_color *vals);
static int i_ppixf_ddoub(i_img *im, i_img_dim x, i_img_dim y, const i_fcolor *val);
static int i_gpixf_ddoub(i_img *im, i_img_dim x, i_img_dim y, i_fcolor *val);
static i_img_dim i_glinf_ddoub(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_fcolor *vals);
static i_img_dim i_plinf_ddoub(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, const i_fcolor *vals);
static i_img_dim i_gsamp_ddoub(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_sample_t *samps, 
                       int const *chans, int chan_count);
static i_img_dim i_gsampf_ddoub(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_fsample_t *samps, 
                        int const *chans, int chan_count);
static i_img_dim 
i_psamp_ddoub(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, const i_sample_t *samps, const int *chans, int chan_count);
static i_img_dim 
i_psampf_ddoub(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, const i_fsample_t *samps, const int *chans, int chan_count);

/*
=item IIM_base_16bit_direct

Base structure used to initialize a 16-bit/sample image.

Internal.

=cut
*/
static i_img IIM_base_double_direct =
{
  0, /* channels set */
  0, 0, 0, /* xsize, ysize, bytes */
  ~0U, /* ch_mask */
  i_double_bits, /* bits */
  i_direct_type, /* type */
  0, /* virtual */
  NULL, /* idata */
  { 0, 0, NULL }, /* tags */
  NULL, /* ext_data */

  i_ppix_ddoub, /* i_f_ppix */
  i_ppixf_ddoub, /* i_f_ppixf */
  i_plin_ddoub, /* i_f_plin */
  i_plinf_ddoub, /* i_f_plinf */
  i_gpix_ddoub, /* i_f_gpix */
  i_gpixf_ddoub, /* i_f_gpixf */
  i_glin_ddoub, /* i_f_glin */
  i_glinf_ddoub, /* i_f_glinf */
  i_gsamp_ddoub, /* i_f_gsamp */
  i_gsampf_ddoub, /* i_f_gsampf */

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

  i_psamp_ddoub, /* i_f_psamp */
  i_psampf_ddoub /* i_f_psampf */
};

/*
=item im_img_double_new(ctx, x, y, ch)
X<im_img_double_new API>X<i_img_double_new API>
=category Image creation/destruction
=synopsis i_img *img = im_img_double_new(aIMCTX, width, height, channels);
=synopsis i_img *img = i_img_double_new(width, height, channels);

Creates a new double per sample image.

Also callable as C<i_img_double_new(width, height, channels)>.

=cut
*/
i_img *
im_img_double_new(pIMCTX, i_img_dim x, i_img_dim y, int ch) {
  size_t bytes;
  i_img *im;

  im_log((aIMCTX, 1,"i_img_double_new(x %" i_DF ", y %" i_DF ", ch %d)\n",
	  i_DFc(x), i_DFc(y), ch));

  if (x < 1 || y < 1) {
    im_push_error(aIMCTX, 0, "Image sizes must be positive");
    return NULL;
  }
  if (ch < 1 || ch > MAXCHANNELS) {
    im_push_errorf(aIMCTX, 0, "channels must be between 1 and %d", MAXCHANNELS);
    return NULL;
  }
  bytes = x * y * ch * sizeof(double);
  if (bytes / y / ch / sizeof(double) != x) {
    im_push_errorf(aIMCTX, 0, "integer overflow calculating image allocation");
    return NULL;
  }
  
  im = im_img_alloc(aIMCTX);
  *im = IIM_base_double_direct;
  i_tags_new(&im->tags);
  im->xsize = x;
  im->ysize = y;
  im->channels = ch;
  im->bytes = bytes;
  im->ext_data = NULL;
  im->idata = mymalloc(im->bytes);
  memset(im->idata, 0, im->bytes);
  im_img_init(aIMCTX, im);
  
  return im;
}

static int i_ppix_ddoub(i_img *im, i_img_dim x, i_img_dim y, const i_color *val) {
  i_img_dim off;
  int ch;

  if (x < 0 || x >= im->xsize || y < 0 || y >= im->ysize) 
    return -1;

  off = (x + y * im->xsize) * im->channels;
  if (I_ALL_CHANNELS_WRITABLE(im)) {
    for (ch = 0; ch < im->channels; ++ch)
      ((double*)im->idata)[off+ch] = Sample8ToF(val->channel[ch]);
  }
  else {
    for (ch = 0; ch < im->channels; ++ch)
      if (im->ch_mask & (1<<ch))
	((double*)im->idata)[off+ch] = Sample8ToF(val->channel[ch]);
  }

  return 0;
}

static int i_gpix_ddoub(i_img *im, i_img_dim x, i_img_dim y, i_color *val) {
  i_img_dim off;
  int ch;

  if (x < 0 || x >= im->xsize || y < 0 || y >= im->ysize) 
    return -1;

  off = (x + y * im->xsize) * im->channels;
  for (ch = 0; ch < im->channels; ++ch)
    val->channel[ch] = SampleFTo8(((double *)im->idata)[off+ch]);

  return 0;
}

static int i_ppixf_ddoub(i_img *im, i_img_dim x, i_img_dim y, const i_fcolor *val) {
  i_img_dim off;
  int ch;

  if (x < 0 || x >= im->xsize || y < 0 || y >= im->ysize) 
    return -1;

  off = (x + y * im->xsize) * im->channels;
  if (I_ALL_CHANNELS_WRITABLE(im)) {
    for (ch = 0; ch < im->channels; ++ch)
      ((double *)im->idata)[off+ch] = val->channel[ch];
  }
  else {
    for (ch = 0; ch < im->channels; ++ch)
      if (im->ch_mask & (1 << ch))
	((double *)im->idata)[off+ch] = val->channel[ch];
  }

  return 0;
}

static int i_gpixf_ddoub(i_img *im, i_img_dim x, i_img_dim y, i_fcolor *val) {
  i_img_dim off;
  int ch;

  if (x < 0 || x >= im->xsize || y < 0 || y >= im->ysize) 
    return -1;

  off = (x + y * im->xsize) * im->channels;
  for (ch = 0; ch < im->channels; ++ch)
    val->channel[ch] = ((double *)im->idata)[off+ch];

  return 0;
}

static i_img_dim i_glin_ddoub(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_color *vals) {
  int ch;
  i_img_dim count, i;
  i_img_dim off;
  if (y >=0 && y < im->ysize && l < im->xsize && l >= 0) {
    if (r > im->xsize)
      r = im->xsize;
    off = (l+y*im->xsize) * im->channels;
    count = r - l;
    for (i = 0; i < count; ++i) {
      for (ch = 0; ch < im->channels; ++ch) {
	vals[i].channel[ch] = SampleFTo8(((double *)im->idata)[off]);
        ++off;
      }
    }
    return count;
  }
  else {
    return 0;
  }
}

static i_img_dim i_plin_ddoub(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, const i_color *vals) {
  int ch;
  i_img_dim count, i;
  i_img_dim off;
  if (y >=0 && y < im->ysize && l < im->xsize && l >= 0) {
    if (r > im->xsize)
      r = im->xsize;
    off = (l+y*im->xsize) * im->channels;
    count = r - l;
    if (I_ALL_CHANNELS_WRITABLE(im)) {
      for (i = 0; i < count; ++i) {
	for (ch = 0; ch < im->channels; ++ch) {
	  ((double *)im->idata)[off] = Sample8ToF(vals[i].channel[ch]);
	  ++off;
	}
      }
    }
    else {
      for (i = 0; i < count; ++i) {
	for (ch = 0; ch < im->channels; ++ch) {
	  if (im->ch_mask & (1 << ch))
	    ((double *)im->idata)[off] = Sample8ToF(vals[i].channel[ch]);
	  ++off;
	}
      }
    }
    return count;
  }
  else {
    return 0;
  }
}

static i_img_dim i_glinf_ddoub(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_fcolor *vals) {
  int ch;
  i_img_dim count, i;
  i_img_dim off;
  if (y >=0 && y < im->ysize && l < im->xsize && l >= 0) {
    if (r > im->xsize)
      r = im->xsize;
    off = (l+y*im->xsize) * im->channels;
    count = r - l;
    for (i = 0; i < count; ++i) {
      for (ch = 0; ch < im->channels; ++ch) {
	vals[i].channel[ch] = ((double *)im->idata)[off];
        ++off;
      }
    }
    return count;
  }
  else {
    return 0;
  }
}

static i_img_dim i_plinf_ddoub(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, const i_fcolor *vals) {
  int ch;
  i_img_dim count, i;
  i_img_dim off;
  if (y >=0 && y < im->ysize && l < im->xsize && l >= 0) {
    if (r > im->xsize)
      r = im->xsize;
    off = (l+y*im->xsize) * im->channels;
    count = r - l;
    if (I_ALL_CHANNELS_WRITABLE(im)) {
      for (i = 0; i < count; ++i) {
	for (ch = 0; ch < im->channels; ++ch) {
	  ((double *)im->idata)[off] = vals[i].channel[ch];
	  ++off;
	}
      }
    }
    else {
      for (i = 0; i < count; ++i) {
	for (ch = 0; ch < im->channels; ++ch) {
	  if (im->ch_mask & (1 << ch))
	    ((double *)im->idata)[off] = vals[i].channel[ch];
	  ++off;
	}
      }
    }
    return count;
  }
  else {
    return 0;
  }
}

static i_img_dim i_gsamp_ddoub(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_sample_t *samps, 
                       int const *chans, int chan_count) {
  int ch;
  i_img_dim count, i, w;
  i_img_dim off;

  if (y >=0 && y < im->ysize && l < im->xsize && l >= 0) {
    if (r > im->xsize)
      r = im->xsize;
    off = (l+y*im->xsize) * im->channels;
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
          *samps++ = SampleFTo8(((double *)im->idata)[off+chans[ch]]);
          ++count;
        }
        off += im->channels;
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
          *samps++ = SampleFTo8(((double *)im->idata)[off+ch]);
          ++count;
        }
        off += im->channels;
      }
    }

    return count;
  }
  else {
    return 0;
  }
}

static i_img_dim i_gsampf_ddoub(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_fsample_t *samps, 
                        int const *chans, int chan_count) {
  int ch;
  i_img_dim count, i, w;
  i_img_dim off;

  if (y >=0 && y < im->ysize && l < im->xsize && l >= 0) {
    if (r > im->xsize)
      r = im->xsize;
    off = (l+y*im->xsize) * im->channels;
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
          *samps++ = ((double *)im->idata)[off+chans[ch]];
          ++count;
        }
        off += im->channels;
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
          *samps++ = ((double *)im->idata)[off+ch];
          ++count;
        }
        off += im->channels;
      }
    }

    return count;
  }
  else {
    return 0;
  }
}

/*
=item i_psamp_ddoub(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, const i_sample_t *samps, int *chans, int chan_count)

Writes sample values to im for the horizontal line (l, y) to (r-1,y)
for the channels specified by chans, an array of int with chan_count
elements.

Returns the number of samples written (which should be (r-l) *
bits_set(chan_mask)

=cut
*/

static
i_img_dim
i_psamp_ddoub(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, 
	  const i_sample_t *samps, const int *chans, int chan_count) {
  int ch;
  i_img_dim count, i, w;

  if (y >=0 && y < im->ysize && l < im->xsize && l >= 0) {
    i_img_dim offset;
    if (r > im->xsize)
      r = im->xsize;
    offset = (l+y*im->xsize) * im->channels;
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
	    ((double*)im->idata)[offset + chans[ch]] = Sample8ToF(*samps);
	    ++samps;
	    ++count;
	  }
	  offset += im->channels;
	}
      }
      else {
	for (i = 0; i < w; ++i) {
	  for (ch = 0; ch < chan_count; ++ch) {
	    if (im->ch_mask & (1 << (chans[ch])))
	      ((double*)im->idata)[offset + chans[ch]] = Sample8ToF(*samps);
	    
	    ++samps;
	    ++count;
	  }
	  offset += im->channels;
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
	    ((double*)im->idata)[offset + ch] = Sample8ToF(*samps);

	  ++samps;
          ++count;
	  mask <<= 1;
        }
        offset += im->channels;
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
=item i_psampf_ddoub(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, const i_fsample_t *samps, int *chans, int chan_count)

Writes sample values to im for the horizontal line (l, y) to (r-1,y)
for the channels specified by chans, an array of int with chan_count
elements.

Returns the number of samples written (which should be (r-l) *
bits_set(chan_mask)

=cut
*/

static
i_img_dim
i_psampf_ddoub(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, 
	       const i_fsample_t *samps, const int *chans, int chan_count) {
  int ch;
  i_img_dim count, i, w;

  if (y >=0 && y < im->ysize && l < im->xsize && l >= 0) {
    i_img_dim offset;
    if (r > im->xsize)
      r = im->xsize;
    offset = (l+y*im->xsize) * im->channels;
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
	    ((double*)im->idata)[offset + chans[ch]] = *samps;
	    ++samps;
	    ++count;
	  }
	  offset += im->channels;
	}
      }
      else {
	for (i = 0; i < w; ++i) {
	  for (ch = 0; ch < chan_count; ++ch) {
	    if (im->ch_mask & (1 << (chans[ch])))
	      ((double*)im->idata)[offset + chans[ch]] = *samps;
	    
	    ++samps;
	    ++count;
	  }
	  offset += im->channels;
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
	    ((double*)im->idata)[offset + ch] = *samps;

	  ++samps;
          ++count;
	  mask <<= 1;
        }
        offset += im->channels;
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
=item i_img_to_drgb(im)

=category Image creation

Returns a double/sample version of the supplied image.

Returns the image on success, or NULL on failure.

=cut
*/

i_img *
i_img_to_drgb(i_img *im) {
  i_img *targ;
  i_fcolor *line;
  i_img_dim y;
  dIMCTXim(im);

  targ = im_img_double_new(aIMCTX, im->xsize, im->ysize, im->channels);
  if (!targ)
    return NULL;
  line = mymalloc(sizeof(i_fcolor) * im->xsize);
  for (y = 0; y < im->ysize; ++y) {
    i_glinf(im, 0, im->xsize, y, line);
    i_plinf(targ, 0, im->xsize, y, line);
  }

  myfree(line);

  return targ;
}

/*
=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=head1 SEE ALSO

Imager(3)

=cut
*/
