#include "imsgi.h"

#include <stdlib.h>
#include <errno.h>
#include <string.h>

/* value for imagic */
#define SGI_MAGIC 474

/* values for the storage field */
#define SGI_STORAGE_VERBATIM 0
#define SGI_STORAGE_RLE 1

/* values for the colormap field */
#define SGI_COLORMAP_NORMAL 0
#define SGI_COLORMAP_DITHERED 1
#define SGI_COLORMAP_SCREEN 2
#define SGI_COLORMAP_COLORMAP 3

/* we add that little bit to avoid rounding issues */
#define SampleFTo16(num) ((int)((num) * 65535.0 + 0.01))

/* maximum size of an SGI image */
#define SGI_DIM_LIMIT 0xFFFF

typedef struct {
  unsigned short imagic;
  unsigned char storagetype;
  unsigned char BPC;
  unsigned short dimensions;
  unsigned short xsize, ysize, zsize;
  unsigned int pixmin, pixmax;
  char name[80];
  unsigned int colormap;
} rgb_header;

static i_img *
read_rgb_8_verbatim(i_img *im, io_glue *ig, rgb_header const *hdr);
static i_img *
read_rgb_8_rle(i_img *im, io_glue *ig, rgb_header const *hdr);
static i_img *
read_rgb_16_verbatim(i_img *im, io_glue *ig, rgb_header const *hdr);
static i_img *
read_rgb_16_rle(i_img *im, io_glue *ig, rgb_header const *hdr);
static int
write_sgi_header(i_img *img, io_glue *ig, int *rle, int *bpc2);
static int
write_sgi_8_rle(i_img *img, io_glue *ig);
static int
write_sgi_8_verb(i_img *img, io_glue *ig);
static int
write_sgi_16_rle(i_img *img, io_glue *ig);
static int
write_sgi_16_verb(i_img *img, io_glue *ig);

#define Sample16ToF(num) ((num) / 65535.0)

#define _STRING(x) #x
#define STRING(x) _STRING(x)

/*
=head1 NAME

rgb.c - implements reading and writing sgi image files, uses io layer.

=head1 SYNOPSIS

   io_glue *ig = io_new_fd( fd );
   i_img *im   = i_readrgb_wiol(ig, 0); // disallow partial reads
   // or 
   io_glue *ig = io_new_fd( fd );
   return_code = i_writergb_wiol(im, ig); 

=head1 DESCRIPTION

imsgi.c implements the basic functions to read and write portable SGI
files.  It uses the iolayer and needs either a seekable source or an
entire memory mapped buffer.

=head1 FUNCTION REFERENCE

Some of these functions are internal.

=over

=cut
*/

/*
=item rgb_header_unpack(header, headbuf)

Unpacks the header structure into from buffer and stores
in the header structure.

    header - header structure
    headbuf - buffer to unpack from

=cut
*/


static
void
rgb_header_unpack(rgb_header *header, const unsigned char *headbuf) {
  header->imagic      = (headbuf[0]<<8) + headbuf[1];
  header->storagetype = headbuf[2];
  header->BPC         = headbuf[3];
  header->dimensions  = (headbuf[4]<<8) + headbuf[5];
  header->xsize       = (headbuf[6]<<8) + headbuf[7];
  header->ysize       = (headbuf[8]<<8) + headbuf[9];
  header->zsize       = (headbuf[10]<<8) + headbuf[11];
  header->pixmin      = (headbuf[12]<<24) + (headbuf[13]<<16)+(headbuf[14]<<8)+headbuf[15];
  header->pixmax      = (headbuf[16]<<24) + (headbuf[17]<<16)+(headbuf[18]<<8)+headbuf[19];
  memcpy(header->name,headbuf+24,80);
  header->name[79] = '\0';
  header->colormap    = (headbuf[104]<<24) + (headbuf[105]<<16)+(headbuf[106]<<8)+headbuf[107];
}

/* don't make this a macro */
static void
store_16(unsigned char *buf, unsigned short value) {
  buf[0] = value >> 8;
  buf[1] = value & 0xFF;
}

static void
store_32(unsigned char *buf, unsigned long value) {
  buf[0] = value >> 24;
  buf[1] = (value >> 16) & 0xFF;
  buf[2] = (value >> 8) & 0xFF;
  buf[3] = value & 0xFF;
}

/*
=item rgb_header_pack(header, headbuf)

Packs header structure into buffer for writing.

    header - header structure
    headbuf - buffer to pack into

=cut
*/

