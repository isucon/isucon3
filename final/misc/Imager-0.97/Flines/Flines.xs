#define PERL_NO_GET_CONTEXT
#ifdef __cplusplus
extern "C" {
#endif
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#ifdef __cplusplus
}
#endif

#include "imext.h"
#include "imperl.h"

unsigned char
static
saturate(int in) {
  if (in>255) { return 255; }
  else if (in>0) return in;
  return 0;
}

static void
flines(i_img *im) {
  i_color vl;
  i_img_dim x,y;

  for(y = 0; y < im->ysize; y ++) {
    float yf, mf;
    if (!(y%2)) {
      yf = y/(double)im->ysize;
    }
    else {
      yf = (im->ysize-y)/(double)im->ysize;
    }
    mf = 1.2-0.8*yf;

    for(x = 0; x < im->xsize; x ++ ) {
      i_gpix(im,x,y,&vl); 
      vl.rgb.r = saturate(vl.rgb.r*mf);
      vl.rgb.g = saturate(vl.rgb.g*mf);
      vl.rgb.b = saturate(vl.rgb.b*mf);
      i_ppix(im,x,y,&vl);
    }
  }
}


DEFINE_IMAGER_CALLBACKS;

MODULE = Imager::Filter::Flines   PACKAGE = Imager::Filter::Flines

PROTOTYPES: ENABLE

void
flines(im)
        Imager::ImgRaw im

BOOT:
        PERL_INITIALIZE_IMAGER_CALLBACKS;

