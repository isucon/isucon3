#define IMAGER_NO_CONTEXT

#include "imager.h"
#include "imageri.h"

/*
=head1 NAME

image.c - implements most of the basic functions of Imager and much of the rest

=head1 SYNOPSIS

  i_img *i;
  i_color *c;
  c = i_color_new(red, green, blue, alpha);
  ICL_DESTROY(c);
  i = i_img_8_new();
  i_img_destroy(i);
  // and much more

=head1 DESCRIPTION

image.c implements the basic functions to create and destroy image and
color objects for Imager.

=head1 FUNCTION REFERENCE

Some of these functions are internal.

=over

=cut
*/

im_context_t (*im_get_context)(void) = NULL;

#define XAXIS 0
#define YAXIS 1
#define XYAXIS 2

#define minmax(a,b,i) ( ((a>=i)?a: ( (b<=i)?b:i   )) )

/* Hack around an obscure linker bug on solaris - probably due to builtin gcc thingies */
void i_linker_bug_fake(void) { ceil(1); }

/*
=item im_img_alloc(aIMCTX)
X<im_img_alloc API>X<i_img_alloc API>
=category Image Implementation
=synopsis i_img *im = im_img_alloc(aIMCTX);
=synopsis i_img *im = i_img_alloc();

Allocates a new i_img structure.

When implementing a new image type perform the following steps in your
image object creation function:

=over

=item 1.

allocate the image with i_img_alloc().

=item 2.

initialize any function pointers or other data as needed, you can
overwrite the whole block if you need to.

=item 3.

initialize Imager's internal data by calling i_img_init() on the image
object.

=back

=cut
*/

i_img *
im_img_alloc(pIMCTX) {
  return mymalloc(sizeof(i_img));
}

/*
=item im_img_init(aIMCTX, image)
X<im_img_init API>X<i_img_init API>
=category Image Implementation
=synopsis im_img_init(aIMCTX, im);
=synopsis i_img_init(im);

Imager internal initialization of images.

See L</im_img_alloc(aIMCTX)> for more information.

=cut
*/

void
im_img_init(pIMCTX, i_img *img) {
  img->im_data = NULL;
  img->context = aIMCTX;
  im_context_refinc(aIMCTX, "img_init");
}

/* 
=item ICL_new_internal(r, g, b, a)

Return a new color object with values passed to it.

   r - red   component (range: 0 - 255)
   g - green component (range: 0 - 255)
   b - blue  component (range: 0 - 255)
   a - alpha component (range: 0 - 255)

=cut
*/

i_color *
ICL_new_internal(unsigned char r,unsigned char g,unsigned char b,unsigned char a) {
  i_color *cl = NULL;
  dIMCTX;

  im_log((aIMCTX,1,"ICL_new_internal(r %d,g %d,b %d,a %d)\n", r, g, b, a));

  if ( (cl=mymalloc(sizeof(i_color))) == NULL) im_fatal(aIMCTX, 2,"malloc() error\n");
  cl->rgba.r = r;
  cl->rgba.g = g;
  cl->rgba.b = b;
  cl->rgba.a = a;
  im_log((aIMCTX,1,"(%p) <- ICL_new_internal\n",cl));
  return cl;
}


/*
=item ICL_set_internal(cl, r, g, b, a)

 Overwrite a color with new values.

   cl - pointer to color object
   r - red   component (range: 0 - 255)
   g - green component (range: 0 - 255)
   b - blue  component (range: 0 - 255)
   a - alpha component (range: 0 - 255)

=cut
*/

i_color *
ICL_set_internal(i_color *cl,unsigned char r,unsigned char g,unsigned char b,unsigned char a) {
  dIMCTX;
  im_log((aIMCTX,1,"ICL_set_internal(cl* %p,r %d,g %d,b %d,a %d)\n",cl,r,g,b,a));
  if (cl == NULL)
    if ( (cl=mymalloc(sizeof(i_color))) == NULL)
      im_fatal(aIMCTX, 2,"malloc() error\n");
  cl->rgba.r=r;
  cl->rgba.g=g;
  cl->rgba.b=b;
  cl->rgba.a=a;
  im_log((aIMCTX,1,"(%p) <- ICL_set_internal\n",cl));
  return cl;
}


/* 
=item ICL_add(dst, src, ch)

Add src to dst inplace - dst is modified.

   dst - pointer to destination color object
   src - pointer to color object that is added
   ch - number of channels

=cut
*/

void
ICL_add(i_color *dst,i_color *src,int ch) {
  int tmp,i;
  for(i=0;i<ch;i++) {
    tmp=dst->channel[i]+src->channel[i];
    dst->channel[i]= tmp>255 ? 255:tmp;
  }
}

/* 
=item ICL_info(cl)

Dump color information to log - strictly for debugging.

   cl - pointer to color object

=cut
*/

void
ICL_info(i_color const *cl) {
  dIMCTX;
  im_log((aIMCTX, 1,"i_color_info(cl* %p)\n",cl));
  im_log((aIMCTX, 1,"i_color_info: (%d,%d,%d,%d)\n",cl->rgba.r,cl->rgba.g,cl->rgba.b,cl->rgba.a));
}

/* 
=item ICL_DESTROY

Destroy ancillary data for Color object.

   cl - pointer to color object

=cut
*/

void
ICL_DESTROY(i_color *cl) {
  dIMCTX;
  im_log((aIMCTX, 1,"ICL_DESTROY(cl* %p)\n",cl));
  myfree(cl);
}

/*
=item i_fcolor_new(double r, double g, double b, double a)

=cut
*/
i_fcolor *i_fcolor_new(double r, double g, double b, double a) {
  i_fcolor *cl = NULL;
  dIMCTX;

  im_log((aIMCTX, 1,"i_fcolor_new(r %g,g %g,b %g,a %g)\n", r, g, b, a));

  if ( (cl=mymalloc(sizeof(i_fcolor))) == NULL) im_fatal(aIMCTX, 2,"malloc() error\n");
  cl->rgba.r = r;
  cl->rgba.g = g;
  cl->rgba.b = b;
  cl->rgba.a = a;
  im_log((aIMCTX, 1,"(%p) <- i_fcolor_new\n",cl));

  return cl;
}

/*
=item i_fcolor_destroy(i_fcolor *cl) 

=cut
*/
void i_fcolor_destroy(i_fcolor *cl) {
  myfree(cl);
}

/* 
=item i_img_exorcise(im)

Free image data.

   im - Image pointer

=cut
*/