static
void
rgb_header_pack(const rgb_header *header, unsigned char headbuf[512]) {
  memset(headbuf, 0, 512);
  store_16(headbuf, header->imagic);
  headbuf[2] = header->storagetype;
  headbuf[3] = header->BPC;
  store_16(headbuf+4, header->dimensions);
  store_16(headbuf+6, header->xsize);
  store_16(headbuf+8, header->ysize);
  store_16(headbuf+10, header->zsize);
  store_32(headbuf+12, header->pixmin);
  store_32(headbuf+16, header->pixmax);
  memccpy(headbuf+24, header->name, '\0', 80);
  store_32(headbuf+104, header->colormap);
}

/*
=item i_readsgi_wiol(ig, partial)

Read in an image from the iolayer data source and return the image structure to it.
Returns NULL on error.

   ig     - io_glue object
   length - maximum length to read from data source, before closing it -1 
            signifies no limit.

=cut
*/

i_img *
i_readsgi_wiol(io_glue *ig, int partial) {
  i_img *img = NULL;
  int width, height, channels;
  rgb_header header;
  unsigned char headbuf[512];

  mm_log((1,"i_readsgi(ig %p, partial %d)\n", ig, partial));
  i_clear_error();

  if (i_io_read(ig, headbuf, 512) != 512) {
    i_push_error(errno, "SGI image: could not read header");
    return NULL;
  }

  rgb_header_unpack(&header, headbuf);

  if (header.imagic != SGI_MAGIC) {
    i_push_error(0, "SGI image: invalid magic number");
    return NULL;
  }

  mm_log((1,"imagic:         %d\n", header.imagic));
  mm_log((1,"storagetype:    %d\n", header.storagetype));
  mm_log((1,"BPC:            %d\n", header.BPC));
  mm_log((1,"dimensions:     %d\n", header.dimensions));
  mm_log((1,"xsize:          %d\n", header.xsize));
  mm_log((1,"ysize:          %d\n", header.ysize));
  mm_log((1,"zsize:          %d\n", header.zsize));
  mm_log((1,"min:            %d\n", header.pixmin));
  mm_log((1,"max:            %d\n", header.pixmax));
  mm_log((1,"name [skipped]\n"));
  mm_log((1,"colormap:       %d\n", header.colormap));

  if (header.colormap != SGI_COLORMAP_NORMAL) {
    i_push_errorf(0, "SGI image: invalid value for colormap (%d)", header.colormap);
    return NULL;
  }

  if (header.BPC != 1 && header.BPC != 2) {
    i_push_errorf(0, "SGI image: invalid value for BPC (%d)", header.BPC);
    return NULL;
  }

  if (header.storagetype != SGI_STORAGE_VERBATIM 
      && header.storagetype != SGI_STORAGE_RLE) {
    i_push_error(0, "SGI image: invalid storage type field");
    return NULL;
  }

  if (header.pixmin >= header.pixmax) {
    i_push_error(0, "SGI image: invalid pixmin >= pixmax");
    return NULL;
  }

  width    = header.xsize;
  height   = header.ysize;
  channels = header.zsize;

  switch (header.dimensions) {
  case 1:
    channels = 1;
    height = 1;
    break;

  case 2:
    channels = 1;
    break;

  case 3:
    /* fall through and use all of the dimensions */
    break;

  default:
    i_push_error(0, "SGI image: invalid dimension field");
    return NULL;
  }

  if (!i_int_check_image_file_limits(width, height, channels, header.BPC)) {
    mm_log((1, "i_readsgi_wiol: image size exceeds limits\n"));
    return NULL;
  }

  if (header.BPC == 1) {
    img = i_img_8_new(width, height, channels);
    if (!img)
      goto ErrorReturn;

    switch (header.storagetype) {
    case SGI_STORAGE_VERBATIM:
      img = read_rgb_8_verbatim(img, ig, &header);
      break;

    case SGI_STORAGE_RLE:
      img = read_rgb_8_rle(img, ig, &header);
      break;

    default:
      goto ErrorReturn;
    }
  }
  else {
    img = i_img_16_new(width, height, channels);
    if (!img)
      goto ErrorReturn;

    switch (header.storagetype) {
    case SGI_STORAGE_VERBATIM:
      img = read_rgb_16_verbatim(img, ig, &header);
      break;

    case SGI_STORAGE_RLE:
      img = read_rgb_16_rle(img, ig, &header);
      break;

    default:
      goto ErrorReturn;
    }
  }

  if (!img)
    goto ErrorReturn;

  if (*header.name)
    i_tags_set(&img->tags, "i_comment", header.name, -1);
  i_tags_setn(&img->tags, "sgi_pixmin", header.pixmin);
  i_tags_setn(&img->tags, "sgi_pixmax", header.pixmax);
  i_tags_setn(&img->tags, "sgi_bpc", header.BPC);
  i_tags_setn(&img->tags, "sgi_rle", header.storagetype == SGI_STORAGE_RLE);
  i_tags_set(&img->tags, "i_format", "sgi", -1);

  return img;

 ErrorReturn:
  if (img) i_img_destroy(img);
  return NULL;
}

