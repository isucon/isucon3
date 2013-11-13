#include "imager.h"
#include <stdio.h>
#include "iolayer.h"
#ifndef _MSC_VER
#include <unistd.h>
#endif
#include <string.h>
#include <errno.h>



/*

 Image loader for raw files.

 This is a barebones raw loader...

             fd: filedescriptor
              x: xsize
              y: ysize
   datachannels: the number of channels the file contains
  storechannels: the bitmap of channels we will read
          intrl: interlace flag,
                       0 = sample interleaving
                       1 = line interleaving
                       2 = image interleaving (not implemented)

*/

static
void
interleave(unsigned char *inbuffer,unsigned char *outbuffer,i_img_dim rowsize,int channels) {
  i_img_dim ind,i;
  int ch;
  i=0;
  if (inbuffer == outbuffer) return; /* Check if data is already in interleaved format */
  for (ind=0; ind<rowsize; ind++) 
    for (ch=0; ch<channels; ch++) 
      outbuffer[i++] = inbuffer[rowsize*ch+ind]; 
}

static
void
expandchannels(unsigned char *inbuffer, unsigned char *outbuffer, 
	       i_img_dim xsize, int datachannels, int storechannels) {
  i_img_dim x;
  int ch;
  int copy_chans = storechannels > datachannels ? datachannels : storechannels;
  if (inbuffer == outbuffer)
    return; /* Check if data is already in expanded format */
  for(x = 0; x < xsize; x++) {
    for (ch = 0; ch < copy_chans; ch++) 
      outbuffer[x*storechannels+ch] = inbuffer[x*datachannels+ch];
    for (; ch < storechannels; ch++)
      outbuffer[x*storechannels+ch] = 0;
  }
}

i_img *
i_readraw_wiol(io_glue *ig, i_img_dim x, i_img_dim y, int datachannels, int storechannels, int intrl) {
  i_img* im;
  ssize_t rc;
  i_img_dim k;

  unsigned char *inbuffer;
  unsigned char *ilbuffer;
  unsigned char *exbuffer;
  
  size_t inbuflen,ilbuflen,exbuflen;

  i_clear_error();
  
  mm_log((1, "i_readraw(ig %p,x %" i_DF ",y %" i_DF ",datachannels %d,storechannels %d,intrl %d)\n",
	  ig, i_DFc(x), i_DFc(y), datachannels, storechannels, intrl));

  if (intrl != 0 && intrl != 1) {
    i_push_error(0, "raw_interleave must be 0 or 1");
    return NULL;
  }
  if (storechannels < 1 || storechannels > 4) {
    i_push_error(0, "raw_storechannels must be between 1 and 4");
    return NULL;
  }
  
  im = i_img_empty_ch(NULL,x,y,storechannels);
  if (!im)
    return NULL;
  
  inbuflen = im->xsize*datachannels;
  ilbuflen = inbuflen;
  exbuflen = im->xsize*storechannels;
  inbuffer = (unsigned char*)mymalloc(inbuflen);
  mm_log((1,"inbuflen: %ld, ilbuflen: %ld, exbuflen: %ld.\n",
	  (long)inbuflen, (long)ilbuflen, (long)exbuflen));

  if (intrl==0) ilbuffer = inbuffer; 
  else ilbuffer=mymalloc(inbuflen);

  if (datachannels==storechannels) exbuffer=ilbuffer; 
  else exbuffer= mymalloc(exbuflen);
  
  k=0;
  while( k<im->ysize ) {
    rc = i_io_read(ig, inbuffer, inbuflen);
    if (rc != inbuflen) { 
      if (rc < 0)
	i_push_error(0, "error reading file");
      else
	i_push_error(0, "premature end of file");
      i_img_destroy(im);
      myfree(inbuffer);
      if (intrl != 0) myfree(ilbuffer);
      if (datachannels != storechannels) myfree(exbuffer);
      return NULL;
    }
    interleave(inbuffer,ilbuffer,im->xsize,datachannels);
    expandchannels(ilbuffer,exbuffer,im->xsize,datachannels,storechannels);
    /* FIXME: Do we ever want to save to a virtual image? */
    memcpy(&(im->idata[im->xsize*storechannels*k]),exbuffer,exbuflen);
    k++;
  }

  myfree(inbuffer);
  if (intrl != 0) myfree(ilbuffer);
  if (datachannels != storechannels) myfree(exbuffer);

  i_tags_add(&im->tags, "i_format", 0, "raw", -1, 0);

  return im;
}



undef_int
i_writeraw_wiol(i_img* im, io_glue *ig) {
  ssize_t rc;

  i_clear_error();
  mm_log((1,"writeraw(im %p,ig %p)\n", im, ig));
  
  if (im == NULL) { mm_log((1,"Image is empty\n")); return(0); }
  if (!im->virtual) {
    rc = i_io_write(ig,im->idata,im->bytes);
    if (rc != im->bytes) { 
      i_push_error(errno, "Could not write to file");
      mm_log((1,"i_writeraw: Couldn't write to file\n")); 
      return(0);
    }
  } else {
    if (im->type == i_direct_type) {
      /* just save it as 8-bits, maybe support saving higher bit count
         raw images later */
      size_t line_size = im->xsize * im->channels;
      unsigned char *data = mymalloc(line_size);

      i_img_dim y = 0;
      rc = line_size;
      while (rc == line_size && y < im->ysize) {
	i_gsamp(im, 0, im->xsize, y, data, NULL, im->channels);
	rc = i_io_write(ig, data, line_size);
	++y;
      }
      if (rc != line_size) {
        i_push_error(errno, "write error");
        return 0;
      }
      myfree(data);
    } else {
      /* paletted image - assumes the caller puts the palette somewhere 
         else
      */
      size_t line_size = sizeof(i_palidx) * im->xsize;
      i_palidx *data = mymalloc(sizeof(i_palidx) * im->xsize);

      i_img_dim y = 0;
      rc = line_size;
      while (rc == line_size && y < im->ysize) {
	i_gpal(im, 0, im->xsize, y, data);
	rc = i_io_write(ig, data, line_size);
	++y;
      }
      myfree(data);
      if (rc != line_size) {
        i_push_error(errno, "write error");
        return 0;
      }
    }
  }

  if (i_io_close(ig))
    return 0;

  return(1);
}