void
i_img_exorcise(i_img *im) {
  dIMCTXim(im);
  im_log((aIMCTX,1,"i_img_exorcise(im* %p)\n",im));
  i_tags_destroy(&im->tags);
  if (im->i_f_destroy)
    (im->i_f_destroy)(im);
  if (im->idata != NULL) { myfree(im->idata); }
  im->idata    = NULL;
  im->xsize    = 0;
  im->ysize    = 0;
  im->channels = 0;

  im->ext_data=NULL;
}

/* 
=item i_img_destroy(C<img>)
=order 90
=category Image creation/destruction
=synopsis i_img_destroy(img)

Destroy an image object

=cut
*/

void
i_img_destroy(i_img *im) {
  dIMCTXim(im);
  im_log((aIMCTX, 1,"i_img_destroy(im %p)\n",im));
  i_img_exorcise(im);
  if (im) { myfree(im); }
  im_context_refdec(aIMCTX, "img_destroy");
}

/* 
=item i_img_info(im, info)

=category Image

Return image information

   im - Image pointer
   info - pointer to array to return data

info is an array of 4 integers with the following values:

 info[0] - width
 info[1] - height
 info[2] - channels
 info[3] - channel mask

=cut
*/


void
i_img_info(i_img *im, i_img_dim *info) {
  dIMCTXim(im);
  im_log((aIMCTX,1,"i_img_info(im %p)\n",im));
  if (im != NULL) {
    im_log((aIMCTX,1,"i_img_info: xsize=%" i_DF " ysize=%" i_DF " channels=%d "
	    "mask=%ud\n",
	    i_DFc(im->xsize), i_DFc(im->ysize), im->channels,im->ch_mask));
    im_log((aIMCTX,1,"i_img_info: idata=%p\n",im->idata));
    info[0] = im->xsize;
    info[1] = im->ysize;
    info[2] = im->channels;
    info[3] = im->ch_mask;
  } else {
    info[0] = 0;
    info[1] = 0;
    info[2] = 0;
    info[3] = 0;
  }
}

/*
=item i_img_setmask(C<im>, C<ch_mask>)
=category Image Information
=synopsis // only channel 0 writable 
=synopsis i_img_setmask(img, 0x01);

Set the image channel mask for C<im> to C<ch_mask>.

The image channel mask gives some control over which channels can be
written to in the image.

=cut
*/
void
i_img_setmask(i_img *im,int ch_mask) { im->ch_mask=ch_mask; }


/*
=item i_img_getmask(C<im>)
=category Image Information
=synopsis int mask = i_img_getmask(img);

Get the image channel mask for C<im>.

=cut
*/
int
i_img_getmask(i_img *im) { return im->ch_mask; }

/*
=item i_img_getchannels(C<im>)
=category Image Information
=synopsis int channels = i_img_getchannels(img);

Get the number of channels in C<im>.

=cut
*/
int
i_img_getchannels(i_img *im) { return im->channels; }

/*
=item i_img_get_width(C<im>)
=category Image Information
=synopsis i_img_dim width = i_img_get_width(im);

Returns the width in pixels of the image.

=cut
*/
i_img_dim
i_img_get_width(i_img *im) {
  return im->xsize;
}

/*
=item i_img_get_height(C<im>)
=category Image Information
=synopsis i_img_dim height = i_img_get_height(im);

Returns the height in pixels of the image.

=cut
*/
i_img_dim
i_img_get_height(i_img *im) {
  return im->ysize;
}

/*
=item i_copyto_trans(C<im>, C<src>, C<x1>, C<y1>, C<x2>, C<y2>, C<tx>, C<ty>, C<trans>)

=category Image

(C<x1>,C<y1>) (C<x2>,C<y2>) specifies the region to copy (in the
source coordinates) (C<tx>,C<ty>) specifies the upper left corner for
the target image.  pass NULL in C<trans> for non transparent i_colors.

=cut
*/

void
i_copyto_trans(i_img *im,i_img *src,i_img_dim x1,i_img_dim y1,i_img_dim x2,i_img_dim y2,i_img_dim tx,i_img_dim ty,const i_color *trans) {
  i_color pv;
  i_img_dim x,y,t,ttx,tty,tt;
  int ch;
  dIMCTXim(im);

  im_log((aIMCTX, 1,"i_copyto_trans(im* %p,src %p, p1(" i_DFp "), p2(" i_DFp "), "
	  "to(" i_DFp "), trans* %p)\n",
	  im, src, i_DFcp(x1, y1), i_DFcp(x2, y2), i_DFcp(tx, ty), trans));
  
  if (x2<x1) { t=x1; x1=x2; x2=t; }
  if (y2<y1) { t=y1; y1=y2; y2=t; }

  ttx=tx;
  for(x=x1;x<x2;x++)
    {
      tty=ty;
      for(y=y1;y<y2;y++)
	{
	  i_gpix(src,x,y,&pv);
	  if ( trans != NULL)
	  {
	    tt=0;
	    for(ch=0;ch<im->channels;ch++) if (trans->channel[ch]!=pv.channel[ch]) tt++;
	    if (tt) i_ppix(im,ttx,tty,&pv);
	  } else i_ppix(im,ttx,tty,&pv);
	  tty++;
	}
      ttx++;
    }
}

/*
=item i_copy(source)

=category Image

Creates a new image that is a copy of the image C<source>.

Tags are not copied, only the image data.

Returns: i_img *

=cut
*/

i_img *
i_copy(i_img *src) {
  i_img_dim y, y1, x1;
  dIMCTXim(src);
  i_img *im = i_sametype(src, src->xsize, src->ysize);

  im_log((aIMCTX,1,"i_copy(src %p)\n", src));

  if (!im)
    return NULL;

  x1 = src->xsize;
  y1 = src->ysize;
  if (src->type == i_direct_type) {
    if (src->bits == i_8_bits) {
      i_color *pv;
      pv = mymalloc(sizeof(i_color) * x1);
      
      for (y = 0; y < y1; ++y) {
        i_glin(src, 0, x1, y, pv);
        i_plin(im, 0, x1, y, pv);
      }
      myfree(pv);
    }
    else {
      i_fcolor *pv;

      pv = mymalloc(sizeof(i_fcolor) * x1);
      for (y = 0; y < y1; ++y) {
        i_glinf(src, 0, x1, y, pv);
        i_plinf(im, 0, x1, y, pv);
      }
      myfree(pv);
    }
  }
  else {
    i_palidx *vals;

    vals = mymalloc(sizeof(i_palidx) * x1);
    for (y = 0; y < y1; ++y) {
      i_gpal(src, 0, x1, y, vals);
      i_ppal(im, 0, x1, y, vals);
    }
    myfree(vals);
  }

  return im;
}

/*

http://en.wikipedia.org/wiki/Lanczos_resampling

*/