/*
=item i_writergb_wiol(img, ig)

Writes an image in targa format.  Returns 0 on error.

   img    - image to store
   ig     - io_glue object

=cut
*/

int
i_writesgi_wiol(io_glue *ig, i_img *img) {
  int rle;
  int bpc2;

  i_clear_error();

  if (img->xsize > SGI_DIM_LIMIT || img->ysize > SGI_DIM_LIMIT) {
    i_push_error(0, "image too large for SGI");
    return 0;
  }

  if (!write_sgi_header(img, ig, &rle, &bpc2))
    return 0;

  mm_log((1, "format rle %d bpc2 %d\n", rle, bpc2));

  if (bpc2) {
    if (rle)
      return write_sgi_16_rle(img, ig);
    else
      return write_sgi_16_verb(img, ig);
  }
  else {
    if (rle)
      return write_sgi_8_rle(img, ig);
    else
      return write_sgi_8_verb(img, ig);
  }
}

static i_img *
read_rgb_8_verbatim(i_img *img, io_glue *ig, rgb_header const *header) {
  i_color *linebuf;
  unsigned char *databuf;
  int c, y;
  int savemask;
  i_img_dim width = i_img_get_width(img);
  i_img_dim height = i_img_get_height(img);
  int channels = i_img_getchannels(img);
  int pixmin = header->pixmin;
  int pixmax = header->pixmax;
  int outmax = pixmax - pixmin;
  
  linebuf   = mymalloc(width * sizeof(i_color)); /* checked 31Jul07 TonyC */
  databuf   = mymalloc(width); /* checked 31Jul07 TonyC */

  savemask = i_img_getmask(img);

  for(c = 0; c < channels; c++) {
    i_img_setmask(img, 1<<c);
    for(y = 0; y < height; y++) {
      int x;
      
      if (i_io_read(ig, databuf, width) != width) {
	i_push_error(0, "SGI image: cannot read image data");
	i_img_destroy(img);
	myfree(linebuf);
	myfree(databuf);
	return NULL;
      }

      if (pixmin == 0 && pixmax == 255) {
	for(x = 0; x < img->xsize; x++)
	  linebuf[x].channel[c] = databuf[x];
      }
      else {
	for(x = 0; x < img->xsize; x++) {
	  int sample = databuf[x];
	  if (sample < pixmin)
	    sample = 0;
	  else if (sample > pixmax)
	    sample = outmax;
	  else
	    sample -= pixmin;
	    
	  linebuf[x].channel[c] = sample * 255 / outmax;
	}
      }
      
      i_plin(img, 0, width, height-1-y, linebuf);
    }
  }
  i_img_setmask(img, savemask);

  myfree(linebuf);
  myfree(databuf);
  
  return img;
}

static int
read_rle_tables(io_glue *ig, i_img *img,
		unsigned long **pstart_tab, unsigned long **plength_tab, 
		unsigned long *pmax_length) {
  i_img_dim height = i_img_get_height(img);
  int channels = i_img_getchannels(img);
  unsigned char *databuf;
  unsigned long *start_tab, *length_tab;
  unsigned long max_length = 0;
  int i;
  size_t databuf_size = (size_t)height * channels * 4;
  size_t tab_size = (size_t)height * channels * sizeof(unsigned long);

  /* assumption: that the lengths are in bytes rather than in pixels */
  if (databuf_size / height / channels != 4
      || tab_size / height / channels != sizeof(unsigned long)) {
    i_push_error(0, "SGI image: integer overflow calculating allocation size");
    return 0;
  }
  databuf    = mymalloc(height * channels * 4);  /* checked 31Jul07 TonyC */
  start_tab  = mymalloc(height*channels*sizeof(unsigned long));
  length_tab = mymalloc(height*channels*sizeof(unsigned long));
    
    /* Read offset table */
  if (i_io_read(ig, databuf, height * channels * 4) != height * channels * 4) {
    i_push_error(0, "SGI image: short read reading RLE start table");
    goto ErrorReturn;
  }

  for(i = 0; i < height * channels; i++) 
    start_tab[i] = (databuf[i*4] << 24) | (databuf[i*4+1] << 16) | 
      (databuf[i*4+2] << 8) | (databuf[i*4+3]);


  /* Read length table */
  if (i_io_read(ig, databuf, height*channels*4) != height*channels*4) {
    i_push_error(0, "SGI image: short read reading RLE length table");
    goto ErrorReturn;
  }

  for(i=0; i < height * channels; i++) {
    length_tab[i] = (databuf[i*4] << 24) + (databuf[i*4+1] << 16)+
      (databuf[i*4+2] << 8) + (databuf[i*4+3]);
    if (length_tab[i] > max_length)
      max_length = length_tab[i];
  }

  mm_log((3, "Offset/length table:\n"));
  for(i=0; i < height * channels; i++)
    mm_log((3, "%d: %lu/%lu\n", i, start_tab[i], length_tab[i]));

  *pstart_tab = start_tab;
  *plength_tab = length_tab;
  *pmax_length = max_length;

  myfree(databuf);

  return 1;

 ErrorReturn:
  myfree(databuf);
  myfree(start_tab);
  myfree(length_tab);

  return 0;
}

