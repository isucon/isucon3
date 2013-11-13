/*
=head1 NAME

img16.c - implements 16-bit images

=head1 SYNOPSIS

  i_img *im = i_img_16_new(i_img_dim x, i_img_dim y, int channels);
  # use like a normal image

=head1 DESCRIPTION

Implements 16-bit/sample images.

This basic implementation is required so that we have some larger 
sample image type to work with.

=over

=cut
*/

#define IMAGER_NO_CONTEXT

#include "imager.h"
#include "imageri.h"

static int i_ppix_d16(i_img *im, i_img_dim x, i_img_dim y, const i_color *val);
static int i_gpix_d16(i_img *im, i_img_dim x, i_img_dim y, i_color *val);
static i_img_dim i_glin_d16(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_color *vals);
static i_img_dim i_plin_d16(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, const i_color *vals);
static int i_ppixf_d16(i_img *im, i_img_dim x, i_img_dim y, const i_fcolor *val);
static int i_gpixf_d16(i_img *im, i_img_dim x, i_img_dim y, i_fcolor *val);
static i_img_dim i_glinf_d16(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_fcolor *vals);
static i_img_dim i_plinf_d16(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, const i_fcolor *vals);
static i_img_dim i_gsamp_d16(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_sample_t *samps, 
                       int const *chans, int chan_count);
static i_img_dim i_gsampf_d16(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_fsample_t *samps, 
                        int const *chans, int chan_count);
static i_img_dim i_gsamp_bits_d16(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, unsigned *samps, 
			    int const *chans, int chan_count, int bits);
static i_img_dim i_psamp_bits_d16(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, unsigned const *samps, 
			    int const *chans, int chan_count, int bits);
static i_img_dim i_psamp_d16(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, const i_sample_t *samps, const int *chans, int chan_count);
static i_img_dim i_psampf_d16(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, const i_fsample_t *samps, const int *chans, int chan_count);

/*
=item IIM_base_16bit_direct

Base structure used to initialize a 16-bit/sample image.

Internal.

=cut
*/
static i_img IIM_base_16bit_direct =
{
  0, /* channels set */
  0, 0, 0, /* xsize, ysize, bytes */
  ~0U, /* ch_mask */
  i_16_bits, /* bits */
  i_direct_type, /* type */
  0, /* virtual */
  NULL, /* idata */
  { 0, 0, NULL }, /* tags */
  NULL, /* ext_data */

  i_ppix_d16, /* i_f_ppix */
  i_ppixf_d16, /* i_f_ppixf */
  i_plin_d16, /* i_f_plin */
  i_plinf_d16, /* i_f_plinf */
  i_gpix_d16, /* i_f_gpix */
  i_gpixf_d16, /* i_f_gpixf */
  i_glin_d16, /* i_f_glin */
  i_glinf_d16, /* i_f_glinf */
  i_gsamp_d16, /* i_f_gsamp */
  i_gsampf_d16, /* i_f_gsampf */

  NULL, /* i_f_gpal */
  NULL, /* i_f_ppal */
  NULL, /* i_f_addcolors */
  NULL, /* i_f_getcolors */
  NULL, /* i_f_colorcount */
  NULL, /* i_f_maxcolors */
  NULL, /* i_f_findcolor */
  NULL, /* i_f_setcolors */

  NULL, /* i_f_destroy */

  i_gsamp_bits_d16,
  i_psamp_bits_d16,

  i_psamp_d16,
  i_psampf_d16
};

/* it's possible some platforms won't have a 16-bit integer type,
   so we check for one otherwise we work by bytes directly

   We do assume 8-bit char

   "Compaq C V6.4-009 on Compaq Tru64 UNIX V5.1A (Rev. 1885)" says it
   supports C99, but doesn't supply stdint.h, which is required for
   both hosted and freestanding implementations.  So guard against it.
*/
#if __STDC_VERSION__ >= 199901L && !defined(OS_dec_osf)
/* C99 should define something useful */
#include <stdint.h>
#ifdef UINT16_MAX
typedef uint16_t i_sample16_t;
#define GOT16
#endif
#endif

