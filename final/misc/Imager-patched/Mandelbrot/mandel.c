#include "imext.h"
#include <stdlib.h>

char evalstr[]="Mandlebrot renderer";

/* Example Mandlebrot generator */

/* input parameters
   image is the image object.
*/


static
int
mandel(double x, double y, int max_iter) {
  double xn, yn;
  double xo, yo;
  int iter = 1;
  /*	Z(n+1) = Z(n) ^2 + c */

  /* printf("(%.2f, %.2f) -> \n", x,y);   */

  xo = x;
  yo = y;

  while( xo*xo+yo*yo <= 10 && iter < max_iter) {
    xn = xo*xo-yo*yo + x;
    yn = 2*xo*yo     + y;
    xo=xn;
    yo=yn;
    iter++;
  }
  return (iter == max_iter)?0:iter;
}

void 
mandelbrot(i_img *im, double minx, double miny, double maxx, double maxy, int max_iter) {

  int i;
  i_img_dim x,y;
  int idx;
  double divx, divy;

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
    
  if (maxx <= minx)
    maxx = minx + 1.0;
  if (maxy <= miny)
    maxy = miny + 1.0;

  divx = (maxx - minx) / im->xsize;
  divy = (maxy - miny) / im->ysize;

  for(y = 0; y < im->ysize; y ++) {
    for(x = 0; x < im->xsize; x ++ ) {
      idx = mandel(minx + x*divx , miny + y*divy, max_iter);
      idx = idx % 256;
      i_ppix(im,x,y,&icl[idx]); 
    }
  }
}