static i_img *
read_rgb_8_rle(i_img *img, io_glue *ig, rgb_header const *header) {
  i_color *linebuf = NULL;
  unsigned char *databuf = NULL;
  unsigned long *start_tab, *length_tab;
  unsigned long max_length;
  i_img_dim width = i_img_get_width(img);
  i_img_dim height = i_img_get_height(img);
  int channels = i_img_getchannels(img);
  i_img_dim y;
  int c;
  int pixmin = header->pixmin;
  int pixmax = header->pixmax;
  int outmax = pixmax - pixmin;

  if (!read_rle_tables(ig, img,  
		       &start_tab, &length_tab, &max_length)) {
    i_img_destroy(img);
    return NULL;
  }

  mm_log((1, "maxlen for an rle buffer: %lu\n", max_length));

  if (max_length > (img->xsize + 1) * 2) {
    i_push_errorf(0, "SGI image: ridiculous RLE line length %lu", max_length);
    goto ErrorReturn;
  }

  linebuf = mymalloc(width*sizeof(i_color)); /* checked 31Jul07 TonyC */
  databuf = mymalloc(max_length); /* checked 31Jul07 TonyC */

  for(y = 0; y < img->ysize; y++) {
    for(c = 0; c < channels; c++) {
      int ci = height * c + y;
      int datalen = length_tab[ci];
      unsigned char *inp;
      i_color *outp;
      int data_left = datalen;
      int pixels_left = width;
      i_sample_t sample;
      
      if (i_io_seek(ig, start_tab[ci], SEEK_SET) != start_tab[ci]) {
	i_push_error(0, "SGI image: cannot seek to RLE data");
	goto ErrorReturn;
      }
      if (i_io_read(ig, databuf, datalen) != datalen) {
	i_push_error(0, "SGI image: cannot read RLE data");
	goto ErrorReturn;
      }
      
      inp = databuf;
      outp = linebuf;
      while (data_left) {
	int code = *inp++;
	int count = code & 0x7f;
	--data_left;

	if (count == 0)
	  break;
	if (code & 0x80) {
	  /* literal run */
	  /* sanity checks */
	  if (count > pixels_left) {
	    i_push_error(0, "SGI image: literal run overflows scanline");
	    goto ErrorReturn;
	  }
	  if (count > data_left) {
	    i_push_error(0, "SGI image: literal run consumes more data than available");
	    goto ErrorReturn;
	  }
	  /* copy the run */
	  pixels_left -= count;
	  data_left -= count;
	  if (pixmin == 0 && pixmax == 255) {
	    while (count-- > 0) {
	      outp->channel[c] = *inp++;
	      ++outp;
	    }
	  }
	  else {
	    while (count-- > 0) {
	      int sample = *inp++;
	      if (sample < pixmin)
		sample = 0;
	      else if (sample > pixmax)
		sample = outmax;
	      else
		sample -= pixmin;
	      outp->channel[c] = sample * 255 / outmax;
	      ++outp;
	    }
	  }
	}
	else {
	  /* RLE run */
	  if (count > pixels_left) {
	    i_push_error(0, "SGI image: RLE run overflows scanline");
	    mm_log((2, "RLE run overflows scanline (y %" i_DF " chan %d offset %lu len %lu)\n", i_DFc(y), c, start_tab[ci], length_tab[ci]));
	    goto ErrorReturn;
	  }
	  if (data_left < 1) {
	    i_push_error(0, "SGI image: RLE run has no data for pixel");
	    goto ErrorReturn;
	  }
	  sample = *inp++;
	  if (pixmin != 0 || pixmax != 255) {
	    if (sample < pixmin)
	      sample = 0;
	    else if (sample > pixmax)
	      sample = outmax;
	    else
	      sample -= pixmin;
	    sample = sample * 255 / outmax;
	  }
	  --data_left;
	  pixels_left -= count;
	  while (count-- > 0) {
	    outp->channel[c] = sample;
	    ++outp;
	  }
	}
      }
      /* must have a full scanline */
      if (pixels_left) {
	i_push_error(0, "SGI image: incomplete RLE scanline");
	goto ErrorReturn;
      }
      /* must have used all of the data */
      if (data_left) {
	i_push_errorf(0, "SGI image: unused RLE data");
	goto ErrorReturn;
      }
    }
    i_plin(img, 0, width, height-1-y, linebuf);
  }

  myfree(linebuf);
  myfree(databuf);
  myfree(start_tab);
  myfree(length_tab);

  return img;

 ErrorReturn:
  if (linebuf)
    myfree(linebuf);
  if (databuf)
    myfree(databuf);
  myfree(start_tab);
  myfree(length_tab);
  i_img_destroy(img);
  return NULL;
}

