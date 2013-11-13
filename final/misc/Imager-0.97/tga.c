#include "imageri.h"
#include "log.h"
#include "iolayer.h"

#include <stdlib.h>
#include <errno.h>


/*
=head1 NAME

tga.c - implements reading and writing targa files, uses io layer.

=head1 SYNOPSIS

   io_glue *ig = io_new_fd( fd );
   i_img *im   = i_readtga_wiol(ig, -1); // no limit on how much is read
   // or 
   io_glue *ig = io_new_fd( fd );
   return_code = i_writetga_wiol(im, ig); 

=head1 DESCRIPTION

tga.c implements the basic functions to read and write portable targa
files.  It uses the iolayer and needs either a seekable source or an
entire memory mapped buffer.

=head1 FUNCTION REFERENCE

Some of these functions are internal.

=over

=cut
*/




typedef struct {
  unsigned char  idlength;
  char  colourmaptype;
  char  datatypecode;
  short int colourmaporigin;
  short int colourmaplength;
  char  colourmapdepth;
  short int x_origin;
  short int y_origin;
  int width;
  int height;
  char  bitsperpixel;
  char  imagedescriptor;
} tga_header;


typedef enum { NoInit, Raw, Rle } rle_state;

typedef struct {
  int compressed;
  size_t bytepp;
  rle_state state;
  unsigned char cval[4];
  int len;
  unsigned char hdr;
  io_glue *ig;
} tga_source;


typedef struct {
  int compressed;
  int bytepp;
  io_glue *ig;
} tga_dest;

#define TGA_MAX_DIM 0xFFFF

/*
=item bpp_to_bytes(bpp)

Convert bits per pixel into bytes per pixel

   bpp - bits per pixel

=cut
*/


static
size_t
bpp_to_bytes(unsigned int bpp) {
  switch (bpp) {
  case 8:
    return 1;
  case 15:
  case 16:
    return 2;
  case 24:
    return 3;
  case 32:
    return 4;
  }
  return 0;
}



/*
=item bpp_to_channels(bpp)

Convert bits per pixel and the number of attribute bits into channels
in the image

   bpp - bits per pixel
   attr_bit_count - number of attribute bits

=cut
*/

static
int
bpp_to_channels(unsigned int bpp, int attr_bit_count) {
  switch (bpp) {
  case 8:
    return 1;
  case 16:
    if (attr_bit_count == 1)
      return 4;
  case 15:
    return 3;
  case 32:
    if (attr_bit_count == 8)
      return 4;
  case 24:
    return 3;
  }
  return 0;
}



/* 
 * Packing functions - used for (un)packing
 * datastructures into raw bytes.
 */


/*
=item color_unpack(buf, bytepp, val)

Unpacks bytes into colour structures, for 2 byte type the first byte
coming from the file will actually be GGGBBBBB, and the second will be
ARRRRRGG.  "A" represents an attribute bit.  The 3 byte entry contains
1 byte each of blue, green, and red.  The 4 byte entry contains 1 byte
each of blue, green, red, and attribute.

   buf - pointer to data
   bytepp - bytes per pixel
   val - pointer to color to store to

=cut
*/

static
void
color_unpack(unsigned char *buf, int bytepp, i_color *val) {
  switch (bytepp) {
  case 1:
    val->gray.gray_color = buf[0];
    break;
  case 2:
    val->rgba.r = (buf[1] & 0x7c) << 1;
    val->rgba.g = ((buf[1] & 0x03) << 6) | ((buf[0] & 0xe0) >> 2);
    val->rgba.b = (buf[0] & 0x1f) << 3;
    val->rgba.a = (buf[1] & 0x80) ? 0 : 255;
    val->rgba.r |= val->rgba.r >> 5;
    val->rgba.g |= val->rgba.g >> 5;
    val->rgba.b |= val->rgba.b >> 5;
    break;
  case 3:
    val->rgb.b = buf[0];
    val->rgb.g = buf[1];
    val->rgb.r = buf[2];
    break;
  case 4:
    val->rgba.b = buf[0];
    val->rgba.g = buf[1];
    val->rgba.r = buf[2];
    val->rgba.a = buf[3];
    break;
  }
}



