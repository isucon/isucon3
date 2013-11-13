#define IMAGER_NO_CONTEXT
#include <stdarg.h>
#include "imageri.h"

/*
=head1 NAME

bmp.c - read and write windows BMP files

=head1 SYNOPSIS

  i_img *im;
  io_glue *ig;

  if (!i_writebmp_wiol(im, ig)) {
    ... error ...
  }
  im = i_readbmp(ig);

=head1 DESCRIPTION

Reads and writes Windows BMP files.

=over

=cut
*/

#define FILEHEAD_SIZE 14
#define INFOHEAD_SIZE 40
#define BI_RGB		0
#define BI_RLE8		1
#define BI_RLE4		2
#define BI_BITFIELDS	3
#define BMPRLE_ENDOFLINE 0
#define BMPRLE_ENDOFBMP 1
#define BMPRLE_DELTA 2

#define SIGNBIT32 ((i_upacked_t)1U << 31)
#define SIGNBIT16 ((i_upacked_t)1U << 15)

#define SIGNMAX32 ((1UL << 31) - 1)

static int read_packed(io_glue *ig, char *format, ...);
static int write_packed(io_glue *ig, char *format, ...);
static int write_bmphead(io_glue *ig, i_img *im, int bit_count, 
                         int data_size);
static int write_1bit_data(io_glue *ig, i_img *im);
static int write_4bit_data(io_glue *ig, i_img *im);
static int write_8bit_data(io_glue *ig, i_img *im);
static int write_24bit_data(io_glue *ig, i_img *im);
static int read_bmp_pal(io_glue *ig, i_img *im, int count);
static i_img *read_1bit_bmp(io_glue *ig, int xsize, int ysize, int clr_used, 
                            int compression, long offbits, int allow_incomplete);
static i_img *read_4bit_bmp(io_glue *ig, int xsize, int ysize, int clr_used, 
                            int compression, long offbits, int allow_incomplete);
static i_img *read_8bit_bmp(io_glue *ig, int xsize, int ysize, int clr_used, 
                            int compression, long offbits, int allow_incomplete);
static i_img *read_direct_bmp(io_glue *ig, int xsize, int ysize, 
                              int bit_count, int clr_used, int compression,
                              long offbits, int allow_incomplete);

/* used for the read_packed() and write_packed() functions, an integer
 * type */
typedef long i_packed_t;
typedef unsigned long i_upacked_t;

/* 
=item i_writebmp_wiol(im, io_glue)

Writes the image as a BMP file.  Uses 1-bit, 4-bit, 8-bit or 24-bit
formats depending on the image.

Never compresses the image.

=cut
*/
int
i_writebmp_wiol(i_img *im, io_glue *ig) {
  dIMCTXim(im);
  i_clear_error();

  /* pick a format */
  if (im->type == i_direct_type) {
    return write_24bit_data(ig, im);
  }
  else {
    int pal_size;

    /* must be paletted */
    pal_size = i_colorcount(im);
    if (pal_size <= 2) {
      return write_1bit_data(ig, im);
    }
    else if (pal_size <= 16) {
      return write_4bit_data(ig, im);
    }
    else {
      return write_8bit_data(ig, im);
    }
  }
}

/*
=item i_readbmp_wiol(ig)

Reads a Windows format bitmap from the given file.

Handles BI_RLE4 and BI_RLE8 compressed images.  Attempts to handle
BI_BITFIELDS images too, but I need a test image.

=cut
*/

i_img *
i_readbmp_wiol(io_glue *ig, int allow_incomplete) {
  i_packed_t b_magic, m_magic, filesize, res1, res2, infohead_size;
  i_packed_t xsize, ysize, planes, bit_count, compression, size_image, xres, yres;
  i_packed_t clr_used, clr_important, offbits;
  i_img *im;
  dIMCTXio(ig);

  im_log((aIMCTX, 1, "i_readbmp_wiol(ig %p)\n", ig));
  
  i_clear_error();

  if (!read_packed(ig, "CCVvvVVV!V!vvVVVVVV", &b_magic, &m_magic, &filesize, 
		   &res1, &res2, &offbits, &infohead_size, 
                   &xsize, &ysize, &planes,
		   &bit_count, &compression, &size_image, &xres, &yres, 
		   &clr_used, &clr_important)) {
    i_push_error(0, "file too short to be a BMP file");
    return 0;
  }
  if (b_magic != 'B' || m_magic != 'M' || infohead_size != INFOHEAD_SIZE
      || planes != 1) {
    i_push_error(0, "not a BMP file");
    return 0;
  }

  im_log((aIMCTX, 1, " bmp header: filesize %d offbits %d xsize %d ysize %d planes %d "
          "bit_count %d compression %d size %d xres %d yres %d clr_used %d "
          "clr_important %d\n", (int)filesize, (int)offbits, (int)xsize,
	  (int)ysize, (int)planes, (int)bit_count, (int)compression, 
	  (int)size_image, (int)xres, (int)yres, (int)clr_used, 
          (int)clr_important));

  if (!i_int_check_image_file_limits(xsize, abs(ysize), 3, sizeof(i_sample_t))) {
    im_log((aIMCTX, 1, "i_readbmp_wiol: image size exceeds limits\n"));
    return NULL;
  }
  
  switch (bit_count) {
  case 1:
    im = read_1bit_bmp(ig, xsize, ysize, clr_used, compression, offbits, 
                       allow_incomplete);
    break;

  case 4:
    im = read_4bit_bmp(ig, xsize, ysize, clr_used, compression, offbits, 
                       allow_incomplete);
    break;

  case 8:
    im = read_8bit_bmp(ig, xsize, ysize, clr_used, compression, offbits, 
                       allow_incomplete);
    break;

  case 32:
  case 24:
  case 16:
    im = read_direct_bmp(ig, xsize, ysize, bit_count, clr_used, compression,
                         offbits, allow_incomplete);
    break;

  default:
    im_push_errorf(aIMCTX, 0, "unknown bit count for BMP file (%d)", (int)bit_count);
    return NULL;
  }

  if (im) {
    /* store the resolution */
    if (xres && !yres)
      yres = xres;
    else if (yres && !xres)
      xres = yres;
    if (xres) {
      i_tags_set_float2(&im->tags, "i_xres", 0, xres * 0.0254, 4);
      i_tags_set_float2(&im->tags, "i_yres", 0, yres * 0.0254, 4);
    }
    i_tags_addn(&im->tags, "bmp_compression", 0, compression);
    i_tags_addn(&im->tags, "bmp_important_colors", 0, clr_important);
    i_tags_addn(&im->tags, "bmp_used_colors", 0, clr_used);
    i_tags_addn(&im->tags, "bmp_filesize", 0, filesize);
    i_tags_addn(&im->tags, "bmp_bit_count", 0, bit_count);
    i_tags_add(&im->tags, "i_format", 0, "bmp", 3, 0);
  }

  return im;
}