static i_img *
read_rgb_16_verbatim(i_img *img, io_glue *ig, rgb_header const *header) {
  i_fcolor *linebuf;
  unsigned char *databuf;
  int c, y;
  int savemask;
  i_img_dim width = i_img_get_width(img);
  i_img_dim height = i_img_get_height(img);
  int channels = i_img_getchannels(img);
  int pixmin = header->pixmin;
  int pixmax = header->pixmax;
  int outmax = pixmax - pixmin;
  
  linebuf   = mymalloc(width * sizeof(i_fcolor));  /* checked 31Jul07 TonyC */
  databuf   = mymalloc(width * 2);  /* checked 31Jul07 TonyC */

  savemask = i_img_getmask(img);

  for(c = 0; c < channels; c++) {
    i_img_setmask(img, 1<<c);
    for(y = 0; y < height; y++) {
      int x;
      
      if (i_io_read(ig, databuf, width*2) != width*2) {
	i_push_error(0, "SGI image: cannot read image data");
	i_img_destroy(img);
	myfree(linebuf);
	myfree(databuf);
	return NULL;
      }

      if (pixmin == 0 && pixmax == 65535) {
	for(x = 0; x < img->xsize; x++)
	  linebuf[x].channel[c] = (databuf[x*2] * 256 + databuf[x*2+1]) / 65535.0;
      }
      else {
	for(x = 0; x < img->xsize; x++) {
	  int sample = databuf[x*2] * 256 + databuf[x*2+1];
	  if (sample < pixmin)
	    sample = 0;
	  else if (sample > pixmax)
	    sample = outmax;
	  else
	    sample -= pixmin;
	    
	  linebuf[x].channel[c] = (double)sample / outmax;
	}
      }
      
      i_plinf(img, 0, width, height-1-y, linebuf);
    }
  }
  i_img_setmask(img, savemask);

  myfree(linebuf);
  myfree(databuf);
  
  return img;
}