/* check out unsigned short */
#ifndef GOT16
#include <limits.h>
#if USHRT_MAX == 65535
typedef unsigned short i_sample16_t;
#define GOT16
#endif
#endif

#ifdef GOT16

/* we have a real 16-bit unsigned integer */
#define STORE16(bytes, offset, word) \
   (((i_sample16_t *)(bytes))[offset] = (word))
#define STORE8as16(bytes, offset, byte) \
   (((i_sample16_t *)(bytes))[offset] = (byte) * 256 + (byte))
#define GET16(bytes, offset) \
     (((i_sample16_t *)(bytes))[offset])
#else

/* we have to do this the hard way */
#define STORE16(bytes, offset, word) \
   ((((unsigned char *)(bytes))[(offset)*2] = (word) >> 8), \
    (((unsigned char *)(bytes))[(offset)*2+1] = (word) & 0xFF))
#define STORE8as16(bytes, offset, byte) \
   ((((unsigned char *)(bytes))[(offset)*2] = (byte)), \
    (((unsigned char *)(bytes))[(offset)*2+1] = (byte)))
   
#define GET16(bytes, offset) \
   (((unsigned char *)(bytes))[(offset)*2] * 256 \
    + ((unsigned char *)(bytes))[(offset)*2+1])

#endif

#define GET16as8(bytes, offset) \
     ((((i_sample16_t *)(bytes))[offset]+127) / 257)

/*
=item im_img_16_new(ctx, x, y, ch)
X<im_img_16_new API>X<i_img_16_new API>
=category Image creation/destruction
=synopsis i_img *img = im_img_16_new(aIMCTX, width, height, channels);
=synopsis i_img *img = i_img_16_new(width, height, channels);

Create a new 16-bit/sample image.

Returns the image on success, or NULL on failure.

Also callable as C<i_img_16_new(x, y, ch)>

=cut
*/