/*
=back

=head1 IMPLEMENTATION FUNCTIONS

Internal functions used in the implementation.

=over

=item read_packed(ig, format, ...)

Reads from the specified "file" the specified sizes.  The format codes
match those used by perl's pack() function, though only a few are
implemented.  In all cases the vararg arguement is an int *.

Returns non-zero if all of the arguments were read.

=cut
*/
static int
read_packed(io_glue *ig, char *format, ...) {
  unsigned char buf[4];
  va_list ap;
  i_packed_t *p;
  i_packed_t work;
  int code;
  int shrieking; /* format code has a ! flag */

  va_start(ap, format);

  while (*format) {
    p = va_arg(ap, i_packed_t *);

    code = *format++;
    shrieking = *format == '!';
    if (shrieking) ++format;

    switch (code) {
    case 'v':
      if (i_io_read(ig, buf, 2) != 2)
	return 0;
      work = buf[0] + ((i_packed_t)buf[1] << 8);
      if (shrieking)
	*p = (work ^ SIGNBIT16) - SIGNBIT16;
      else
	*p = work;
      break;

    case 'V':
      if (i_io_read(ig, buf, 4) != 4)
	return 0;
      work = buf[0] + (buf[1] << 8) + ((i_packed_t)buf[2] << 16) + ((i_packed_t)buf[3] << 24);
      if (shrieking)
	*p = (work ^ SIGNBIT32) - SIGNBIT32;
      else
	*p = work;
      break;

    case 'C':
      if (i_io_read(ig, buf, 1) != 1)
	return 0;
      *p = buf[0];
      break;

    case 'c':
      if (i_io_read(ig, buf, 1) != 1)
	return 0;
      *p = (char)buf[0];
      break;
      
    case '3': /* extension - 24-bit number */
      if (i_io_read(ig, buf, 3) != 3)
        return 0;
      *p = buf[0] + (buf[1] << 8) + ((i_packed_t)buf[2] << 16);
      break;
      
    default:
      {
	dIMCTXio(ig);
	im_fatal(aIMCTX, 1, "Unknown read_packed format code 0x%02x", code);
      }
    }
  }
  return 1;
}

/*
=item write_packed(ig, format, ...)

Writes packed data to the specified io_glue.

Returns non-zero on success.

=cut
*/

static int
write_packed(io_glue *ig, char *format, ...) {
  unsigned char buf[4];
  va_list ap;
  int i;

  va_start(ap, format);

  while (*format) {
    i = va_arg(ap, i_upacked_t);

    switch (*format) {
    case 'v':
      buf[0] = i & 255;
      buf[1] = i / 256;
      if (i_io_write(ig, buf, 2) == -1)
	return 0;
      break;

    case 'V':
      buf[0] = i & 0xFF;
      buf[1] = (i >> 8) & 0xFF;
      buf[2] = (i >> 16) & 0xFF;
      buf[3] = (i >> 24) & 0xFF;
      if (i_io_write(ig, buf, 4) == -1)
	return 0;
      break;

    case 'C':
    case 'c':
      buf[0] = i & 0xFF;
      if (i_io_write(ig, buf, 1) == -1)
	return 0;
      break;

    default:
      {
	dIMCTXio(ig);
	im_fatal(aIMCTX, 1, "Unknown write_packed format code 0x%02x", *format);
      }
    }
    ++format;
  }
  va_end(ap);

  return 1;
}

/*
=item write_bmphead(ig, im, bit_count, data_size)

Writes a Windows BMP header to the file.

Returns non-zero on success.

=cut
*/

