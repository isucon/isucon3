#include "pluginst.h"
#include <stdlib.h>

char evalstr[]="Mandlebrot renderer";

/* Example Mandlebrot generator */

/* input parameters
   image is the image object.
*/


#define MXITER 256

static
int
mandel(double x, double y) {
  double xn, yn;
  double xo, yo;
  int iter = 1;
  /*	Z(n+1) = Z(n) ^2 + c */

  /* printf("(%.2f, %.2f) -> \n", x,y);   */

  xo = x;
  yo = y;

  while( xo*xo+yo*yo <= 10 && iter < MXITER) {
    xn = xo*xo-yo*yo + x;
    yn = 2*xo*yo     + y;
    xo=xn;
    yo=yn;
    iter++;
  }
  return (iter == MXITER)?0:iter;
}



void mandlebrot(void *INP) {

  i_img *im;
  int i;
  i_img_dim x,y;
  int idx;
  
  double xs, ys;
  double div;

  i_color icl[256];
  srand(12235);
  for(i=1;i<256; i++) {
    icl[i].rgb.r = 100+(int) (155.0*rand()/(RAND_MAX+1.0));
    icl[i].rgb.g = 100+(int) (155.0*rand()/(RAND_MAX+1.0));
    icl[i].rgb.g = 100+(int) (155.0*rand()/(RAND_MAX+1.0));
  }

  icl[0].rgb.r = 0;
  icl[0].rgb.g = 0;
  icl[0].rgb.g = 0;
    

  
  if ( !getOBJ("image","Imager::ImgRaw",&im) ) { fprintf(stderr,"Error: image is missing\n"); }
  
  fprintf(stderr,"mandlebrot: parameters: (im %p)\n",im);

  fprintf(stderr, "mandlebrot: image info:\n size (" i_DFp ")\n channels (%d)\n",
	  i_DFcp(im->xsize,im->ysize),im->channels); 
  div = 2.5;

  xs = 0.8*div;
  ys = 0.5*div;
  
  div /= im->xsize;


  fprintf(stderr, "Divider: %f \n", div);
  for(y = 0; y < im->ysize; y ++) {
    for(x = 0; x < im->xsize; x ++ ) {
      idx = mandel(x*div-xs , y*div-ys);
      idx = (idx>255)?255:idx;
      i_ppix(im,x,y,&icl[idx]); 
    }
  }
}



func_ptr function_list[]={
  {
    "mandlebrot",
    mandlebrot,
    "callseq => ['image'], \
    callsub => sub { my %hsh=@_; DSO_call($DSO_handle,0,\\%hsh); } \
    "
  },
  {NULL,NULL,NULL}};


/* Remember to double backslash backslashes within Double quotes in C */