i_img *
im_img_16_new(pIMCTX, i_img_dim x, i_img_dim y, int ch) {
  i_img *im;
  size_t bytes, line_bytes;

  im_log((aIMCTX, 1,"i_img_16_new(x %" i_DF ", y %" i_DF ", ch %d)\n",
	  i_DFc(x), i_DFc(y), ch));

  if (x < 1 || y < 1) {
    im_push_error(aIMCTX, 0, "Image sizes must be positive");
    return NULL;
  }
  if (ch < 1 || ch > MAXCHANNELS) {
    im_push_errorf(aIMCTX, 0, "channels must be between 1 and %d", MAXCHANNELS);
    return NULL;
  }
  bytes =  x * y * ch * 2;
  if (bytes / y / ch / 2 != x) {
    im_push_errorf(aIMCTX, 0, "integer overflow calculating image allocation");
    return NULL;
  }
  
  /* basic assumption: we can always allocate a buffer representing a
     line from the image, otherwise we're going to have trouble
     working with the image */
  line_bytes = sizeof(i_fcolor) * x;
  if (line_bytes / x != sizeof(i_fcolor)) {
    im_push_error(aIMCTX, 0, "integer overflow calculating scanline allocation");
    return NULL;
  }

  im = im_img_alloc(aIMCTX);
  *im = IIM_base_16bit_direct;
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

/*
=item i_img_to_rgb16(im)

=category Image creation

Returns a 16-bit/sample version of the supplied image.

Returns the image on success, or NULL on failure.

=cut
*/

i_img *
i_img_to_rgb16(i_img *im) {
  i_img *targ;
  i_fcolor *line;
  i_img_dim y;
  dIMCTXim(im);

  targ = im_img_16_new(aIMCTX, im->xsize, im->ysize, im->channels);
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

static int i_ppix_d16(i_img *im, i_img_dim x, i_img_dim y, const i_color *val) {
  i_img_dim off;
  int ch;

  if (x < 0 || x >= im->xsize || y < 0 || y >= im->ysize) 
    return -1;

  off = (x + y * im->xsize) * im->channels;
  if (I_ALL_CHANNELS_WRITABLE(im)) {
    for (ch = 0; ch < im->channels; ++ch)
      STORE8as16(im->idata, off+ch, val->channel[ch]);
  }
  else {
    for (ch = 0; ch < im->channels; ++ch)
      if (im->ch_mask & (1 << ch))
	STORE8as16(im->idata, off+ch, val->channel[ch]);
  }

  return 0;
}

static int i_gpix_d16(i_img *im, i_img_dim x, i_img_dim y, i_color *val) {
  i_img_dim off;
  int ch;

  if (x < 0 || x >= im->xsize || y < 0 || y >= im->ysize) 
    return -1;

  off = (x + y * im->xsize) * im->channels;
  for (ch = 0; ch < im->channels; ++ch)
    val->channel[ch] = GET16as8(im->idata, off+ch);

  return 0;
}

static int i_ppixf_d16(i_img *im, i_img_dim x, i_img_dim y, const i_fcolor *val) {
  i_img_dim off;
  int ch;

  if (x < 0 || x >= im->xsize || y < 0 || y >= im->ysize) 
    return -1;

  off = (x + y * im->xsize) * im->channels;
  if (I_ALL_CHANNELS_WRITABLE(im)) {
    for (ch = 0; ch < im->channels; ++ch)
      STORE16(im->idata, off+ch, SampleFTo16(val->channel[ch]));
  }
  else {
    for (ch = 0; ch < im->channels; ++ch)
      if (im->ch_mask & (1 << ch))
	STORE16(im->idata, off+ch, SampleFTo16(val->channel[ch]));
  }

  return 0;
}

static int i_gpixf_d16(i_img *im, i_img_dim x, i_img_dim y, i_fcolor *val) {
  i_img_dim off;
  int ch;

  if (x < 0 || x >= im->xsize || y < 0 || y >= im->ysize) 
    return -1;

  off = (x + y * im->xsize) * im->channels;
  for (ch = 0; ch < im->channels; ++ch)
    val->channel[ch] = Sample16ToF(GET16(im->idata, off+ch));

  return 0;
}

static i_img_dim i_glin_d16(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_color *vals) {
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
	vals[i].channel[ch] = GET16as8(im->idata, off);
        ++off;
      }
    }
    return count;
  }
  else {
    return 0;
  }
}

static i_img_dim i_plin_d16(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, const i_color *vals) {
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
	  STORE8as16(im->idata, off, vals[i].channel[ch]);
	  ++off;
	}
      }
    }
    else {
      for (i = 0; i < count; ++i) {
	for (ch = 0; ch < im->channels; ++ch) {
	  if (im->ch_mask & (1 << ch))
	    STORE8as16(im->idata, off, vals[i].channel[ch]);
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

static i_img_dim i_glinf_d16(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_fcolor *vals) {
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
	vals[i].channel[ch] = Sample16ToF(GET16(im->idata, off));
        ++off;
      }
    }
    return count;
  }
  else {
    return 0;
  }
}