/*
=item color_pack

Packs a colour into an array of bytes, for 2 byte type the first byte
will be GGGBBBBB, and the second will be ARRRRRGG.  "A" represents an
attribute bit.  The 3 byte entry contains 1 byte each of blue, green,
and red.  The 4 byte entry contains 1 byte each of blue, green, red,
and attribute.

    buf - destination buffer
    bitspp - bits per pixel
    val - color to pack

=cut
*/

static
void
color_pack(unsigned char *buf, int bitspp, i_color *val) {
  switch (bitspp) {
  case 8:
    buf[0] = val->gray.gray_color;
    break;
  case 16:
    buf[0]  = (val->rgba.b >> 3);
    buf[0] |= (val->rgba.g & 0x38) << 2;
    buf[1]  = (val->rgba.r & 0xf8)>> 1;
    buf[1] |= (val->rgba.g >> 6);
    buf[1] |=  val->rgba.a > 0x7f ? 0 : 0x80;
    break;
  case 15:
    buf[0]  = (val->rgba.b >> 3);
    buf[0] |= (val->rgba.g & 0x38) << 2;
    buf[1]  = (val->rgba.r & 0xf8)>> 1;
    buf[1] |= (val->rgba.g >> 6);
    break;
  case 24:
    buf[0] = val->rgb.b;
    buf[1] = val->rgb.g;
    buf[2] = val->rgb.r;
    break;
  case 32:
    buf[0] = val->rgba.b;
    buf[1] = val->rgba.g;
    buf[2] = val->rgba.r;
    buf[3] = val->rgba.a;
    break;
  }
}


/*
=item find_repeat

Helper function for rle compressor to find the next triple repeat of the 
same pixel value in buffer.

    buf - buffer
    length - number of pixel values in buffer
    bytepp - number of bytes in a pixel value

=cut
*/

static
int
find_repeat(unsigned char *buf, int length, int bytepp) {
  int i = 0;
  
  while(i<length-1) {
    if(memcmp(buf+i*bytepp, buf+(i+1)*bytepp, bytepp) == 0) {
      if (i == length-2) return -1;
      if (memcmp(buf+(i+1)*bytepp, buf+(i+2)*bytepp,bytepp) == 0)  
	return i;
      else i++;
    }
    i++;
  }
  return -1;
}


/*
=item find_span

Helper function for rle compressor to find the length of a span where
the same pixel value is in the buffer.

    buf - buffer
    length - number of pixel values in buffer
    bytepp - number of bytes in a pixel value

=cut
*/

static
int
find_span(unsigned char *buf, int length, int bytepp) {
  int i = 0;
  while(i<length) {
    if(memcmp(buf, buf+(i*bytepp), bytepp) != 0) return i;
    i++;
  }
  return length;
}


/*
=item tga_header_unpack(header, headbuf)

Unpacks the header structure into from buffer and stores
in the header structure.

    header - header structure
    headbuf - buffer to unpack from

=cut
*/

static
void
tga_header_unpack(tga_header *header, unsigned char headbuf[18]) {
  header->idlength        = headbuf[0];
  header->colourmaptype   = headbuf[1];
  header->datatypecode    = headbuf[2];
  header->colourmaporigin = (headbuf[4] << 8) + headbuf[3];
  header->colourmaplength = (headbuf[6] << 8) + headbuf[5];
  header->colourmapdepth  = headbuf[7];
  header->x_origin        = (headbuf[9] << 8) + headbuf[8];
  header->y_origin        = (headbuf[11] << 8) + headbuf[10];
  header->width           = (headbuf[13] << 8) + headbuf[12];
  header->height          = (headbuf[15] << 8) + headbuf[14];
  header->bitsperpixel    = headbuf[16];
  header->imagedescriptor = headbuf[17];
}