static i_img *
read_rgb_16_rle(i_img *img, io_glue *ig, rgb_header const *header) {
  i_fcolor *linebuf = NULL;
  unsigned char *databuf = NULL;
  unsigned long *start_tab, *length_tab;
  unsigned long max_length;
  i_img_dim width = i_img_get_width(img);
  i_img_dim height = i_img_get_height(img);
  int channels = i_img_getchannels(img);
  i_img_dim y;
  int c;
  int pixmin = header->pixmin;
  int pixmax = header->pixmax;
  int outmax = pixmax - pixmin;

  if (!read_rle_tables(ig, img,  
		       &start_tab, &length_tab, &max_length)) {
    i_img_destroy(img);
    return NULL;
  }

  mm_log((1, "maxlen for an rle buffer: %lu\n", max_length));

  if (max_length > (img->xsize * 2 + 1) * 2) {
    i_push_errorf(0, "SGI image: ridiculous RLE line length %lu", max_length);
    goto ErrorReturn;
  }

  linebuf = mymalloc(width*sizeof(i_fcolor)); /* checked 31Jul07 TonyC */
  databuf = mymalloc(max_length); /* checked 31Jul07 TonyC */

  for(y = 0; y < img->ysize; y++) {
    for(c = 0; c < channels; c++) {
      int ci = height * c + y;
      int datalen = length_tab[ci];
      unsigned char *inp;
      i_fcolor *outp;
      int data_left = datalen;
      int pixels_left = width;
      int sample;
      
      if (datalen & 1) {
	i_push_error(0, "SGI image: invalid RLE length value for BPC=2");
	goto ErrorReturn;
      }
      if (i_io_seek(ig, start_tab[ci], SEEK_SET) != start_tab[ci]) {
	i_push_error(0, "SGI image: cannot seek to RLE data");
	goto ErrorReturn;
      }
      if (i_io_read(ig, databuf, datalen) != datalen) {
	i_push_error(0, "SGI image: cannot read RLE data");
	goto ErrorReturn;
      }
      
      inp = databuf;
      outp = linebuf;
      while (data_left > 0) {
	int code = inp[0] * 256 + inp[1];
	int count = code & 0x7f;
	inp += 2;
	data_left -= 2;

	if (count == 0)
	  break;
	if (code & 0x80) {
	  /* literal run */
	  /* sanity checks */
	  if (count > pixels_left) {
	    i_push_error(0, "SGI image: literal run overflows scanline");
	    goto ErrorReturn;
	  }
	  if (count > data_left) {
	    i_push_error(0, "SGI image: literal run consumes more data than available");
	    goto ErrorReturn;
	  }
	  /* copy the run */
	  pixels_left -= count;
	  data_left -= count * 2;
	  if (pixmin == 0 && pixmax == 65535) {
	    while (count-- > 0) {
	      outp->channel[c] = (inp[0] * 256 + inp[1]) / 65535.0;
	      inp += 2;
	      ++outp;
	    }
	  }
	  else {
	    while (count-- > 0) {
	      int sample = inp[0] * 256 + inp[1];
	      if (sample < pixmin)
		sample = 0;
	      else if (sample > pixmax)
		sample = outmax;
	      else
		sample -= pixmin;
	      outp->channel[c] = (double)sample / outmax;
	      ++outp;
	      inp += 2;
	    }
	  }
	}
	else {
	  double fsample;
	  /* RLE run */
	  if (count > pixels_left) {
	    i_push_error(0, "SGI image: RLE run overflows scanline");
	    goto ErrorReturn;
	  }
	  if (data_left < 2) {
	    i_push_error(0, "SGI image: RLE run has no data for pixel");
	    goto ErrorReturn;
	  }
	  sample = inp[0] * 256 + inp[1];
	  inp += 2;
	  data_left -= 2;
	  if (pixmin != 0 || pixmax != 65535) {
	    if (sample < pixmin)
	      sample = 0;
	    else if (sample > pixmax)
	      sample = outmax;
	    else
	      sample -= pixmin;
	    fsample = (double)sample / outmax;
	  }
	  else {
	    fsample = (double)sample / 65535.0;
	  }
	  pixels_left -= count;
	  while (count-- > 0) {
	    outp->channel[c] = fsample;
	    ++outp;
	  }
	}
      }
      /* must have a full scanline */
      if (pixels_left) {
	i_push_error(0, "SGI image: incomplete RLE scanline");
	goto ErrorReturn;
      }
      /* must have used all of the data */
      if (data_left) {
	i_push_errorf(0, "SGI image: unused RLE data");
	goto ErrorReturn;
      }
    }
    i_plinf(img, 0, width, height-1-y, linebuf);
  }

  myfree(linebuf);
  myfree(databuf);
  myfree(start_tab);
  myfree(length_tab);

  return img;

 ErrorReturn:
  if (linebuf)
    myfree(linebuf);
  if (databuf)
    myfree(databuf);
  myfree(start_tab);
  myfree(length_tab);
  i_img_destroy(img);
  return NULL;
}

static int
write_sgi_header(i_img *img, io_glue *ig, int *rle, int *bpc2) {
  rgb_header header;
  unsigned char headbuf[512] = { 0 };

  header.imagic = SGI_MAGIC;
  if (!i_tags_get_int(&img->tags, "sgi_rle", 0, rle))
    *rle = 0;
  header.storagetype = *rle ? SGI_STORAGE_RLE : SGI_STORAGE_VERBATIM;
  header.pixmin = 0;
  header.colormap = SGI_COLORMAP_NORMAL;
  *bpc2 = img->bits > 8;
  if (*bpc2) {
    header.BPC = 2;
    header.pixmax = 65535;
  }
  else {
    header.BPC = 1;
    header.pixmax = 255;
  }
  if (img->channels == 1) {
    header.dimensions = 2;
  }
  else {
    header.dimensions = 3;
  }
  header.xsize = img->xsize;
  header.ysize = img->ysize;
  header.zsize = img->channels;
  memset(header.name, 0, sizeof(header.name));
  i_tags_get_string(&img->tags, "i_comment",  0, 
		    header.name, sizeof(header.name));

  rgb_header_pack(&header, headbuf);

  if (i_io_write(ig, headbuf, sizeof(headbuf)) != sizeof(headbuf)) {
    i_push_error(0, "SGI image: cannot write header");
    return 0;
  }

  return 1;
}

static int
write_sgi_8_verb(i_img *img, io_glue *ig) {
  i_sample_t *linebuf;
  i_img_dim width = img->xsize;
  int c;
  i_img_dim y;

  linebuf = mymalloc(width);  /* checked 31Jul07 TonyC */
  for (c = 0; c < img->channels; ++c) {
    for (y = img->ysize - 1; y >= 0; --y) {
      i_gsamp(img, 0, width, y, linebuf, &c, 1);
      if (i_io_write(ig, linebuf, width) != width) {
	i_push_error(errno, "SGI image: error writing image data");
	myfree(linebuf);
	return 0;
      }
    }
  }
  myfree(linebuf);

  if (i_io_close(ig))
    return 0;

  return 1;
}