static
float
Lanczos(float x) {
  float PIx, PIx2;
  
  PIx = PI * x;
  PIx2 = PIx / 2.0;
  
  if ((x >= 2.0) || (x <= -2.0)) return (0.0);
  else if (x == 0.0) return (1.0);
  else return(sin(PIx) / PIx * sin(PIx2) / PIx2);
}


/*
=item i_scaleaxis(im, value, axis)

Returns a new image object which is I<im> scaled by I<value> along
wither the x-axis (I<axis> == 0) or the y-axis (I<axis> == 1).

=cut
*/

i_img*
i_scaleaxis(i_img *im, double Value, int Axis) {
  i_img_dim hsize, vsize, i, j, k, l, lMax, iEnd, jEnd;
  i_img_dim LanczosWidthFactor;
  float *l0, *l1;
  double OldLocation;
  i_img_dim T; 
  double t;
  float F, PictureValue[MAXCHANNELS];
  short psave;
  i_color val,val1,val2;
  i_img *new_img;
  int has_alpha = i_img_has_alpha(im);
  int color_chans = i_img_color_channels(im);
  dIMCTXim(im);

  i_clear_error();
  im_log((aIMCTX, 1,"i_scaleaxis(im %p,Value %.2f,Axis %d)\n",im,Value,Axis));

  if (Axis == XAXIS) {
    hsize = (i_img_dim)(0.5 + im->xsize * Value);
    if (hsize < 1) {
      hsize = 1;
      Value = 1.0 / im->xsize;
    }
    vsize = im->ysize;
    
    jEnd = hsize;
    iEnd = vsize;
  } else {
    hsize = im->xsize;
    vsize = (i_img_dim)(0.5 + im->ysize * Value);

    if (vsize < 1) {
      vsize = 1;
      Value = 1.0 / im->ysize;
    }

    jEnd = vsize;
    iEnd = hsize;
  }
  
  new_img = i_img_8_new(hsize, vsize, im->channels);
  if (!new_img) {
    i_push_error(0, "cannot create output image");
    return NULL;
  }
  
  /* 1.4 is a magic number, setting it to 2 will cause rather blurred images */
  LanczosWidthFactor = (Value >= 1) ? 1 : (i_img_dim) (1.4/Value); 
  lMax = LanczosWidthFactor << 1;
  
  l0 = mymalloc(lMax * sizeof(float));
  l1 = mymalloc(lMax * sizeof(float));
  
  for (j=0; j<jEnd; j++) {
    OldLocation = ((double) j) / Value;
    T = (i_img_dim) (OldLocation);
    F = OldLocation - T;
    
    for (l = 0; l<lMax; l++) {
      l0[lMax-l-1] = Lanczos(((float) (lMax-l-1) + F) / (float) LanczosWidthFactor);
      l1[l]        = Lanczos(((float) (l+1)      - F) / (float) LanczosWidthFactor);
    }
    
    /* Make sure filter is normalized */
    t = 0.0;
    for(l=0; l<lMax; l++) {
      t+=l0[l];
      t+=l1[l];
    }
    t /= (double)LanczosWidthFactor;
    
    for(l=0; l<lMax; l++) {
      l0[l] /= t;
      l1[l] /= t;
    }

    if (Axis == XAXIS) {
      
      for (i=0; i<iEnd; i++) {
	for (k=0; k<im->channels; k++) PictureValue[k] = 0.0;
	for (l=0; l<lMax; l++) {
	  i_img_dim mx = T-lMax+l+1;
	  i_img_dim Mx = T+l+1;
	  mx = (mx < 0) ? 0 : mx;
	  Mx = (Mx >= im->xsize) ? im->xsize-1 : Mx;
	  
	  i_gpix(im, Mx, i, &val1);
	  i_gpix(im, mx, i, &val2);

	  if (has_alpha) {
	    i_sample_t alpha1 = val1.channel[color_chans];
	    i_sample_t alpha2 = val2.channel[color_chans];
	    for (k=0; k < color_chans; k++) {
	      PictureValue[k] += l1[l]        * val1.channel[k] * alpha1 / 255;
	      PictureValue[k] += l0[lMax-l-1] * val2.channel[k] * alpha2 / 255;
	    }
	    PictureValue[color_chans] += l1[l] * val1.channel[color_chans];
	    PictureValue[color_chans] += l0[lMax-l-1] * val2.channel[color_chans];
	  }
	  else {
	    for (k=0; k<im->channels; k++) {
	      PictureValue[k] += l1[l]        * val1.channel[k];
	      PictureValue[k] += l0[lMax-l-1] * val2.channel[k];
	    }
	  }
	}

	if (has_alpha) {
	  float fa = PictureValue[color_chans] / LanczosWidthFactor;
	  int alpha = minmax(0, 255, fa+0.5);
	  if (alpha) {
	    for (k = 0; k < color_chans; ++k) {
	      psave = (short)(0.5+(PictureValue[k] / LanczosWidthFactor * 255 / fa));
	      val.channel[k]=minmax(0,255,psave);
	    }
	    val.channel[color_chans] = alpha;
	  }
	  else {
	    /* zero alpha, so the pixel has no color */
	    for (k = 0; k < im->channels; ++k)
	      val.channel[k] = 0;
	  }
	}
	else {
	  for(k=0;k<im->channels;k++) {
	    psave = (short)(0.5+(PictureValue[k] / LanczosWidthFactor));
	    val.channel[k]=minmax(0,255,psave);
	  }
	}
	i_ppix(new_img, j, i, &val);
      }
      
    } else {
      
      for (i=0; i<iEnd; i++) {
	for (k=0; k<im->channels; k++) PictureValue[k] = 0.0;
	for (l=0; l < lMax; l++) {
	  i_img_dim mx = T-lMax+l+1;
	  i_img_dim Mx = T+l+1;
	  mx = (mx < 0) ? 0 : mx;
	  Mx = (Mx >= im->ysize) ? im->ysize-1 : Mx;

	  i_gpix(im, i, Mx, &val1);
	  i_gpix(im, i, mx, &val2);
	  if (has_alpha) {
	    i_sample_t alpha1 = val1.channel[color_chans];
	    i_sample_t alpha2 = val2.channel[color_chans];
	    for (k=0; k < color_chans; k++) {
	      PictureValue[k] += l1[l]        * val1.channel[k] * alpha1 / 255;
	      PictureValue[k] += l0[lMax-l-1] * val2.channel[k] * alpha2 / 255;
	    }
	    PictureValue[color_chans] += l1[l] * val1.channel[color_chans];
	    PictureValue[color_chans] += l0[lMax-l-1] * val2.channel[color_chans];
	  }
	  else {
	    for (k=0; k<im->channels; k++) {
	      PictureValue[k] += l1[l]        * val1.channel[k];
	      PictureValue[k] += l0[lMax-l-1] * val2.channel[k];
	    }
	  }
	}
	if (has_alpha) {
	  float fa = PictureValue[color_chans] / LanczosWidthFactor;
	  int alpha = minmax(0, 255, fa+0.5);
	  if (alpha) {
	    for (k = 0; k < color_chans; ++k) {
	      psave = (short)(0.5+(PictureValue[k] / LanczosWidthFactor * 255 / fa));
	      val.channel[k]=minmax(0,255,psave);
	    }
	    val.channel[color_chans] = alpha;
	  }
	  else {
	    for (k = 0; k < im->channels; ++k)
	      val.channel[k] = 0;
	  }
	}
	else {
	  for(k=0;k<im->channels;k++) {
	    psave = (short)(0.5+(PictureValue[k] / LanczosWidthFactor));
	    val.channel[k]=minmax(0,255,psave);
	  }
	}
	i_ppix(new_img, i, j, &val);
      }
      
    }
  }
  myfree(l0);
  myfree(l1);

  im_log((aIMCTX, 1,"(%p) <- i_scaleaxis\n", new_img));

  return new_img;
}