static
int write_bmphead(io_glue *ig, i_img *im, int bit_count, int data_size) {
  double xres, yres;
  int got_xres, got_yres, aspect_only;
  int colors_used = 0;
  int offset = FILEHEAD_SIZE + INFOHEAD_SIZE;
  dIMCTXim(im);

  if (im->xsize > SIGNMAX32 || im->ysize > SIGNMAX32) {
    i_push_error(0, "image too large to write to BMP");
    return 0;
  }

  got_xres = i_tags_get_float(&im->tags, "i_xres", 0, &xres);
  got_yres = i_tags_get_float(&im->tags, "i_yres", 0, &yres);
  if (!i_tags_get_int(&im->tags, "i_aspect_only", 0,&aspect_only))
    aspect_only = 0;
  if (!got_xres) {
    if (!got_yres)
      xres = yres = 72;
    else
      xres = yres;
  }
  else {
    if (!got_yres)
      yres = xres;
  }
  if (xres <= 0 || yres <= 0)
    xres = yres = 72;
  if (aspect_only) {
    /* scale so the smaller value is 72 */
    double ratio;
    if (xres < yres) {
      ratio = 72.0 / xres;
    }
    else {
      ratio = 72.0 / yres;
    }
    xres *= ratio;
    yres *= ratio;
  }
  /* now to pels/meter */
  xres *= 100.0/2.54;
  yres *= 100.0/2.54;

  if (im->type == i_palette_type) {
    colors_used = i_colorcount(im);
    offset += 4 * colors_used;
  }

  if (!write_packed(ig, "CCVvvVVVVvvVVVVVV", 'B', 'M', 
		    (i_upacked_t)(data_size+offset), 
		    (i_upacked_t)0, (i_upacked_t)0, (i_upacked_t)offset,
		    (i_upacked_t)INFOHEAD_SIZE, (i_upacked_t)im->xsize,
		    (i_upacked_t)im->ysize, (i_upacked_t)1, 
		    (i_upacked_t)bit_count, (i_upacked_t)BI_RGB,
		    (i_upacked_t)data_size, 
		    (i_upacked_t)(xres+0.5), (i_upacked_t)(yres+0.5), 
		    (i_upacked_t)colors_used, (i_upacked_t)colors_used)){
    i_push_error(0, "cannot write bmp header");
    return 0;
  }
  if (im->type == i_palette_type) {
    int i;
    i_color c;

    for (i = 0; i < colors_used; ++i) {
      i_getcolors(im, i, &c, 1);
      if (im->channels >= 3) {
	if (!write_packed(ig, "CCCC", (i_upacked_t)(c.channel[2]), 
			  (i_upacked_t)(c.channel[1]), 
			  (i_upacked_t)(c.channel[0]), (i_upacked_t)0)) {
	  i_push_error(0, "cannot write palette entry");
	  return 0;
	}
      }
      else {
	i_upacked_t v = c.channel[0];
	if (!write_packed(ig, "CCCC", v, v, v, 0)) {
	  i_push_error(0, "cannot write palette entry");
	  return 0;
	}
      }
    }
  }

  return 1;
}

/*
=item write_1bit_data(ig, im)

Writes the image data as a 1-bit/pixel image.

Returns non-zero on success.

=cut
*/
static int
write_1bit_data(io_glue *ig, i_img *im) {
  i_palidx *line;
  unsigned char *packed;
  int byte;
  int mask;
  unsigned char *out;
  int line_size = (im->xsize+7) / 8;
  int x, y;
  int unpacked_size;
  dIMCTXim(im);

  /* round up to nearest multiple of four */
  line_size = (line_size + 3) / 4 * 4;

  if (!write_bmphead(ig, im, 1, line_size * im->ysize))
    return 0;

  /* this shouldn't be an issue, but let's be careful */
  unpacked_size = im->xsize + 8;
  if (unpacked_size < im->xsize) {
    i_push_error(0, "integer overflow during memory allocation");
    return 0;
  }
  line = mymalloc(unpacked_size); /* checked 29jun05 tonyc */
  memset(line + im->xsize, 0, 8);

  /* size allocated here is always much smaller than xsize, hence
     can't overflow int */
  packed = mymalloc(line_size); /* checked 29jun05 tonyc */
  memset(packed, 0, line_size);
  
  for (y = im->ysize-1; y >= 0; --y) {
    i_gpal(im, 0, im->xsize, y, line);
    mask = 0x80;
    byte = 0;
    out = packed;
    for (x = 0; x < im->xsize; ++x) {
      if (line[x])
	byte |= mask;
      if ((mask >>= 1) == 0) {
	*out++ = byte;
	byte = 0;
	mask = 0x80;
      }
    }
    if (mask != 0x80) {
      *out++ = byte;
    }
    if (i_io_write(ig, packed, line_size) < 0) {
      myfree(packed);
      myfree(line);
      i_push_error(0, "writing 1 bit/pixel packed data");
      return 0;
    }
  }
  myfree(packed);
  myfree(line);

  if (i_io_close(ig))
    return 0;

  return 1;
}

/*
=item write_4bit_data(ig, im)

Writes the image data as a 4-bit/pixel image.

Returns non-zero on success.

=cut
*/
static int
write_4bit_data(io_glue *ig, i_img *im) {
  i_palidx *line;
  unsigned char *packed;
  unsigned char *out;
  int line_size = (im->xsize+1) / 2;
  int x, y;
  int unpacked_size;
  dIMCTXim(im);

  /* round up to nearest multiple of four */
  line_size = (line_size + 3) / 4 * 4;

  if (!write_bmphead(ig, im, 4, line_size * im->ysize))
    return 0;

  /* this shouldn't be an issue, but let's be careful */
  unpacked_size = im->xsize + 2;
  if (unpacked_size < im->xsize) {
    i_push_error(0, "integer overflow during memory allocation");
    return 0;
  }
  line = mymalloc(unpacked_size); /* checked 29jun05 tonyc */
  memset(line + im->xsize, 0, 2);
  
  /* size allocated here is always much smaller than xsize, hence
     can't overflow int */
  packed = mymalloc(line_size); /* checked 29jun05 tonyc */
  memset(packed, 0, line_size);
  
  for (y = im->ysize-1; y >= 0; --y) {
    i_gpal(im, 0, im->xsize, y, line);
    out = packed;
    for (x = 0; x < im->xsize; x += 2) {
      *out++ = (line[x] << 4) + line[x+1];
    }
    if (i_io_write(ig, packed, line_size) < 0) {
      myfree(packed);
      myfree(line);
      i_push_error(0, "writing 4 bit/pixel packed data");
      return 0;
    }
  }
  myfree(packed);
  myfree(line);

  if (i_io_close(ig))
    return 0;

  return 1;
}