/* this function should never produce diagnostics to stdout, maybe to the logfile */
int
tga_header_verify(unsigned char headbuf[18]) {
  tga_header header;
  tga_header_unpack(&header, headbuf);
  switch (header.datatypecode) { 
  default:
    /*printf("bad typecode!\n");*/
    return 0;
  case 1:  /* Uncompressed, color-mapped images */ 
  case 3:  /* Uncompressed, grayscale images    */ 
  case 9:  /* Compressed,   color-mapped images */ 
  case 11: /* Compressed,   grayscale images    */ 
    if (header.bitsperpixel != 8)
      return 0;
    break;
  case 0:
  case 2:  /* Uncompressed, rgb images          */ 
  case 10: /* Compressed,   rgb images          */ 
    if (header.bitsperpixel != 15 && header.bitsperpixel != 16
	&& header.bitsperpixel != 24 && header.bitsperpixel != 32)
      return 0;
    break;
	}

  switch (header.colourmaptype) { 
  default:
    /*printf("bad colourmaptype!\n");*/
    return 0;
  case 1:
    if (header.datatypecode != 1 && header.datatypecode != 9)
      return 0; /* only get a color map on a color mapped image */
  case 0:
  	break;
	}

  switch (header.colourmapdepth) {
  default:
    return 0;
  case 0: /* can be 0 if no colour map */
  case 15:
  case 16:
  case 24:
  case 32:
    break;
  }
  
  return 1;
}


/*
=item tga_header_pack(header, headbuf)

Packs header structure into buffer for writing.

    header - header structure
    headbuf - buffer to pack into

=cut
*/

static
void
tga_header_pack(tga_header *header, unsigned char headbuf[18]) {
  headbuf[0] = header->idlength;
  headbuf[1] = header->colourmaptype;
  headbuf[2] = header->datatypecode;
  headbuf[3] = header->colourmaporigin & 0xff;
  headbuf[4] = header->colourmaporigin >> 8;
  headbuf[5] = header->colourmaplength & 0xff;
  headbuf[6] = header->colourmaplength >> 8;
  headbuf[7] = header->colourmapdepth;
  headbuf[8] = header->x_origin & 0xff;
  headbuf[9] = header->x_origin >> 8;
  headbuf[10] = header->y_origin & 0xff;
  headbuf[11] = header->y_origin >> 8;
  headbuf[12] = header->width & 0xff;
  headbuf[13] = header->width >> 8;
  headbuf[14] = header->height & 0xff;
  headbuf[15] = header->height >> 8;
  headbuf[16] = header->bitsperpixel;
  headbuf[17] = header->imagedescriptor;
}


/*
=item tga_source_read(s, buf, pixels)

Reads pixel number of pixels from source s into buffer buf.  Takes
care of decompressing the stream if needed.

    s - data source 
    buf - destination buffer
    pixels - number of pixels to put into buffer

=cut
*/

static
int
tga_source_read(tga_source *s, unsigned char *buf, size_t pixels) {
  int cp = 0, j, k;
  if (!s->compressed) {
    if (i_io_read(s->ig, buf, pixels*s->bytepp) != pixels*s->bytepp) return 0;
    return 1;
  }
  
  while(cp < pixels) {
    int ml;
    if (s->len == 0) s->state = NoInit;
    switch (s->state) {
    case NoInit:
      if (i_io_read(s->ig, &s->hdr, 1) != 1) return 0;

      s->len = (s->hdr &~(1<<7))+1;
      s->state = (s->hdr & (1<<7)) ? Rle : Raw;
      {
/*
	static cnt = 0;
	printf("%04d %s: %d\n", cnt++, s->state==Rle?"RLE":"RAW", s->len);
 */
     }
      if (s->state == Rle && i_io_read(s->ig, s->cval, s->bytepp) != s->bytepp) return 0;

      break;
    case Rle:
      ml = i_min(s->len, pixels-cp);
      for(k=0; k<ml; k++) for(j=0; j<s->bytepp; j++) 
	buf[(cp+k)*s->bytepp+j] = s->cval[j];
      cp     += ml;
      s->len -= ml;
      break;
    case Raw:
      ml = i_min(s->len, pixels-cp);
      if (i_io_read(s->ig, buf+cp*s->bytepp, ml*s->bytepp) != ml*s->bytepp) return 0;
      cp     += ml;
      s->len -= ml;
      break;
    }
  }
  return 1;
}