/* 
=item i_scale_nn(im, scx, scy)

Scale by using nearest neighbor 
Both axes scaled at the same time since 
nothing is gained by doing it in two steps 

=cut
*/


i_img*
i_scale_nn(i_img *im, double scx, double scy) {

  i_img_dim nxsize,nysize,nx,ny;
  i_img *new_img;
  i_color val;
  dIMCTXim(im);

  im_log((aIMCTX, 1,"i_scale_nn(im %p,scx %.2f,scy %.2f)\n",im,scx,scy));

  nxsize = (i_img_dim) ((double) im->xsize * scx);
  if (nxsize < 1) {
    nxsize = 1;
    scx = 1.0 / im->xsize;
  }
  nysize = (i_img_dim) ((double) im->ysize * scy);
  if (nysize < 1) {
    nysize = 1;
    scy = 1.0 / im->ysize;
  }
  im_assert(scx != 0 && scy != 0);
    
  new_img=i_img_empty_ch(NULL,nxsize,nysize,im->channels);
  
  for(ny=0;ny<nysize;ny++) for(nx=0;nx<nxsize;nx++) {
    i_gpix(im,((double)nx)/scx,((double)ny)/scy,&val);
    i_ppix(new_img,nx,ny,&val);
  }

  im_log((aIMCTX, 1,"(%p) <- i_scale_nn\n",new_img));

  return new_img;
}

/*
=item i_sametype(C<im>, C<xsize>, C<ysize>)

=category Image creation/destruction
=synopsis i_img *img = i_sametype(src, width, height);

Returns an image of the same type (sample size, channels, paletted/direct).

For paletted images the palette is copied from the source.

=cut
*/

i_img *
i_sametype(i_img *src, i_img_dim xsize, i_img_dim ysize) {
  dIMCTXim(src);

  if (src->type == i_direct_type) {
    if (src->bits == 8) {
      return i_img_empty_ch(NULL, xsize, ysize, src->channels);
    }
    else if (src->bits == i_16_bits) {
      return i_img_16_new(xsize, ysize, src->channels);
    }
    else if (src->bits == i_double_bits) {
      return i_img_double_new(xsize, ysize, src->channels);
    }
    else {
      i_push_error(0, "Unknown image bits");
      return NULL;
    }
  }
  else {
    i_color col;
    int i;

    i_img *targ = i_img_pal_new(xsize, ysize, src->channels, i_maxcolors(src));
    for (i = 0; i < i_colorcount(src); ++i) {
      i_getcolors(src, i, &col, 1);
      i_addcolors(targ, &col, 1);
    }

    return targ;
  }
}

/*
=item i_sametype_chans(C<im>, C<xsize>, C<ysize>, C<channels>)

=category Image creation/destruction
=synopsis i_img *img = i_sametype_chans(src, width, height, channels);

Returns an image of the same type (sample size).

For paletted images the equivalent direct type is returned.

=cut
*/

i_img *
i_sametype_chans(i_img *src, i_img_dim xsize, i_img_dim ysize, int channels) {
  dIMCTXim(src);

  if (src->bits == 8) {
    return i_img_empty_ch(NULL, xsize, ysize, channels);
  }
  else if (src->bits == i_16_bits) {
    return i_img_16_new(xsize, ysize, channels);
  }
  else if (src->bits == i_double_bits) {
    return i_img_double_new(xsize, ysize, channels);
  }
  else {
    i_push_error(0, "Unknown image bits");
    return NULL;
  }
}

/*
=item i_transform(im, opx, opxl, opy, opyl, parm, parmlen)

Spatially transforms I<im> returning a new image.

opx for a length of opxl and opy for a length of opy are arrays of
operators that modify the x and y positions to retreive the pixel data from.

parm and parmlen define extra parameters that the operators may use.

Note that this function is largely superseded by the more flexible
L<transform.c/i_transform2>.

Returns the new image.

The operators for this function are defined in L<stackmach.c>.

=cut
*/
i_img*
i_transform(i_img *im, int *opx,int opxl,int *opy,int opyl,double parm[],int parmlen) {
  double rx,ry;
  i_img_dim nxsize,nysize,nx,ny;
  i_img *new_img;
  i_color val;
  dIMCTXim(im);
  
  im_log((aIMCTX, 1,"i_transform(im %p, opx %p, opxl %d, opy %p, opyl %d, parm %p, parmlen %d)\n",im,opx,opxl,opy,opyl,parm,parmlen));

  nxsize = im->xsize;
  nysize = im->ysize ;
  
  new_img=i_img_empty_ch(NULL,nxsize,nysize,im->channels);
  /*   fprintf(stderr,"parm[2]=%f\n",parm[2]);   */
  for(ny=0;ny<nysize;ny++) for(nx=0;nx<nxsize;nx++) {
    /*     parm[parmlen-2]=(double)nx;
	   parm[parmlen-1]=(double)ny; */

    parm[0]=(double)nx;
    parm[1]=(double)ny;

    /*     fprintf(stderr,"(%d,%d) ->",nx,ny);  */
    rx=i_op_run(opx,opxl,parm,parmlen);
    ry=i_op_run(opy,opyl,parm,parmlen);
    /*    fprintf(stderr,"(%f,%f)\n",rx,ry); */
    i_gpix(im,rx,ry,&val);
    i_ppix(new_img,nx,ny,&val);
  }

  im_log((aIMCTX, 1,"(%p) <- i_transform\n",new_img));
  return new_img;
}

/*
=item i_img_diff(im1, im2)

Calculates the sum of the squares of the differences between
correspoding channels in two images.

If the images are not the same size then only the common area is 
compared, hence even if images are different sizes this function 
can return zero.

=cut
*/