/*
=item write_8bit_data(ig, im)

Writes the image data as a 8-bit/pixel image.

Returns non-zero on success.

=cut
*/
static int
write_8bit_data(io_glue *ig, i_img *im) {
  i_palidx *line;
  int line_size = im->xsize;
  int y;
  int unpacked_size;
  dIMCTXim(im);

  /* round up to nearest multiple of four */
  line_size = (line_size + 3) / 4 * 4;

  if (!write_bmphead(ig, im, 8, line_size * im->ysize))
    return 0;

  /* this shouldn't be an issue, but let's be careful */
  unpacked_size = im->xsize + 4;
  if (unpacked_size < im->xsize) {
    i_push_error(0, "integer overflow during memory allocation");
    return 0;
  }
  line = mymalloc(unpacked_size); /* checked 29jun05 tonyc */
  memset(line + im->xsize, 0, 4);
  
  for (y = im->ysize-1; y >= 0; --y) {
    i_gpal(im, 0, im->xsize, y, line);
    if (i_io_write(ig, line, line_size) < 0) {
      myfree(line);
      i_push_error(0, "writing 8 bit/pixel packed data");
      return 0;
    }
  }
  myfree(line);

  if (i_io_close(ig))
    return 0;

  return 1;
}

/*
=item write_24bit_data(ig, im)

Writes the image data as a 24-bit/pixel image.

Returns non-zero on success.

=cut
*/
static int
write_24bit_data(io_glue *ig, i_img *im) {
  unsigned char *samples;
  int y;
  int line_size = 3 * im->xsize;
  i_color bg;
  dIMCTXim(im);

  i_get_file_background(im, &bg);

  /* just in case we implement a direct format with 2bytes/pixel
     (unlikely though) */
  if (line_size / 3 != im->xsize) {
    i_push_error(0, "integer overflow during memory allocation");
    return 0;
  }
  
  line_size = (line_size + 3) / 4 * 4;
  
  if (!write_bmphead(ig, im, 24, line_size * im->ysize))
    return 0;
  samples = mymalloc(4 * im->xsize);
  memset(samples, 0, line_size);
  for (y = im->ysize-1; y >= 0; --y) {
    unsigned char *samplep = samples;
    int x;
    i_gsamp_bg(im, 0, im->xsize, y, samples, 3, &bg);
    for (x = 0; x < im->xsize; ++x) {
      unsigned char tmp = samplep[2];
      samplep[2] = samplep[0];
      samplep[0] = tmp;
      samplep += 3;
    }
    if (i_io_write(ig, samples, line_size) < 0) {
      i_push_error(0, "writing image data");
      myfree(samples);
      return 0;
    }
  }
  myfree(samples);

  if (i_io_close(ig))
    return 0;

  return 1;
}

/*
=item read_bmp_pal(ig, im, count)

Reads count palette entries from the file and add them to the image.

Returns non-zero on success.

=cut
*/
static int
read_bmp_pal(io_glue *ig, i_img *im, int count) {
  int i;
  i_packed_t r, g, b, x;
  i_color c;
  dIMCTXio(ig);
  
  for (i = 0; i < count; ++i) {
    if (!read_packed(ig, "CCCC", &b, &g, &r, &x)) {
      i_push_error(0, "reading BMP palette");
      return 0;
    }
    c.channel[0] = r;
    c.channel[1] = g;
    c.channel[2] = b;
    if (i_addcolors(im, &c, 1) < 0) {
      i_push_error(0, "out of space in image palette");
      return 0;
    }
  }
  
  return 1;
}