static i_img_dim i_plinf_d16(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, const i_fcolor *vals) {
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
	  STORE16(im->idata, off, SampleFTo16(vals[i].channel[ch]));
	  ++off;
	}
      }
    }
    else {
      for (i = 0; i < count; ++i) {
	for (ch = 0; ch < im->channels; ++ch) {
	  if (im->ch_mask & (1 << ch))
	    STORE16(im->idata, off, SampleFTo16(vals[i].channel[ch]));
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

static i_img_dim i_gsamp_d16(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_sample_t *samps, 
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
          *samps++ = GET16as8(im->idata, off+chans[ch]);
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
          *samps++ = GET16as8(im->idata, off+ch);
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

static i_img_dim i_gsampf_d16(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_fsample_t *samps, 
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
          *samps++ = Sample16ToF(GET16(im->idata, off+chans[ch]));
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
          *samps++ = Sample16ToF(GET16(im->idata, off+ch));
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

static i_img_dim 
i_gsamp_bits_d16(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, unsigned *samps, 
			    int const *chans, int chan_count, int bits) {
  int ch;
  i_img_dim count, i, w;
  i_img_dim off;

  if (bits != 16) {
    return i_gsamp_bits_fb(im, l, r, y, samps, chans, chan_count, bits);
  }

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
          return -1;
        }
      }
      for (i = 0; i < w; ++i) {
        for (ch = 0; ch < chan_count; ++ch) {
          *samps++ = GET16(im->idata, off+chans[ch]);
          ++count;
        }
        off += im->channels;
      }
    }
    else {
      if (chan_count <= 0 || chan_count > im->channels) {
	dIMCTXim(im);
	i_push_error(0, "Invalid channel count");
	return -1;
      }
      for (i = 0; i < w; ++i) {
        for (ch = 0; ch < chan_count; ++ch) {
          *samps++ = GET16(im->idata, off+ch);
          ++count;
        }
        off += im->channels;
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

static i_img_dim 
i_psamp_bits_d16(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, unsigned const *samps, 
			    int const *chans, int chan_count, int bits) {
  int ch;
  i_img_dim count, i, w;
  i_img_dim off;

  if (bits != 16) {
    dIMCTXim(im);
    i_push_error(0, "Invalid bits for 16-bit image");
    return -1;
  }

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
          return -1;
        }
      }
      for (i = 0; i < w; ++i) {
        for (ch = 0; ch < chan_count; ++ch) {
	  if (im->ch_mask & (1 << ch))
	    STORE16(im->idata, off+chans[ch], *samps);
	  ++samps;
	  ++count;
        }
        off += im->channels;
      }
    }
    else {
      if (chan_count <= 0 || chan_count > im->channels) {
	dIMCTXim(im);
	i_push_error(0, "Invalid channel count");
	return -1;
      }
      for (i = 0; i < w; ++i) {
        for (ch = 0; ch < chan_count; ++ch) {
	  if (im->ch_mask & (1 << ch)) 
	    STORE16(im->idata, off+ch, *samps);
	  ++samps;
          ++count;
        }
        off += im->channels;
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
=item i_psamp_d16(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, const i_sample_t *samps, int *chans, int chan_count)

Writes sample values to im for the horizontal line (l, y) to (r-1,y)
for the channels specified by chans, an array of int with chan_count
elements.

Returns the number of samples written (which should be (r-l) *
bits_set(chan_mask)

=cut
*/

static
i_img_dim
i_psamp_d16(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, 
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
	    STORE8as16(im->idata, offset + chans[ch], *samps);
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
	    STORE8as16(im->idata, offset + chans[ch], *samps);
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
	    STORE8as16(im->idata, offset + ch, *samps);
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
=item i_psampf_d16(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, const i_fsample_t *samps, int *chans, int chan_count)

Writes sample values to im for the horizontal line (l, y) to (r-1,y)
for the channels specified by chans, an array of int with chan_count
elements.

Returns the number of samples written (which should be (r-l) *
bits_set(chan_mask)

=cut
*/

static
i_img_dim
i_psampf_d16(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, 
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
	    unsigned samp16 = SampleFTo16(*samps);
	    STORE16(im->idata, offset + chans[ch], samp16);
	    ++samps;
	    ++count;
	  }
	  offset += im->channels;
	}
      }
      else {
	for (i = 0; i < w; ++i) {
	  for (ch = 0; ch < chan_count; ++ch) {
	    if (im->ch_mask & (1 << (chans[ch]))) {
	      unsigned samp16 = SampleFTo16(*samps);
	      STORE16(im->idata, offset + chans[ch], samp16);
	    }
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
	  if (im->ch_mask & mask) {
	    unsigned samp16 = SampleFTo16(*samps);
	    STORE16(im->idata, offset + ch, samp16);
	  }
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
=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=head1 SEE ALSO

Imager(3)

=cut
*/