/*
=item tga_dest_write(s, buf, pixels)

Writes pixels from buf to destination s.  Takes care of compressing if the
destination is compressed.

    s - data destination
    buf - source buffer
    pixels - number of pixels to put write to destination

=cut
*/

static
int
tga_dest_write(tga_dest *s, unsigned char *buf, size_t pixels) {
  int cp = 0;

  if (!s->compressed) {
    if (i_io_write(s->ig, buf, pixels*s->bytepp) != pixels*s->bytepp) return 0;
    return 1;
  }
  
  while(cp < pixels) {
    int tlen;
    int nxtrip = find_repeat(buf+cp*s->bytepp, pixels-cp, s->bytepp);
    tlen = (nxtrip == -1) ? pixels-cp : nxtrip;
    while(tlen) {
      unsigned char clen = (tlen>128) ? 128 : tlen;
      clen--;
      if (i_io_write(s->ig, &clen, 1) != 1) return 0;
      clen++;
      if (i_io_write(s->ig, buf+cp*s->bytepp, clen*s->bytepp) != clen*s->bytepp) return 0;
      tlen -= clen;
      cp += clen;
    }
    if (cp >= pixels) break;
    tlen = find_span(buf+cp*s->bytepp, pixels-cp, s->bytepp);
    if (tlen <3) continue;
    while (tlen) {
      unsigned char clen = (tlen>128) ? 128 : tlen;
      clen = (clen - 1) | 0x80;
      if (i_io_write(s->ig, &clen, 1) != 1) return 0;
      clen = (clen & ~0x80) + 1;
      if (i_io_write(s->ig, buf+cp*s->bytepp, s->bytepp) != s->bytepp) return 0;
      tlen -= clen;
      cp += clen;
    }
  }
  return 1;
}






/*
=item tga_palette_read(ig, img, bytepp, colourmaplength)

Reads the colormap from a tga file and stores in the paletted image
structure.

    ig - iolayer data source
    img - image structure
    bytepp - bytes per pixel
    colourmaplength - number of colours in colourmap

=cut
*/

static
int
tga_palette_read(io_glue *ig, i_img *img, int bytepp, int colourmaplength) {
  int i;
  size_t palbsize;
  unsigned char *palbuf;
  i_color val;

  palbsize = colourmaplength*bytepp;
  palbuf   = mymalloc(palbsize);
  
  if (i_io_read(ig, palbuf, palbsize) != palbsize) {
    i_push_error(errno, "could not read targa colourmap");
    return 0;
  }
  
  /* populate the palette of the new image */
  for(i=0; i<colourmaplength; i++) {
    color_unpack(palbuf+i*bytepp, bytepp, &val);
    i_addcolors(img, &val, 1);
  }
  myfree(palbuf);
  return 1;
}


/*
=item tga_palette_write(ig, img, bitspp, colourmaplength)

Stores the colormap of an image in the destination ig.

    ig - iolayer data source
    img - image structure
    bitspp - bits per pixel in colourmap
    colourmaplength - number of colours in colourmap

=cut
*/

static
int
tga_palette_write(io_glue *ig, i_img *img, int bitspp, int colourmaplength) {
  int i;
  size_t bytepp = bpp_to_bytes(bitspp);
  size_t palbsize = i_colorcount(img)*bytepp;
  unsigned char *palbuf = mymalloc(palbsize);
  
  for(i=0; i<colourmaplength; i++) {
    i_color val;
    i_getcolors(img, i, &val, 1);
    color_pack(palbuf+i*bytepp, bitspp, &val);
  }
  
  if (i_io_write(ig, palbuf, palbsize) != palbsize) {
    i_push_error(errno, "could not write targa colourmap");
    return 0;
  }
  myfree(palbuf);
  return 1;
}