/*
=item read_1bit_bmp(ig, xsize, ysize, clr_used, compression, offbits)

Reads in the palette and image data for a 1-bit/pixel image.

Returns the image or NULL.

=cut
*/
static i_img *
read_1bit_bmp(io_glue *ig, int xsize, int ysize, int clr_used, 
              int compression, long offbits, int allow_incomplete) {
  i_img *im;
  int x, y, lasty, yinc, start_y;
  i_palidx *line, *p;
  unsigned char *packed;
  int line_size = (xsize + 7)/8;
  int bit;
  unsigned char *in;
  long base_offset;
  dIMCTXio(ig);

  if (compression != BI_RGB) {
    im_push_errorf(aIMCTX, 0, "unknown 1-bit BMP compression (%d)", compression);
    return NULL;
  }

  if ((i_img_dim)((i_img_dim_u)xsize + 8) < xsize) { /* if there was overflow */
    /* we check with 8 because we allocate that much for the decoded 
       line buffer */
    i_push_error(0, "integer overflow during memory allocation");
    return NULL;
  }

  /* if xsize+7 is ok then (xsize+7)/8 will be and the minor
     adjustments below won't make it overflow */
  line_size = (line_size+3) / 4 * 4;

  if (ysize > 0) {
    start_y = ysize-1;
    lasty = -1;
    yinc = -1;
  }
  else {
    /* when ysize is -ve it's a top-down image */
    ysize = -ysize;
    start_y = 0;
    lasty = ysize;
    yinc = 1;
  }
  y = start_y;
  if (!clr_used)
    clr_used = 2;
  if (clr_used < 0 || clr_used > 2) {
    im_push_errorf(aIMCTX, 0, "out of range colors used (%d)", clr_used);
    return NULL;
  }

  base_offset = FILEHEAD_SIZE + INFOHEAD_SIZE + clr_used * 4;
  if (offbits < base_offset) {
    im_push_errorf(aIMCTX, 0, "image data offset too small (%ld)", offbits);
    return NULL;
  }

  im = i_img_pal_new(xsize, ysize, 3, 256);
  if (!im)
    return NULL;
  if (!read_bmp_pal(ig, im, clr_used)) {
    i_img_destroy(im);
    return NULL;
  }

  if (offbits > base_offset) {
    /* this will be slow if the offset is large, but that should be
       rare */
    char buffer;
    while (base_offset < offbits) {
      if (i_io_read(ig, &buffer, 1) != 1) {
        i_img_destroy(im);
        i_push_error(0, "failed skipping to image data offset");
        return NULL;
      }
      ++base_offset;
    }
  }
  
  i_tags_add(&im->tags, "bmp_compression_name", 0, "BI_RGB", -1, 0);

  packed = mymalloc(line_size); /* checked 29jun05 tonyc */
  line = mymalloc(xsize+8); /* checked 29jun05 tonyc */
  while (y != lasty) {
    if (i_io_read(ig, packed, line_size) != line_size) {
      myfree(packed);
      myfree(line);
      if (allow_incomplete) {
        i_tags_setn(&im->tags, "i_incomplete", 1);
        i_tags_setn(&im->tags, "i_lines_read", abs(start_y - y));
        return im;
      }
      else {
        i_push_error(0, "failed reading 1-bit bmp data");
        i_img_destroy(im);
        return NULL;
      }
    }
    in = packed;
    bit = 0x80;
    p = line;
    for (x = 0; x < xsize; ++x) {
      *p++ = (*in & bit) ? 1 : 0;
      bit >>= 1;
      if (!bit) {
	++in;
	bit = 0x80;
      }
    }
    i_ppal(im, 0, xsize, y, line);
    y += yinc;
  }

  myfree(packed);
  myfree(line);
  return im;
}