static int
write_sgi_8_rle(i_img *img, io_glue *ig) {
  i_sample_t *linebuf;
  unsigned char *comp_buf;
  i_img_dim width = img->xsize;
  int c;
  i_img_dim y;
  unsigned char *offsets;
  unsigned char *lengths;
  int offset_pos = 0;
  size_t offsets_size = (size_t)4 * img->ysize * img->channels * 2;
  unsigned long start_offset = 512 + offsets_size;
  unsigned long current_offset = start_offset;
  int in_left;
  unsigned char *outp;
  i_sample_t *inp;
  size_t comp_size;

  if (offsets_size / 2 / 4 / img->channels != img->ysize) {
    i_push_error(0, "SGI image: integer overflow calculating allocation size");
    return 0;
  }

  linebuf = mymalloc(width);  /* checked 31Jul07 TonyC */
  comp_buf = mymalloc((width + 1) * 2);  /* checked 31Jul07 TonyC */
  offsets = mymalloc(offsets_size);
  memset(offsets, 0, offsets_size);
  if (i_io_write(ig, offsets, offsets_size) != offsets_size) {
    i_push_error(errno, "SGI image: error writing offsets/lengths");
    goto Error;
  }
  lengths = offsets + img->ysize * img->channels * 4;
  for (c = 0; c < img->channels; ++c) {
    for (y = img->ysize - 1; y >= 0; --y) {
      i_gsamp(img, 0, width, y, linebuf, &c, 1);
      in_left = width;
      outp = comp_buf;
      inp = linebuf;
      while (in_left) {
	unsigned char *run_start = inp;

	/* first try for an RLE run */
	int run_length = 1;
	while (in_left - run_length >= 2 && inp[0] == inp[1] && run_length < 127) {
	  ++run_length;
	  ++inp;
	}
	if (in_left - run_length == 1 && inp[0] == inp[1] && run_length < 127) {
	  ++run_length;
	  ++inp;
	}
	if (run_length > 2) {
	  *outp++ = run_length;
	  *outp++ = inp[0];
	  inp++;
	  in_left -= run_length;
	}
	else {
	  inp = run_start;

	  /* scan for a literal run */
	  run_length = 1;
	  run_start = inp;
	  while (in_left - run_length > 1 && (inp[0] != inp[1] || inp[1] != inp[2]) && run_length < 127) {
	    ++run_length;
	    ++inp;
	  }
	  ++inp;
	  
	  /* fill out the run if 2 or less samples left and there's space */
	  if (in_left - run_length <= 2 
	      && in_left <= 127) {
	    run_length = in_left;
	  }
	  in_left -= run_length;
	  *outp++ = run_length | 0x80;
	  while (run_length--) {
	    *outp++ = *run_start++;
	  }
	}
      }
      *outp++ = 0;
      comp_size = outp - comp_buf;
      store_32(offsets + offset_pos, current_offset);
      store_32(lengths + offset_pos, comp_size);
      offset_pos += 4;
      current_offset += comp_size;
      if (i_io_write(ig, comp_buf, comp_size) != comp_size) {
	i_push_error(errno, "SGI image: error writing RLE data");
	goto Error;
      }
    }
  }

  /* seek back to store the offsets and lengths */
  if (i_io_seek(ig, 512, SEEK_SET) != 512) {
    i_push_error(errno, "SGI image: cannot seek to RLE table");
    goto Error;
  }

  if (i_io_write(ig, offsets, offsets_size) != offsets_size) {
    i_push_error(errno, "SGI image: cannot write final RLE table");
    goto Error;
  }

  myfree(offsets);
  myfree(comp_buf);
  myfree(linebuf);

  if (i_io_close(ig))
    return 0;

  return 1;

 Error:
  myfree(offsets);
  myfree(comp_buf);
  myfree(linebuf);
  return 0;
}

static int
write_sgi_16_verb(i_img *img, io_glue *ig) {
  i_fsample_t *linebuf;
  unsigned char *encbuf;
  unsigned char *outp;
  i_img_dim width = img->xsize;
  int c;
  i_img_dim x;
  i_img_dim y;

  linebuf = mymalloc(width * sizeof(i_fsample_t));  /* checked 31Jul07 TonyC */
  encbuf = mymalloc(width * 2);  /* checked 31Jul07 TonyC */
  for (c = 0; c < img->channels; ++c) {
    for (y = img->ysize - 1; y >= 0; --y) {
      i_gsampf(img, 0, width, y, linebuf, &c, 1);
      for (x = 0, outp = encbuf; x < width; ++x, outp+=2) {
	unsigned short samp16 = SampleFTo16(linebuf[x]);
	store_16(outp, samp16);
      }
      if (i_io_write(ig, encbuf, width * 2) != width * 2) {
	i_push_error(errno, "SGI image: error writing image data");
	myfree(linebuf);
	myfree(encbuf);
	return 0;
      }
    }
  }
  myfree(linebuf);
  myfree(encbuf);

  if (i_io_close(ig))
    return 0;

  return 1;
}