float
i_img_diff(i_img *im1,i_img *im2) {
  i_img_dim x, y, xb, yb;
  int ch, chb;
  float tdiff;
  i_color val1,val2;
  dIMCTXim(im1);

  im_log((aIMCTX, 1,"i_img_diff(im1 %p,im2 %p)\n",im1,im2));

  xb=(im1->xsize<im2->xsize)?im1->xsize:im2->xsize;
  yb=(im1->ysize<im2->ysize)?im1->ysize:im2->ysize;
  chb=(im1->channels<im2->channels)?im1->channels:im2->channels;

  im_log((aIMCTX, 1,"i_img_diff: b=(" i_DFp ") chb=%d\n",
	  i_DFcp(xb,yb), chb));

  tdiff=0;
  for(y=0;y<yb;y++) for(x=0;x<xb;x++) {
    i_gpix(im1,x,y,&val1);
    i_gpix(im2,x,y,&val2);

    for(ch=0;ch<chb;ch++) tdiff+=(val1.channel[ch]-val2.channel[ch])*(val1.channel[ch]-val2.channel[ch]);
  }
  im_log((aIMCTX, 1,"i_img_diff <- (%.2f)\n",tdiff));
  return tdiff;
}

/*
=item i_img_diffd(im1, im2)

Calculates the sum of the squares of the differences between
correspoding channels in two images.

If the images are not the same size then only the common area is 
compared, hence even if images are different sizes this function 
can return zero.

This is like i_img_diff() but looks at floating point samples instead.

=cut
*/

double
i_img_diffd(i_img *im1,i_img *im2) {
  i_img_dim x, y, xb, yb;
  int ch, chb;
  double tdiff;
  i_fcolor val1,val2;
  dIMCTXim(im1);

  im_log((aIMCTX, 1,"i_img_diffd(im1 %p,im2 %p)\n",im1,im2));

  xb=(im1->xsize<im2->xsize)?im1->xsize:im2->xsize;
  yb=(im1->ysize<im2->ysize)?im1->ysize:im2->ysize;
  chb=(im1->channels<im2->channels)?im1->channels:im2->channels;

  im_log((aIMCTX, 1,"i_img_diffd: b(" i_DFp ") chb=%d\n",
	  i_DFcp(xb, yb), chb));

  tdiff=0;
  for(y=0;y<yb;y++) for(x=0;x<xb;x++) {
    i_gpixf(im1,x,y,&val1);
    i_gpixf(im2,x,y,&val2);

    for(ch=0;ch<chb;ch++) {
      double sdiff = val1.channel[ch]-val2.channel[ch];
      tdiff += sdiff * sdiff;
    }
  }
  im_log((aIMCTX, 1,"i_img_diffd <- (%.2f)\n",tdiff));

  return tdiff;
}

int
i_img_samef(i_img *im1,i_img *im2, double epsilon, char const *what) {
  i_img_dim x,y,xb,yb;
  int ch, chb;
  i_fcolor val1,val2;
  dIMCTXim(im1);

  if (what == NULL)
    what = "(null)";

  im_log((aIMCTX,1,"i_img_samef(im1 %p,im2 %p, epsilon %g, what '%s')\n", im1, im2, epsilon, what));

  xb=(im1->xsize<im2->xsize)?im1->xsize:im2->xsize;
  yb=(im1->ysize<im2->ysize)?im1->ysize:im2->ysize;
  chb=(im1->channels<im2->channels)?im1->channels:im2->channels;

  im_log((aIMCTX, 1,"i_img_samef: b(" i_DFp ") chb=%d\n",
	  i_DFcp(xb, yb), chb));

  for(y = 0; y < yb; y++) {
    for(x = 0; x < xb; x++) {
      i_gpixf(im1, x, y, &val1);
      i_gpixf(im2, x, y, &val2);
      
      for(ch = 0; ch < chb; ch++) {
	double sdiff = val1.channel[ch] - val2.channel[ch];
	if (fabs(sdiff) > epsilon) {
	  im_log((aIMCTX, 1,"i_img_samef <- different %g @(" i_DFp ")\n",
		  sdiff, i_DFcp(x, y)));
	  return 0;
	}
      }
    }
  }
  im_log((aIMCTX, 1,"i_img_samef <- same\n"));

  return 1;
}

/* just a tiny demo of haar wavelets */

i_img*
i_haar(i_img *im) {
  i_img_dim mx,my;
  i_img_dim fx,fy;
  i_img_dim x,y;
  int ch;
  i_img *new_img,*new_img2;
  i_color val1,val2,dval1,dval2;
  dIMCTXim(im);
  
  mx=im->xsize;
  my=im->ysize;
  fx=(mx+1)/2;
  fy=(my+1)/2;


  /* horizontal pass */
  
  new_img=i_img_empty_ch(NULL,fx*2,fy*2,im->channels);
  new_img2=i_img_empty_ch(NULL,fx*2,fy*2,im->channels);

  for(y=0;y<my;y++) for(x=0;x<fx;x++) {
    i_gpix(im,x*2,y,&val1);
    i_gpix(im,x*2+1,y,&val2);
    for(ch=0;ch<im->channels;ch++) {
      dval1.channel[ch]=(val1.channel[ch]+val2.channel[ch])/2;
      dval2.channel[ch]=(255+val1.channel[ch]-val2.channel[ch])/2;
    }
    i_ppix(new_img,x,y,&dval1);
    i_ppix(new_img,x+fx,y,&dval2);
  }

  for(y=0;y<fy;y++) for(x=0;x<mx;x++) {
    i_gpix(new_img,x,y*2,&val1);
    i_gpix(new_img,x,y*2+1,&val2);
    for(ch=0;ch<im->channels;ch++) {
      dval1.channel[ch]=(val1.channel[ch]+val2.channel[ch])/2;
      dval2.channel[ch]=(255+val1.channel[ch]-val2.channel[ch])/2;
    }
    i_ppix(new_img2,x,y,&dval1);
    i_ppix(new_img2,x,y+fy,&dval2);
  }

  i_img_destroy(new_img);
  return new_img2;
}

/* 
=item i_count_colors(im, maxc)

returns number of colors or -1 
to indicate that it was more than max colors

=cut
*/
/* This function has been changed and is now faster. It's using
 * i_gsamp instead of i_gpix */
