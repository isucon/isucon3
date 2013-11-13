#include "pluginst.h"
#include <stdio.h>

char evalstr[]="Plugin for creating html tables from images";

/* input parameters
   fname - file to add the html to.

*/



void
html_art(void *INP) {
  i_img *im;
  i_color rcolor;
  i_img_dim x,y;
  FILE *fp;
  char *fname;

  if ( !getSTR("fname",&fname) ) { fprintf(stderr,"Error: filename is missing\n"); return; } 
  if ( !getOBJ("image","Imager::ImgRaw",&im) ) { fprintf(stderr,"Error: image is missing\n"); return; }
  
  printf("parameters: (im %p,fname %s)\n",im,fname); 

  printf("image info:\n size ("i_DFp ")\n channels (%d)\n",
	 i_DFcp(im->xsize, im->ysize), im->channels); 

  fp=fopen(fname,"ab+");
  fprintf(fp,"<TABLE BORDER=\"0\" CELLPADDING=\"0\" CELLSPACING=\"0\">");
  for(y=0;y<im->ysize;y+=2) {
    fprintf(fp,"<TR>");
     for(x=0;x<im->xsize;x++) {
      i_gpix(im,x,y,&rcolor);
      fprintf(fp,"<TD BGCOLOR=\"#%02X%02X%02X\">&nbsp;&nbsp;</TD>",rcolor.rgb.r,rcolor.rgb.g,rcolor.rgb.b);
    }
    fprintf(fp,"</TR>"); 
  }
  fprintf(fp,"</TABLE>");
  fclose(fp);
}

func_ptr function_list[]={
  {
    "html_art",
    html_art,
    "callseq => ['image','fname'], \
    callsub => sub { my %hsh=@_; DSO_call($DSO_handle,0,\\%hsh); } \
    "
  },
  {NULL,NULL,NULL}};


/* Remember to double backslash backslashes within Double quotes in C */
