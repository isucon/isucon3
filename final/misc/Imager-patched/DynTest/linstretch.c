#include "imext.h"

char evalstr[]="Description string of plugin dyntest - kind of like";

void null_plug(void *ptr) { }

/* Example dynamic filter - level stretch (linear) - note it only stretches and doesn't compress */

/* input parameters
   a: the current black
   b: the current white
   
   0 <= a < b <= 255;

   output pixel value calculated by: o=((i-a)*255)/(b-a);

   note that since we do not have the needed functions to manipulate the data structures *** YET ***
*/


static
unsigned char
saturate(int in) {
  if (in>255) { return 255; }
  else if (in>0) return in;
  return 0;
}

void lin_stretch(i_img *im, int a, int b) {

  i_color rcolor;
  i_img_dim x,y;
  int i;

  
  /*   fprintf(stderr,"parameters: (im 0x%x,a %d,b %d)\n",im,a,b);*/
 
  for(y=0;y<im->ysize;y++) for(x=0;x<im->xsize;x++) {
    i_gpix(im,x,y,&rcolor);
    for(i=0;i<im->channels;i++) rcolor.channel[i]=saturate((255*(rcolor.channel[i]-a))/(b-a));    
    i_ppix(im,x,y,&rcolor);
  }

}