int
i_count_colors(i_img *im,int maxc) {
  struct octt *ct;
  i_img_dim x,y;
  int colorcnt;
  int channels[3];
  int *samp_chans;
  i_sample_t * samp;
  i_img_dim xsize = im->xsize; 
  i_img_dim ysize = im->ysize;
  int samp_cnt = 3 * xsize;

  if (im->channels >= 3) {
    samp_chans = NULL;
  }
  else {
    channels[0] = channels[1] = channels[2] = 0;
    samp_chans = channels;
  }

  ct = octt_new();

  samp = (i_sample_t *) mymalloc( xsize * 3 * sizeof(i_sample_t));

  colorcnt = 0;
  for(y = 0; y < ysize; ) {
      i_gsamp(im, 0, xsize, y++, samp, samp_chans, 3);
      for(x = 0; x < samp_cnt; ) {
          colorcnt += octt_add(ct, samp[x], samp[x+1], samp[x+2]);
          x += 3;
          if (colorcnt > maxc) { 
              octt_delete(ct); 
              return -1; 
          }
      }
  }
  myfree(samp);
  octt_delete(ct);
  return colorcnt;
}

/* sorts the array ra[0..n-1] into increasing order using heapsort algorithm 
 * (adapted from the Numerical Recipes)
 */
/* Needed by get_anonymous_color_histo */
static void
hpsort(unsigned int n, unsigned *ra) {
    unsigned int i,
                 ir,
                 j,
                 l, 
                 rra;

    if (n < 2) return;
    l = n >> 1;
    ir = n - 1;
    for(;;) {
        if (l > 0) {
            rra = ra[--l];
        }
        else {
            rra = ra[ir];
            ra[ir] = ra[0];
            if (--ir == 0) {
                ra[0] = rra;
                break;
            }
        }
        i = l;
        j = 2 * l + 1;
        while (j <= ir) {
            if (j < ir && ra[j] < ra[j+1]) j++;
            if (rra < ra[j]) {
                ra[i] = ra[j];
                i = j;
                j++; j <<= 1; j--;
            }
            else break;
        }
        ra[i] = rra;
    }
}

/* This function constructs an ordered list which represents how much the
 * different colors are used. So for instance (100, 100, 500) means that one
 * color is used for 500 pixels, another for 100 pixels and another for 100
 * pixels. It's tuned for performance. You might not like the way I've hardcoded
 * the maxc ;-) and you might want to change the name... */
/* Uses octt_histo */
int
i_get_anonymous_color_histo(i_img *im, unsigned int **col_usage, int maxc) {
  struct octt *ct;
  i_img_dim x,y;
  int colorcnt;
  unsigned int *col_usage_it;
  i_sample_t * samp;
  int channels[3];
  int *samp_chans;
  
  i_img_dim xsize = im->xsize; 
  i_img_dim ysize = im->ysize;
  int samp_cnt = 3 * xsize;
  ct = octt_new();
  
  samp = (i_sample_t *) mymalloc( xsize * 3 * sizeof(i_sample_t));
  
  if (im->channels >= 3) {
    samp_chans = NULL;
  }
  else {
    channels[0] = channels[1] = channels[2] = 0;
    samp_chans = channels;
  }

  colorcnt = 0;
  for(y = 0; y < ysize; ) {
    i_gsamp(im, 0, xsize, y++, samp, samp_chans, 3);
    for(x = 0; x < samp_cnt; ) {
      colorcnt += octt_add(ct, samp[x], samp[x+1], samp[x+2]);
      x += 3;
      if (colorcnt > maxc) { 
	octt_delete(ct); 
	return -1; 
      }
    }
  }
  myfree(samp);
  /* Now that we know the number of colours... */
  col_usage_it = *col_usage = (unsigned int *) mymalloc(colorcnt * sizeof(unsigned int));
  octt_histo(ct, &col_usage_it);
  hpsort(colorcnt, *col_usage);
  octt_delete(ct);
  return colorcnt;
}

/*
=back

=head2 Image method wrappers

These functions provide i_fsample_t functions in terms of their
i_sample_t versions.

=over

=item i_ppixf_fp(i_img *im, i_img_dim x, i_img_dim y, i_fcolor *pix)

=cut
*/

int i_ppixf_fp(i_img *im, i_img_dim x, i_img_dim y, const i_fcolor *pix) {
  i_color temp;
  int ch;

  for (ch = 0; ch < im->channels; ++ch)
    temp.channel[ch] = SampleFTo8(pix->channel[ch]);
  
  return i_ppix(im, x, y, &temp);
}

/*
=item i_gpixf_fp(i_img *im, i_img_dim x, i_img_dim y, i_fcolor *pix)

=cut
*/
int i_gpixf_fp(i_img *im, i_img_dim x, i_img_dim y, i_fcolor *pix) {
  i_color temp;
  int ch;

  if (i_gpix(im, x, y, &temp) == 0) {
    for (ch = 0; ch < im->channels; ++ch)
      pix->channel[ch] = Sample8ToF(temp.channel[ch]);
    return 0;
  }
  else 
    return -1;
}

/*
=item i_plinf_fp(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_fcolor *pix)

=cut
*/
i_img_dim
i_plinf_fp(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, const i_fcolor *pix) {
  i_color *work;

  if (y >= 0 && y < im->ysize && l < im->xsize && l >= 0) {
    if (r > im->xsize)
      r = im->xsize;
    if (r > l) {
      i_img_dim ret;
      i_img_dim i;
      int ch;
      work = mymalloc(sizeof(i_color) * (r-l));
      for (i = 0; i < r-l; ++i) {
        for (ch = 0; ch < im->channels; ++ch) 
          work[i].channel[ch] = SampleFTo8(pix[i].channel[ch]);
      }
      ret = i_plin(im, l, r, y, work);
      myfree(work);

      return ret;
    }
    else {
      return 0;
    }
  }
  else {
    return 0;
  }
}

/*
=item i_glinf_fp(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_fcolor *pix)

=cut
*/
i_img_dim
i_glinf_fp(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_fcolor *pix) {
  i_color *work;

  if (y >= 0 && y < im->ysize && l < im->xsize && l >= 0) {
    if (r > im->xsize)
      r = im->xsize;
    if (r > l) {
      i_img_dim ret;
      i_img_dim i;
      int ch;
      work = mymalloc(sizeof(i_color) * (r-l));
      ret = i_plin(im, l, r, y, work);
      for (i = 0; i < r-l; ++i) {
        for (ch = 0; ch < im->channels; ++ch) 
          pix[i].channel[ch] = Sample8ToF(work[i].channel[ch]);
      }
      myfree(work);

      return ret;
    }
    else {
      return 0;
    }
  }
  else {
    return 0;
  }
}

/*
=item i_gsampf_fp(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_fsample_t *samp, int *chans, int chan_count)

=cut
*/