/*
=item i_readtga_wiol(ig, length)

Read in an image from the iolayer data source and return the image structure to it.
Returns NULL on error.

   ig     - io_glue object
   length - maximum length to read from data source, before closing it -1 
            signifies no limit.

=cut
*/

i_img *
i_readtga_wiol(io_glue *ig, int length) {
  i_img* img = NULL;
  int x, y;
  int width, height, channels;
  int mapped;
  char *idstring = NULL;

  tga_source src;
  tga_header header;
  unsigned char headbuf[18];
  unsigned char *databuf;

  i_color *linebuf = NULL;
  i_clear_error();

  mm_log((1,"i_readtga(ig %p, length %d)\n", ig, length));
  
  if (i_io_read(ig, &headbuf, 18) != 18) {
    i_push_error(errno, "could not read targa header");
    return NULL;
  }

  tga_header_unpack(&header, headbuf);

  mm_log((1,"Id length:         %d\n",header.idlength));
  mm_log((1,"Colour map type:   %d\n",header.colourmaptype));
  mm_log((1,"Image type:        %d\n",header.datatypecode));
  mm_log((1,"Colour map offset: %d\n",header.colourmaporigin));
  mm_log((1,"Colour map length: %d\n",header.colourmaplength));
  mm_log((1,"Colour map depth:  %d\n",header.colourmapdepth));
  mm_log((1,"X origin:          %d\n",header.x_origin));
  mm_log((1,"Y origin:          %d\n",header.y_origin));
  mm_log((1,"Width:             %d\n",header.width));
  mm_log((1,"Height:            %d\n",header.height));
  mm_log((1,"Bits per pixel:    %d\n",header.bitsperpixel));
  mm_log((1,"Descriptor:        %d\n",header.imagedescriptor));

  if (header.idlength) {
    /* max of 256, so this is safe */
    idstring = mymalloc(header.idlength+1);
    if (i_io_read(ig, idstring, header.idlength) != header.idlength) {
      i_push_error(errno, "short read on targa idstring");
      return NULL;
    }
  }

  width = header.width;
  height = header.height;

  
  /* Set tags here */
  
  switch (header.datatypecode) {
  case 0: /* No data in image */
    i_push_error(0, "Targa image contains no image data");
    if (idstring) myfree(idstring);
    return NULL;
    break;
  case 1:  /* Uncompressed, color-mapped images */
  case 9:  /* Compressed,   color-mapped images */
  case 3:  /* Uncompressed, grayscale images    */
  case 11: /* Compressed,   grayscale images    */
    if (header.bitsperpixel != 8) {
      i_push_error(0, "Targa: mapped/grayscale image's bpp is not 8, unsupported.");
      if (idstring) myfree(idstring);
      return NULL;
    }
    src.bytepp = 1;
    break;
  case 2:  /* Uncompressed, rgb images          */
  case 10: /* Compressed,   rgb images          */
    if ((src.bytepp = bpp_to_bytes(header.bitsperpixel)))
      break;
    i_push_error(0, "Targa: direct color image's bpp is not 15/16/24/32 - unsupported.");
    if (idstring) myfree(idstring);
    return NULL;
    break;
  case 32: /* Compressed color-mapped, Huffman, Delta and runlength */
  case 33: /* Compressed color-mapped, Huffman, Delta and runlength */
    i_push_error(0, "Unsupported Targa (Huffman/delta/rle/quadtree) subformat is not supported");
    if (idstring) myfree(idstring);
    return NULL;
    break;
  default: /* All others which we don't know which might be */
    i_push_error(0, "Unknown targa format");
    if (idstring) myfree(idstring);
    return NULL;
    break;
  }
  
  src.state = NoInit;
  src.len = 0;
  src.ig = ig;
  src.compressed = !!(header.datatypecode & (1<<3));

  /* Determine number of channels */
  
  mapped = 1;
  switch (header.datatypecode) {
  case 2:  /* Uncompressed, rgb images          */
  case 10: /* Compressed,   rgb images          */
    mapped = 0;
  case 1:  /* Uncompressed, color-mapped images */
  case 9:  /* Compressed,   color-mapped images */
    if ((channels = bpp_to_channels(mapped ? 
				   header.colourmapdepth : 
				   header.bitsperpixel,
				    header.imagedescriptor & 0xF))) break;
    i_push_error(0, "Targa Image has none of 15/16/24/32 pixel layout");
    if (idstring) myfree(idstring);
    return NULL;
    break;
  case 3:  /* Uncompressed, grayscale images    */
  case 11: /* Compressed,   grayscale images    */
    mapped = 0;
    channels = 1;
    break;
  default:
    i_push_error(0, "invalid or unsupported datatype code");
    return NULL;
  }

  if (!i_int_check_image_file_limits(width, height, channels, 
				     sizeof(i_sample_t))) {
    mm_log((1, "i_readtga_wiol: image size exceeds limits\n"));
    return NULL;
  }
  
  img = mapped ? 
    i_img_pal_new(width, height, channels, 256) :
    i_img_empty_ch(NULL, width, height, channels);

  if (!img) {
    if (idstring) 
      myfree(idstring);
    return NULL;
  }
  
  if (idstring) {
    i_tags_add(&img->tags, "tga_idstring", 0, idstring, header.idlength, 0);
    myfree(idstring);
  }

  if (mapped &&
      !tga_palette_read(ig,
			img,
			bpp_to_bytes(header.colourmapdepth),
			header.colourmaplength)
      ) {
    i_push_error(0, "Targa Image has none of 15/16/24/32 pixel layout");
    if (idstring) myfree(idstring);
    if (img) i_img_destroy(img);
    return NULL;
  }
  
  /* Allocate buffers */
  /* width is max 0xffff, src.bytepp is max 4, so this is safe */
  databuf = mymalloc(width*src.bytepp);
  /* similarly here */
  if (!mapped) linebuf = mymalloc(width*sizeof(i_color));
  
  for(y=0; y<height; y++) {
    if (!tga_source_read(&src, databuf, width)) {
      i_push_error(errno, "read for targa data failed");
      if (linebuf) myfree(linebuf);
      myfree(databuf);
      if (img) i_img_destroy(img);
      return NULL;
    }
    if (mapped && header.colourmaporigin) for(x=0; x<width; x++) databuf[x] -= header.colourmaporigin;
    if (mapped) i_ppal(img, 0, width, header.imagedescriptor & (1<<5) ? y : height-1-y, databuf);
    else {
      for(x=0; x<width; x++) color_unpack(databuf+x*src.bytepp, src.bytepp, linebuf+x);
      i_plin(img, 0, width, header.imagedescriptor & (1<<5) ? y : height-1-y, linebuf);
    }
  }
  myfree(databuf);
  if (linebuf) myfree(linebuf);
  
  i_tags_add(&img->tags, "i_format", 0, "tga", -1, 0);
  i_tags_addn(&img->tags, "tga_bitspp", 0, mapped?header.colourmapdepth:header.bitsperpixel);
  if (src.compressed) i_tags_addn(&img->tags, "compressed", 0, 1);
  return img;
}