static int
write_sgi_16_rle(i_img *img, io_glue *ig) {
  i_fsample_t *sampbuf;
  unsigned short *linebuf;
  unsigned char *comp_buf;
  i_img_dim width = img->xsize;
  int c;
  i_img_dim y;
  unsigned char *offsets;
  unsigned char *lengths;
  int offset_pos = 0;
  size_t offsets_size = (size_t)4 * img->ysize * img->channels * 2;
  unsigned long start_offset = 512 + offsets_size;
  unsigned long current_offset = start_offset;
  int in_left;
  unsigned char *outp;
  unsigned short *inp;
  size_t comp_size;
  i_img_dim x;

  if (offsets_size / 4 / 2 / img->channels != img->ysize) {
    i_push_error(0, "SGI image: integer overflow calculating allocation size");
    return 0;
  }

  sampbuf = mymalloc(width * sizeof(i_fsample_t));  /* checked 31Jul07 TonyC */
  linebuf = mymalloc(width * sizeof(unsigned short));  /* checked 31Jul07 TonyC */
  comp_buf = mymalloc((width + 1) * 2 * 2);  /* checked 31Jul07 TonyC */
  offsets = mymalloc(offsets_size);
  memset(offsets, 0, offsets_size);
  if (i_io_write(ig, offsets, offsets_size) != offsets_size) {
    i_push_error(errno, "SGI image: error writing offsets/lengths");
    goto Error;
  }
  lengths = offsets + img->ysize * img->channels * 4;
  for (c = 0; c < img->channels; ++c) {
    for (y = img->ysize - 1; y >= 0; --y) {
      i_gsampf(img, 0, width, y, sampbuf, &c, 1);
      for (x = 0; x < width; ++x)
	linebuf[x] = (unsigned short)(SampleFTo16(sampbuf[x]));
      in_left = width;
      outp = comp_buf;
      inp = linebuf;
      while (in_left) {
	unsigned short *run_start = inp;

	/* first try for an RLE run */
	int run_length = 1;
	while (in_left - run_length >= 2 && inp[0] == inp[1] && run_length < 127) {
	  ++run_length;
	  ++inp;
	}
	if (in_left - run_length == 1 && inp[0] == inp[1] && run_length < 127) {
	  ++run_length;
	  ++inp;
	}
	if (run_length > 2) {
	  store_16(outp, run_length);
	  store_16(outp+2, inp[0]);
	  outp += 4;
	  inp++;
	  in_left -= run_length;
	}
	else {
	  inp = run_start;

	  /* scan for a literal run */
	  run_length = 1;
	  run_start = inp;
	  while (in_left - run_length > 1 && (inp[0] != inp[1] || inp[1] != inp[2]) && run_length < 127) {
	    ++run_length;
	    ++inp;
	  }
	  ++inp;
	  
	  /* fill out the run if 2 or less samples left and there's space */
	  if (in_left - run_length <= 2 
	      && in_left <= 127) {
	    run_length = in_left;
	  }
	  in_left -= run_length;
	  store_16(outp, run_length | 0x80);
	  outp += 2;
	  while (run_length--) {
	    store_16(outp, *run_start++);
	    outp += 2;
	  }
	}
      }
      store_16(outp, 0);
      outp += 2;
      comp_size = outp - comp_buf;
      store_32(offsets + offset_pos, current_offset);
      store_32(lengths + offset_pos, comp_size);
      offset_pos += 4;
      current_offset += comp_size;
      if (i_io_write(ig, comp_buf, comp_size) != comp_size) {
	i_push_error(errno, "SGI image: error writing RLE data");
	goto Error;
      }
    }
  }

  /* seek back to store the offsets and lengths */
  if (i_io_seek(ig, 512, SEEK_SET) != 512) {
    i_push_error(errno, "SGI image: cannot seek to RLE table");
    goto Error;
  }

  if (i_io_write(ig, offsets, offsets_size) != offsets_size) {
    i_push_error(errno, "SGI image: cannot write final RLE table");
    goto Error;
  }

  myfree(offsets);
  myfree(comp_buf);
  myfree(linebuf);
  myfree(sampbuf);

  if (i_io_close(ig))
    return 0;

  return 1;

 Error:
  myfree(offsets);
  myfree(comp_buf);
  myfree(linebuf);
  myfree(sampbuf);

  return 0;
}