i_img_dim
i_gsampf_fp(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_fsample_t *samp, 
                int const *chans, int chan_count) {
  i_sample_t *work;

  if (y >= 0 && y < im->ysize && l < im->xsize && l >= 0) {
    if (r > im->xsize)
      r = im->xsize;
    if (r > l) {
      i_img_dim ret;
      i_img_dim i;
      work = mymalloc(sizeof(i_sample_t) * (r-l));
      ret = i_gsamp(im, l, r, y, work, chans, chan_count);
      for (i = 0; i < ret; ++i) {
          samp[i] = Sample8ToF(work[i]);
      }
      myfree(work);

      return ret;
    }
    else {
      return 0;
    }
  }
  else {
    return 0;
  }
}

/*
=back

=head2 Palette wrapper functions

Used for virtual images, these forward palette calls to a wrapped image, 
assuming the wrapped image is the first pointer in the structure that 
im->ext_data points at.

=over

=item i_addcolors_forward(i_img *im, const i_color *colors, int count)

=cut
*/
int i_addcolors_forward(i_img *im, const i_color *colors, int count) {
  return i_addcolors(*(i_img **)im->ext_data, colors, count);
}

/*
=item i_getcolors_forward(i_img *im, int i, i_color *color, int count)

=cut
*/
int i_getcolors_forward(i_img *im, int i, i_color *color, int count) {
  return i_getcolors(*(i_img **)im->ext_data, i, color, count);
}

/*
=item i_setcolors_forward(i_img *im, int i, const i_color *color, int count)

=cut
*/
int i_setcolors_forward(i_img *im, int i, const i_color *color, int count) {
  return i_setcolors(*(i_img **)im->ext_data, i, color, count);
}

/*
=item i_colorcount_forward(i_img *im)

=cut
*/
int i_colorcount_forward(i_img *im) {
  return i_colorcount(*(i_img **)im->ext_data);
}

/*
=item i_maxcolors_forward(i_img *im)

=cut
*/
int i_maxcolors_forward(i_img *im) {
  return i_maxcolors(*(i_img **)im->ext_data);
}

/*
=item i_findcolor_forward(i_img *im, const i_color *color, i_palidx *entry)

=cut
*/
int i_findcolor_forward(i_img *im, const i_color *color, i_palidx *entry) {
  return i_findcolor(*(i_img **)im->ext_data, color, entry);
}

/*
=back

=head2 Fallback handler

=over

=item i_gsamp_bits_fb

=cut
*/

i_img_dim
i_gsamp_bits_fb(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, unsigned *samps, 
		const int *chans, int chan_count, int bits) {
  dIMCTXim(im);

  if (bits < 1 || bits > 32) {
    i_push_error(0, "Invalid bits, must be 1..32");
    return -1;
  }

  if (y >=0 && y < im->ysize && l < im->xsize && l >= 0) {
    double scale;
    int ch;
    i_img_dim count, i, w;
    
    if (bits == 32)
      scale = 4294967295.0;
    else
      scale = (double)(1 << bits) - 1;

    if (r > im->xsize)
      r = im->xsize;
    w = r - l;
    count = 0;

    if (chans) {
      /* make sure we have good channel numbers */
      for (ch = 0; ch < chan_count; ++ch) {
        if (chans[ch] < 0 || chans[ch] >= im->channels) {
          im_push_errorf(aIMCTX, 0, "No channel %d in this image", chans[ch]);
          return -1;
        }
      }
      for (i = 0; i < w; ++i) {
	i_fcolor c;
	i_gpixf(im, l+i, y, &c);
        for (ch = 0; ch < chan_count; ++ch) {
          *samps++ = (unsigned)(c.channel[ch] * scale + 0.5);
          ++count;
        }
      }
    }
    else {
      if (chan_count <= 0 || chan_count > im->channels) {
	i_push_error(0, "Invalid channel count");
	return -1;
      }
      for (i = 0; i < w; ++i) {
	i_fcolor c;
	i_gpixf(im, l+i, y, &c);
        for (ch = 0; ch < chan_count; ++ch) {
          *samps++ = (unsigned)(c.channel[ch] * scale + 0.5);
          ++count;
        }
      }
    }

    return count;
  }
  else {
    i_push_error(0, "Image position outside of image");
    return -1;
  }
}

struct magic_entry {
  unsigned char *magic;
  size_t magic_size;
  char *name;
  unsigned char *mask;  
};

static int
test_magic(unsigned char *buffer, size_t length, struct magic_entry const *magic) {
  if (length < magic->magic_size)
    return 0;
  if (magic->mask) {
    int i;
    unsigned char *bufp = buffer, 
      *maskp = magic->mask, 
      *magicp = magic->magic;

    for (i = 0; i < magic->magic_size; ++i) {
      int mask = *maskp == 'x' ? 0xFF : *maskp == ' ' ? 0 : *maskp;
      ++maskp;

      if ((*bufp++ & mask) != (*magicp++ & mask)) 
	return 0;
    }

    return 1;
  }
  else {
    return !memcmp(magic->magic, buffer, magic->magic_size);
  }
}

/*
=item i_test_format_probe(io_glue *data, int length)

Check the beginning of the supplied file for a 'magic number'

=cut
*/

#define FORMAT_ENTRY(magic, type) \
  { (unsigned char *)(magic ""), sizeof(magic)-1, type }
#define FORMAT_ENTRY2(magic, type, mask) \
  { (unsigned char *)(magic ""), sizeof(magic)-1, type, (unsigned char *)(mask) }