/*
=item read_4bit_bmp(ig, xsize, ysize, clr_used, compression)

Reads in the palette and image data for a 4-bit/pixel image.

Returns the image or NULL.

Hopefully this will be combined with the following function at some
point.

=cut
*/
static i_img *
read_4bit_bmp(io_glue *ig, int xsize, int ysize, int clr_used, 
              int compression, long offbits, int allow_incomplete) {
  i_img *im;
  int x, y, lasty, yinc;
  i_palidx *line, *p;
  unsigned char *packed;
  int line_size = (xsize + 1)/2;
  unsigned char *in;
  int size, i;
  long base_offset;
  int starty;
  dIMCTXio(ig);

  /* line_size is going to be smaller than xsize in most cases (and
     when it's not, xsize is itself small), and hence not overflow */
  line_size = (line_size+3) / 4 * 4;

  if (ysize > 0) {
    starty = ysize-1;
    lasty = -1;
    yinc = -1;
  }
  else {
    /* when ysize is -ve it's a top-down image */
    ysize = -ysize;
    starty = 0;
    lasty = ysize;
    yinc = 1;
  }
  y = starty;
  if (!clr_used)
    clr_used = 16;

  if (clr_used > 16 || clr_used < 0) {
    im_push_errorf(aIMCTX, 0, "out of range colors used (%d)", clr_used);
    return NULL;
  }

  base_offset = FILEHEAD_SIZE + INFOHEAD_SIZE + clr_used * 4;
  if (offbits < base_offset) {
    im_push_errorf(aIMCTX, 0, "image data offset too small (%ld)", offbits);
    return NULL;
  }

  im = i_img_pal_new(xsize, ysize, 3, 256);
  if (!im) /* error should have been pushed already */
    return NULL;
  if (!read_bmp_pal(ig, im, clr_used)) {
    i_img_destroy(im);
    return NULL;
  }

  if (offbits > base_offset) {
    /* this will be slow if the offset is large, but that should be
       rare */
    char buffer;
    while (base_offset < offbits) {
      if (i_io_read(ig, &buffer, 1) != 1) {
        i_img_destroy(im);
        i_push_error(0, "failed skipping to image data offset");
        return NULL;
      }
      ++base_offset;
    }
  }
  
  if (line_size < 260)
    packed = mymalloc(260); /* checked 29jun05 tonyc */
  else
    packed = mymalloc(line_size); /* checked 29jun05 tonyc */
  /* xsize won't approach MAXINT */
  line = mymalloc(xsize+1); /* checked 29jun05 tonyc */
  if (compression == BI_RGB) {
    i_tags_add(&im->tags, "bmp_compression_name", 0, "BI_RGB", -1, 0);
    while (y != lasty) {
      if (i_io_read(ig, packed, line_size) != line_size) {
	myfree(packed);
	myfree(line);
        if (allow_incomplete) {
          i_tags_setn(&im->tags, "i_incomplete", 1);
          i_tags_setn(&im->tags, "i_lines_read", abs(y - starty));
          return im;
        }
        else {
          i_push_error(0, "failed reading 4-bit bmp data");
          i_img_destroy(im);
          return NULL;
        }
      }
      in = packed;
      p = line;
      for (x = 0; x < xsize; x+=2) {
	*p++ = *in >> 4;
	*p++ = *in & 0x0F;
	++in;
      }
      i_ppal(im, 0, xsize, y, line);
      y += yinc;
    }
    myfree(packed);
    myfree(line);
  }
  else if (compression == BI_RLE4) {
    int read_size;
    int count;
    i_img_dim xlimit = (xsize + 1) / 2 * 2; /* rounded up */

    i_tags_add(&im->tags, "bmp_compression_name", 0, "BI_RLE4", -1, 0);
    x = 0;
    while (1) {
      /* there's always at least 2 bytes in a sequence */
      if (i_io_read(ig, packed, 2) != 2) {
        myfree(packed);
        myfree(line);
        if (allow_incomplete) {
          i_tags_setn(&im->tags, "i_incomplete", 1);
          i_tags_setn(&im->tags, "i_lines_read", abs(y - starty));
          return im;
        }
        else {
          i_push_error(0, "missing data during decompression");
          i_img_destroy(im);
          return NULL;
        }
      }
      else if (packed[0]) {
	int count = packed[0];
	if (x + count > xlimit) {
	  /* this file is corrupt */
	  myfree(packed);
	  myfree(line);
	  i_push_error(0, "invalid data during decompression");
	  im_log((aIMCTX, 1, "read 4-bit: scanline overflow x %d + count %d vs xlimit %d (y %d)\n",
		  (int)x, count, (int)xlimit, (int)y));
	  i_img_destroy(im);
	  return NULL;
	}
	/* fill in the line */
	for (i = 0; i < count; i += 2)
	  line[i] = packed[1] >> 4;
	for (i = 1; i < count; i += 2)
	  line[i] = packed[1] & 0x0F;
	i_ppal(im, x, x+count, y, line);
	x += count;
      } else {
        switch (packed[1]) {
        case BMPRLE_ENDOFLINE:
          x = 0;
          y += yinc;
          break;

        case BMPRLE_ENDOFBMP:
          myfree(packed);
          myfree(line);
          return im;

        case BMPRLE_DELTA:
          if (i_io_read(ig, packed, 2) != 2) {
            myfree(packed);
            myfree(line);
            if (allow_incomplete) {
              i_tags_setn(&im->tags, "i_incomplete", 1);
              i_tags_setn(&im->tags, "i_lines_read", abs(y - starty));
              return im;
            }
            else {
              i_push_error(0, "missing data during decompression");
              i_img_destroy(im);
              return NULL;
            }
          }
          x += packed[0];
          y += yinc * packed[1];
          break;

        default:
          count = packed[1];
	  if (x + count > xlimit) {
	    /* this file is corrupt */
	    myfree(packed);
	    myfree(line);
	    i_push_error(0, "invalid data during decompression");
	    im_log((aIMCTX, 1, "read 4-bit: scanline overflow (unpacked) x %d + count %d vs xlimit %d (y %d)\n",
		  (int)x, count, (int)xlimit, (int)y));
	    i_img_destroy(im);
	    return NULL;
	  }
          size = (count + 1) / 2;
          read_size = (size+1) / 2 * 2;
          if (i_io_read(ig, packed, read_size) != read_size) {
            myfree(packed);
            myfree(line);
            if (allow_incomplete) {
              i_tags_setn(&im->tags, "i_incomplete", 1);
              i_tags_setn(&im->tags, "i_lines_read", abs(y - starty));
              return im;
            }
            else {
              i_push_error(0, "missing data during decompression");
              i_img_destroy(im);
              return NULL;
            }
          }
          for (i = 0; i < size; ++i) {
            line[0] = packed[i] >> 4;
            line[1] = packed[i] & 0xF;
            i_ppal(im, x, x+2, y, line);
            x += 2;
          }
          break;
        }
      }
    }
  }
  else { /*if (compression == BI_RLE4) {*/
    myfree(packed);
    myfree(line);
    im_push_errorf(aIMCTX, 0, "unknown 4-bit BMP compression (%d)", compression);
    i_img_destroy(im);
    return NULL;
  }

  return im;
}