/*
=item i_writetga_wiol(img, ig)

Writes an image in targa format.  Returns 0 on error.

   img    - image to store
   ig     - io_glue object

=cut
*/

undef_int
i_writetga_wiol(i_img *img, io_glue *ig, int wierdpack, int compress, char *idstring, size_t idlen) {
  tga_header header;
  tga_dest dest;
  unsigned char headbuf[18];
  unsigned int bitspp;
  unsigned int attr_bits = 0;
  
  int mapped;

  /* parameters */

  /*
    int compress = 1;
    char *idstring = "testing";
    int wierdpack = 0;
  */

  idlen = strlen(idstring);
  mapped = img->type == i_palette_type;

  mm_log((1,"i_writetga_wiol(img %p, ig %p, idstring %p, idlen %ld, wierdpack %d, compress %d)\n",
	  img, ig, idstring, (long)idlen, wierdpack, compress));
  mm_log((1, "virtual %d, paletted %d\n", img->virtual, mapped));
  mm_log((1, "channels %d\n", img->channels));
  
  i_clear_error();

  if (img->xsize > TGA_MAX_DIM || img->ysize > TGA_MAX_DIM) {
    i_push_error(0, "image too large for TGA");
    return 0;
  }

  switch (img->channels) {
  case 1:
    bitspp = 8;
    if (wierdpack) {
      mm_log((1,"wierdpack option ignored for 1 channel images\n"));
      wierdpack=0;
    }
    break;
  case 2:
    i_push_error(0, "Cannot store 2 channel image in targa format");
    return 0;
    break;
  case 3:
    bitspp = wierdpack ? 15 : 24;
    break;
  case 4:
    bitspp = wierdpack ? 16 : 32;
    attr_bits = wierdpack ? 1 : 8;
    break;
  default:
    i_push_error(0, "Targa only handles 1,3 and 4 channel images.");
    return 0;
  }

  header.idlength = idlen;
  header.colourmaptype   = mapped ? 1 : 0;
  header.datatypecode    = mapped ? 1 : img->channels == 1 ? 3 : 2;
  header.datatypecode   += compress ? 8 : 0;
  mm_log((1, "datatypecode %d\n", header.datatypecode));
  header.colourmaporigin = 0;
  header.colourmaplength = mapped ? i_colorcount(img) : 0;
  header.colourmapdepth  = mapped ? bitspp : 0;
  header.x_origin        = 0;
  header.y_origin        = 0;
  header.width           = img->xsize;
  header.height          = img->ysize;
  header.bitsperpixel    = mapped ? 8 : bitspp;
  header.imagedescriptor = (1<<5) | attr_bits; /* normal order instead of upside down */

  tga_header_pack(&header, headbuf);

  if (i_io_write(ig, &headbuf, sizeof(headbuf)) != sizeof(headbuf)) {
    i_push_error(errno, "could not write targa header");
    return 0;
  }

  if (idlen) {
    if (i_io_write(ig, idstring, idlen) != idlen) {
      i_push_error(errno, "could not write targa idstring");
      return 0;
    }
  }
  
  /* Make this into a constructor? */
  dest.compressed = compress;
  dest.bytepp     = mapped ? 1 : bpp_to_bytes(bitspp);
  dest.ig         = ig;

  mm_log((1, "dest.compressed = %d\n", dest.compressed));
  mm_log((1, "dest.bytepp = %d\n", dest.bytepp));

  if (img->type == i_palette_type) {
    if (!tga_palette_write(ig, img, bitspp, i_colorcount(img))) return 0;
    
    if (!img->virtual && !dest.compressed) {
      if (i_io_write(ig, img->idata, img->bytes) != img->bytes) {
	i_push_error(errno, "could not write targa image data");
	return 0;
      }
    } else {
      int y;
      i_palidx *vals = mymalloc(sizeof(i_palidx)*img->xsize);
      for(y=0; y<img->ysize; y++) {
	i_gpal(img, 0, img->xsize, y, vals);
	tga_dest_write(&dest, vals, img->xsize);
      }
      myfree(vals);
    }
  } else { /* direct type */
    int x, y;
    size_t bytepp = wierdpack ? 2 : bpp_to_bytes(bitspp);
    size_t lsize = bytepp * img->xsize;
    i_color *vals = mymalloc(img->xsize*sizeof(i_color));
    unsigned char *buf = mymalloc(lsize);
    
    for(y=0; y<img->ysize; y++) {
      i_glin(img, 0, img->xsize, y, vals);
      for(x=0; x<img->xsize; x++) color_pack(buf+x*bytepp, bitspp, vals+x);
      tga_dest_write(&dest, buf, img->xsize);
    }
    myfree(buf);
    myfree(vals);
  }

  if (i_io_close(ig))
    return 0;

  return 1;
}

/*
=back

=head1 AUTHOR

Arnar M. Hrafnkelsson <addi@umich.edu>

=head1 SEE ALSO

Imager(3)

=cut
*/