const char *
i_test_format_probe(io_glue *data, int length) {
  static const struct magic_entry formats[] = {
    FORMAT_ENTRY("\xFF\xD8", "jpeg"),
    FORMAT_ENTRY("GIF87a", "gif"),
    FORMAT_ENTRY("GIF89a", "gif"),
    FORMAT_ENTRY("MM\0*", "tiff"),
    FORMAT_ENTRY("II*\0", "tiff"),
    FORMAT_ENTRY("BM", "bmp"),
    FORMAT_ENTRY("\x89PNG\x0d\x0a\x1a\x0a", "png"),
    FORMAT_ENTRY("P1", "pnm"),
    FORMAT_ENTRY("P2", "pnm"),
    FORMAT_ENTRY("P3", "pnm"),
    FORMAT_ENTRY("P4", "pnm"),
    FORMAT_ENTRY("P5", "pnm"),
    FORMAT_ENTRY("P6", "pnm"),
    FORMAT_ENTRY("/* XPM", "xpm"),
    FORMAT_ENTRY("\x8aMNG", "mng"),
    FORMAT_ENTRY("\x8aJNG", "jng"),
    /* SGI RGB - with various possible parameters to avoid false positives
       on similar files 
       values are: 2 byte magic, rle flags (0 or 1), bytes/sample (1 or 2)
    */
    FORMAT_ENTRY("\x01\xDA\x00\x01", "sgi"),
    FORMAT_ENTRY("\x01\xDA\x00\x02", "sgi"),
    FORMAT_ENTRY("\x01\xDA\x01\x01", "sgi"),
    FORMAT_ENTRY("\x01\xDA\x01\x02", "sgi"),
    
    FORMAT_ENTRY2("FORM    ILBM", "ilbm", "xxxx    xxxx"),

    /* different versions of PCX format 
       http://www.fileformat.info/format/pcx/
    */
    FORMAT_ENTRY("\x0A\x00\x01", "pcx"),
    FORMAT_ENTRY("\x0A\x02\x01", "pcx"),
    FORMAT_ENTRY("\x0A\x03\x01", "pcx"),
    FORMAT_ENTRY("\x0A\x04\x01", "pcx"),
    FORMAT_ENTRY("\x0A\x05\x01", "pcx"),

    /* FITS - http://fits.gsfc.nasa.gov/ */
    FORMAT_ENTRY("SIMPLE  =", "fits"),

    /* PSD - Photoshop */
    FORMAT_ENTRY("8BPS\x00\x01", "psd"),
    
    /* EPS - Encapsulated Postscript */
    /* only reading 18 chars, so we don't include the F in EPSF */
    FORMAT_ENTRY("%!PS-Adobe-2.0 EPS", "eps"),

    /* Utah RLE */
    FORMAT_ENTRY("\x52\xCC", "utah"),

    /* GZIP compressed, only matching deflate for now */
    FORMAT_ENTRY("\x1F\x8B\x08", "gzip"),

    /* bzip2 compressed */
    FORMAT_ENTRY("BZh", "bzip2"),

    /* WEBP
       http://code.google.com/speed/webp/docs/riff_container.html */
    FORMAT_ENTRY2("RIFF    WEBP", "webp", "xxxx    xxxx"),

    /* JPEG 2000 
       This might match a little loosely */
    FORMAT_ENTRY("\x00\x00\x00\x0CjP  \x0D\x0A\x87\x0A", "jp2"),
  };
  static const struct magic_entry more_formats[] = {
    /* these were originally both listed as ico, but cur files can
       include hotspot information */
    FORMAT_ENTRY("\x00\x00\x01\x00", "ico"), /* Windows icon */
    FORMAT_ENTRY("\x00\x00\x02\x00", "cur"), /* Windows cursor */
    FORMAT_ENTRY2("\x00\x00\x00\x00\x00\x00\x00\x07", 
		  "xwd", "    xxxx"), /* X Windows Dump */
  };

  unsigned int i;
  unsigned char head[18];
  ssize_t rc;

  rc = i_io_peekn(data, head, 18);
  if (rc == -1) return NULL;
#if 0
  {
    int i;
    fprintf(stderr, "%d bytes -", (int)rc);
    for (i = 0; i < rc; ++i)
      fprintf(stderr, " %02x", head[i]);
    fprintf(stderr, "\n");
  }
#endif

  for(i=0; i<sizeof(formats)/sizeof(formats[0]); i++) { 
    struct magic_entry const *entry = formats + i;

    if (test_magic(head, rc, entry)) 
      return entry->name;
  }

  if ((rc == 18) &&
      tga_header_verify(head))
    return "tga";

  for(i=0; i<sizeof(more_formats)/sizeof(more_formats[0]); i++) { 
    struct magic_entry const *entry = more_formats + i;

    if (test_magic(head, rc, entry)) 
      return entry->name;
  }

  return NULL;
}

/*
=item i_img_is_monochrome(img, &zero_is_white)

=category Image Information

Tests an image to check it meets our monochrome tests.

The idea is that a file writer can use this to test where it should
write the image in whatever bi-level format it uses, eg. C<pbm> for
C<pnm>.

For performance of encoders we require monochrome images:

=over

=item *

be paletted

=item *

have a palette of two colors, containing only C<(0,0,0)> and
C<(255,255,255)> in either order.

=back

C<zero_is_white> is set to non-zero if the first palette entry is white.

=cut
*/

int
i_img_is_monochrome(i_img *im, int *zero_is_white) {
  if (im->type == i_palette_type
      && i_colorcount(im) == 2) {
    i_color colors[2];
    i_getcolors(im, 0, colors, 2);
    if (im->channels == 3) {
      if (colors[0].rgb.r == 255 && 
          colors[0].rgb.g == 255 &&
          colors[0].rgb.b == 255 &&
          colors[1].rgb.r == 0 &&
          colors[1].rgb.g == 0 &&
          colors[1].rgb.b == 0) {
        *zero_is_white = 1;
        return 1;
      }
      else if (colors[0].rgb.r == 0 && 
               colors[0].rgb.g == 0 &&
               colors[0].rgb.b == 0 &&
               colors[1].rgb.r == 255 &&
               colors[1].rgb.g == 255 &&
               colors[1].rgb.b == 255) {
        *zero_is_white = 0;
        return 1;
      }
    }
    else if (im->channels == 1) {
      if (colors[0].channel[0] == 255 &&
          colors[1].channel[0] == 0) {
        *zero_is_white = 1;
        return 1;
      }
      else if (colors[0].channel[0] == 0 &&
               colors[1].channel[0] == 255) {
        *zero_is_white = 0;
        return 1;         
      }
    }
  }

  *zero_is_white = 0;
  return 0;
}

/*
=item i_get_file_background(im, &bg)

=category Files

Retrieve the file write background color tag from the image.

If not present, C<bg> is set to black.

Returns 1 if the C<i_background> tag was found and valid.

=cut
*/

int
i_get_file_background(i_img *im, i_color *bg) {
  int result = i_tags_get_color(&im->tags, "i_background", 0, bg);
  if (!result) {
    /* black default */
    bg->channel[0] = bg->channel[1] = bg->channel[2] = 0;
  }
  /* always full alpha */
  bg->channel[3] = 255;

  return result;
}

/*
=item i_get_file_backgroundf(im, &bg)

=category Files

Retrieve the file write background color tag from the image as a
floating point color.

Implemented in terms of i_get_file_background().

If not present, C<bg> is set to black.

Returns 1 if the C<i_background> tag was found and valid.

=cut
*/

int
i_get_file_backgroundf(i_img *im, i_fcolor *fbg) {
  i_color bg;
  int result = i_get_file_background(im, &bg);
  fbg->rgba.r = Sample8ToF(bg.rgba.r);
  fbg->rgba.g = Sample8ToF(bg.rgba.g);
  fbg->rgba.b = Sample8ToF(bg.rgba.b);
  fbg->rgba.a = 1.0;

  return result;
}

/*
=back

=head1 AUTHOR

Arnar M. Hrafnkelsson <addi@umich.edu>

Tony Cook <tonyc@cpan.org>

=head1 SEE ALSO

L<Imager>, L<gif.c>

=cut
*/