/*
=item read_8bit_bmp(ig, xsize, ysize, clr_used, compression, allow_incomplete)

Reads in the palette and image data for a 8-bit/pixel image.

Returns the image or NULL.

=cut
*/
static i_img *
read_8bit_bmp(io_glue *ig, int xsize, int ysize, int clr_used, 
              int compression, long offbits, int allow_incomplete) {
  i_img *im;
  int x, y, lasty, yinc, start_y;
  i_palidx *line;
  int line_size = xsize;
  long base_offset;
  dIMCTXio(ig);

  line_size = (line_size+3) / 4 * 4;
  if (line_size < xsize) { /* if it overflowed (unlikely, but check) */
    i_push_error(0, "integer overflow during memory allocation");
    return NULL;
  }

  if (ysize > 0) {
    start_y = ysize-1;
    lasty = -1;
    yinc = -1;
  }
  else {
    /* when ysize is -ve it's a top-down image */
    ysize = -ysize;
    start_y = 0;
    lasty = ysize;
    yinc = 1;
  }
  y = start_y;
  if (!clr_used)
    clr_used = 256;
  if (clr_used > 256 || clr_used < 0) {
    im_push_errorf(aIMCTX, 0, "out of range colors used (%d)", clr_used);
    return NULL;
  }

  base_offset = FILEHEAD_SIZE + INFOHEAD_SIZE + clr_used * 4;
  if (offbits < base_offset) {
    im_push_errorf(aIMCTX, 0, "image data offset too small (%ld)", offbits);
    return NULL;
  }

  im = i_img_pal_new(xsize, ysize, 3, 256);
  if (!im)
    return NULL;
  if (!read_bmp_pal(ig, im, clr_used)) {
    i_img_destroy(im);
    return NULL;
  }

  if (offbits > base_offset) {
    /* this will be slow if the offset is large, but that should be
       rare */
    char buffer;
    while (base_offset < offbits) {
      if (i_io_read(ig, &buffer, 1) != 1) {
        i_img_destroy(im);
        i_push_error(0, "failed skipping to image data offset");
        return NULL;
      }
      ++base_offset;
    }
  }
  
  line = mymalloc(line_size); /* checked 29jun05 tonyc */
  if (compression == BI_RGB) {
    i_tags_add(&im->tags, "bmp_compression_name", 0, "BI_RGB", -1, 0);
    while (y != lasty) {
      if (i_io_read(ig, line, line_size) != line_size) {
	myfree(line);
        if (allow_incomplete) {
          i_tags_setn(&im->tags, "i_incomplete", 1);
          i_tags_setn(&im->tags, "i_lines_read", abs(start_y - y));
          return im;
        }
        else {
          i_push_error(0, "failed reading 8-bit bmp data");
          i_img_destroy(im);
          return NULL;
        }
      }
      i_ppal(im, 0, xsize, y, line);
      y += yinc;
    }
    myfree(line);
  }
  else if (compression == BI_RLE8) {
    int read_size;
    int count;
    unsigned char packed[2];

    i_tags_add(&im->tags, "bmp_compression_name", 0, "BI_RLE8", -1, 0);
    x = 0;
    while (1) {
      /* there's always at least 2 bytes in a sequence */
      if (i_io_read(ig, packed, 2) != 2) {
        myfree(line);
        if (allow_incomplete) {
          i_tags_setn(&im->tags, "i_incomplete", 1);
          i_tags_setn(&im->tags, "i_lines_read", abs(start_y-y));
          return im;
        }
        else {
          i_push_error(0, "missing data during decompression");
          i_img_destroy(im);
          return NULL;
        }
      }
      if (packed[0]) {
	if (x + packed[0] > xsize) {
	  /* this file isn't incomplete, it's corrupt */
	  myfree(line);
	  i_push_error(0, "invalid data during decompression");
	  i_img_destroy(im);
	  return NULL;
	}
        memset(line, packed[1], packed[0]);
        i_ppal(im, x, x+packed[0], y, line);
        x += packed[0];
      } else {
        switch (packed[1]) {
        case BMPRLE_ENDOFLINE:
          x = 0;
          y += yinc;
          break;

        case BMPRLE_ENDOFBMP:
          myfree(line);
          return im;

        case BMPRLE_DELTA:
          if (i_io_read(ig, packed, 2) != 2) {
            myfree(line);
            if (allow_incomplete) {
              i_tags_setn(&im->tags, "i_incomplete", 1);
              i_tags_setn(&im->tags, "i_lines_read", abs(start_y-y));
              return im;
            }
            else {
              i_push_error(0, "missing data during decompression");
              i_img_destroy(im);
              return NULL;
            }
          }
          x += packed[0];
          y += yinc * packed[1];
          break;

        default:
          count = packed[1];
	  if (x + count > xsize) {
	    /* runs shouldn't cross a line boundary */
	    /* this file isn't incomplete, it's corrupt */
	    myfree(line);
	    i_push_error(0, "invalid data during decompression");
	    i_img_destroy(im);
	    return NULL;
	  }
          read_size = (count+1) / 2 * 2;
          if (i_io_read(ig, line, read_size) != read_size) {
            myfree(line);
            if (allow_incomplete) {
              i_tags_setn(&im->tags, "i_incomplete", 1);
              i_tags_setn(&im->tags, "i_lines_read", abs(start_y-y));
              return im;
            }
            else {
              i_push_error(0, "missing data during decompression");
              i_img_destroy(im);
              return NULL;
            }
          }
          i_ppal(im, x, x+count, y, line);
          x += count;
          break;
        }
      }
    }
  }
  else { 
    myfree(line);
    im_push_errorf(aIMCTX, 0, "unknown 8-bit BMP compression (%d)", compression);
    i_img_destroy(im);
    return NULL;
  }

  return im;
}

struct bm_masks {
  unsigned masks[3];
  int shifts[3];
  int bits[3];
};
static struct bm_masks std_masks[] =
{
  { /* 16-bit */
    { 0076000, 00001740, 00000037, },
    { 10, 5, 0, },
    { 5, 5, 5, }
  },
  { /* 24-bit */
    { 0xFF0000, 0x00FF00, 0x0000FF, },
    {       16,        8,        0, },
    {        8,        8,        8, },
  },
  { /* 32-bit */
    { 0xFF0000, 0x00FF00, 0x0000FF, },
    {       16,        8,        0, },
    {        8,        8,        8, },
  },
};

/* multiplier and shift for converting from N bits to 8 bits */
struct bm_sampconverts {
  int mult;
  int shift;
};
static struct bm_sampconverts samp_converts[] = {
  { 0xff, 0 }, /* 1 bit samples */
  { 0x55, 0 },
  { 0111, 1 },
  { 0x11, 0 },
  { 0x21, 2 },
  { 0x41, 4 },
  { 0x81, 6 }  /* 7 bit samples */
};

/*
=item read_direct_bmp(ig, xsize, ysize, bit_count, clr_used, compression, allow_incomplete)

Skips the palette and reads in the image data for a direct colour image.

Returns the image or NULL.

=cut
*/
static i_img *
read_direct_bmp(io_glue *ig, int xsize, int ysize, int bit_count, 
                int clr_used, int compression, long offbits, 
                int allow_incomplete) {
  i_img *im;
  int x, y, starty, lasty, yinc;
  i_color *line, *p;
  int pix_size = bit_count / 8;
  int line_size = xsize * pix_size;
  struct bm_masks masks;
  char unpack_code[2] = "";
  int i;
  int extras;
  char junk[4];
  const char *compression_name;
  int bytes;
  long base_offset = FILEHEAD_SIZE + INFOHEAD_SIZE;
  dIMCTXio(ig);
  
  unpack_code[0] = *("v3V"+pix_size-2);
  unpack_code[1] = '\0';

  line_size = (line_size+3) / 4 * 4;
  extras = line_size - xsize * pix_size;

  if (ysize > 0) {
    starty = ysize-1;
    lasty = -1;
    yinc = -1;
  }
  else {
    /* when ysize is -ve it's a top-down image */
    ysize = -ysize;
    starty = 0;
    lasty = ysize;
    yinc = 1;
  }
  y = starty;
  if (compression == BI_RGB) {
    compression_name = "BI_RGB";
    masks = std_masks[pix_size-2];
    
    /* there's a potential "palette" after the header */
    for (i = 0; i < clr_used; ++clr_used) {
      char buf[4];
      if (i_io_read(ig, buf, 4) != 4) {
        i_push_error(0, "skipping colors");
        return 0;
      }
      base_offset += 4;
    }
  }
  else if (compression == BI_BITFIELDS) {
    int pos;
    unsigned bits;
    compression_name = "BI_BITFIELDS";

    for (i = 0; i < 3; ++i) {
      i_packed_t rmask;
      if (!read_packed(ig, "V", &rmask)) {
        i_push_error(0, "reading pixel masks");
        return 0;
      }
      if (rmask == 0) {
	im_push_errorf(aIMCTX, 0, "Zero mask for channel %d", i);
	return NULL;
      }
      masks.masks[i] = rmask;
      /* work out a shift for the mask */
      pos = 0;
      bits = masks.masks[i];
      while (!(bits & 1)) {
        ++pos;
        bits >>= 1;
      }
      masks.shifts[i] = pos;
      pos = 0;
      while (bits & 1) {
	++pos;
	bits >>= 1;
      }
      masks.bits[i] = pos;
      /*fprintf(stderr, "%d: mask %08x shift %d bits %d\n", i, masks.masks[i], masks.shifts[i], masks.bits[i]);*/
    }
    /* account for the masks */
    base_offset += 3 * 4;
  }
  else {
    im_push_errorf(aIMCTX, 0, "unknown 24-bit BMP compression (%d)", compression);
    return NULL;
  }

  if (offbits < base_offset) {
    im_push_errorf(aIMCTX, 0, "image data offset too small (%ld)", offbits);
    return NULL;
  }

  if (offbits > base_offset) {
    /* this will be slow if the offset is large, but that should be
       rare */
    char buffer;
    while (base_offset < offbits) {
      if (i_io_read(ig, &buffer, 1) != 1) {
        i_push_error(0, "failed skipping to image data offset");
        return NULL;
      }
      ++base_offset;
    }
  }
  
  im = i_img_empty(NULL, xsize, ysize);
  if (!im)
    return NULL;

  i_tags_add(&im->tags, "bmp_compression_name", 0, compression_name, -1, 0);

  /* I wasn't able to make this overflow in testing, but better to be
     safe */
  bytes = sizeof(i_color) * xsize;
  if (bytes / sizeof(i_color) != xsize) {
    i_img_destroy(im);
    i_push_error(0, "integer overflow calculating buffer size");
    return NULL;
  }
  line = mymalloc(bytes); /* checked 29jun05 tonyc */
  while (y != lasty) {
    p = line;
    for (x = 0; x < xsize; ++x) {
      i_packed_t pixel;
      if (!read_packed(ig, unpack_code, &pixel)) {
        myfree(line);
        if (allow_incomplete) {
          i_tags_setn(&im->tags, "i_incomplete", 1);
          i_tags_setn(&im->tags, "i_lines_read", abs(starty - y));
          return im;
        }
        else {
          i_push_error(0, "failed reading image data");
          i_img_destroy(im);
          return NULL;
        }
      }
      for (i = 0; i < 3; ++i) {
	int sample = (pixel & masks.masks[i]) >> masks.shifts[i];
	int bits = masks.bits[i];
	if (bits < 8) {
	  sample = (sample * samp_converts[bits-1].mult) >> samp_converts[bits-1].shift;
	}
	else if (bits) {
	  sample >>= bits - 8;
	}
	p->channel[i] = sample;
      }
      ++p;
    }
    i_plin(im, 0, xsize, y, line);
    if (extras)
      i_io_read(ig, junk, extras);
    y += yinc;
  }
  myfree(line);

  return im;
}

/*
=head1 SEE ALSO

Imager(3)

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=head1 RESTRICTIONS

Cannot save as compressed BMP.

=head1 BUGS

Doesn't handle OS/2 bitmaps.

16-bit/pixel images haven't been tested.  (I need an image).

BI_BITFIELDS compression hasn't been tested (I need an image).

The header handling for paletted images needs to be refactored

=cut
*/
