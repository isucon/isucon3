#include "imext.h"
#include "msicon.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdarg.h>
#include <assert.h>

static
int read_packed(io_glue *ig, const char *format, ...);
static int 
read_palette(ico_reader_t *file, ico_image_t *image, int *error);
static int 
read_24bit_data(ico_reader_t *file, ico_image_t *image, int *error);
static int 
read_32bit_data(ico_reader_t *file, ico_image_t *image, int *error);
static int 
read_8bit_data(ico_reader_t *file, ico_image_t *image, int *error);
static int 
read_4bit_data(ico_reader_t *file, ico_image_t *image, int *error);
static int 
read_1bit_data(ico_reader_t *file, ico_image_t *image, int *error);
static int 
read_mask(ico_reader_t *file, ico_image_t *image, int *error);
static int
ico_write_validate(ico_image_t const *images, int image_count, int *error);
static int
ico_image_size(ico_image_t const *image, int *bits, int *colors);
static int
write_packed(i_io_glue_t *ig, char const *format, ...);
static int
write_palette(i_io_glue_t *ig, ico_image_t const *image, int *error);
static int
write_32_bit(i_io_glue_t *ig, ico_image_t const *image, int *error);
static int
write_8_bit(i_io_glue_t *ig, ico_image_t const *image, int *error);
static int
write_4_bit(i_io_glue_t *ig, ico_image_t const *image, int *error);
static int
write_1_bit(i_io_glue_t *ig, ico_image_t const *image, int *error);
static int
write_mask(i_io_glue_t *ig, ico_image_t const *image, int *error);

typedef struct {
  int width;
  int height;
  long offset;
  long size;
  int hotspot_x, hotspot_y;
} ico_reader_image_entry;

/* this was previously declared, now define it */
struct ico_reader_tag {
  /* the file we're dealing with */
  i_io_glue_t *ig;

  /* number of images in the file */
  int count;

  /* type of resource - 1=icon, 2=cursor */
  int type;

  /* image information from the header */
  ico_reader_image_entry *images;
};

/*
=head1 NAME 

msicon.c - functions for working with .ICO files.

=head1 SYNOPSIS

  // reading
  int error;
  ico_reader_t *file = ico_reader_open(ig, &error);
  if (!file) {
    char buffer[100];
    ico_error_message(error, buffer, sizeof(buffer));
    fputs(buffer, stderr);
    exit(1);
  }
  int count = ico_image_count(file);
  for (i = 0; i < count; ++i) {
    ico_image_t *im = ico_image_read(file, index);
    printf("%d x %d image %d\n", im->width, im->height, 
           im->direct ? "direct" : "paletted");
    ico_image_release(im);
  }
  ico_reader_close(file);

=head1 DESCRIPTION

This is intended as a general interface to reading MS Icon files, and
is written to be independent of Imager, even though it is part of
Imager.  You just need to supply something that acts like Imager's
io_glue.

It relies on icon images being generally small, and reads the entire
image into memory when reading.

=head1 READING ICON FILES

=over

=item ico_reader_open(ig, &error)

Parameters:

=over

=item *

io_glue *ig - an Imager IO object.  This must be seekable.

=item *

int *error - pointer to an integer which an error code will be
returned in on failure.

=back

=cut
*/

ico_reader_t *
ico_reader_open(i_io_glue_t *ig, int *error) {
  long res1, type, count;
  ico_reader_t *file = NULL;
  int i;

  if (!read_packed(ig, "www", &res1, &type, &count)) {
    *error = ICOERR_Short_File;
    return NULL;
  }
  if (res1 != 0 || (type != 1 && type != 2) || count == 0) {
    *error = ICOERR_Invalid_File;
    return NULL;
  }

  file = malloc(sizeof(ico_reader_t));
  if (!file) {
    *error = ICOERR_Out_Of_Memory;
    return NULL;
  }
  file->count = count;
  file->type = type;
  file->ig = ig;
  file->images = malloc(sizeof(ico_reader_image_entry) * count);
  if (file->images == NULL) {
    *error = ICOERR_Out_Of_Memory;
    free(file);
    return NULL;
  }

  for (i = 0; i < count; ++i) {
    long width, height, bytes_in_res, image_offset;

    ico_reader_image_entry *image = file->images + i;
    if (type == ICON_ICON) {
      if (!read_packed(ig, "bb xxxxxx dd", &width, &height, &bytes_in_res, 
		       &image_offset)) {
	free(file->images);
	free(file);
	*error = ICOERR_Short_File;
	return NULL;
      }
      image->hotspot_x = image->hotspot_y = 0;
    }
    else {
      long hotspot_x, hotspot_y;

      if (!read_packed(ig, "bb xx ww dd", &width, &height, 
		       &hotspot_x, &hotspot_y, &bytes_in_res, 
		       &image_offset)) {
	free(file->images);
	free(file);
	*error = ICOERR_Short_File;
	return NULL;
      }
      image->hotspot_x = hotspot_x;
      image->hotspot_y = hotspot_y;
    }

    /* a width or height of zero here indicates a width/height of 256 */
    image->width = width ? width : 256;
    image->height = height ? height : 256;
    image->offset = image_offset;
    image->size = bytes_in_res;
  }

  return file;
}

/*
=item ico_image_count

  // number of images in the file
  count = ico_image_count(file);

=cut
*/

int
ico_image_count(ico_reader_t *file) {
  return file->count;
}

/*
=item ico_type

  // type of file - ICON_ICON for icon, ICON_CURSOR for cursor
  type = ico_type(file);

=cut
*/

int
ico_type(ico_reader_t *file) {
  return file->type;
}

/*
=item ico_image_read

Read an image from the file given it's index.

=cut
*/

ico_image_t *
ico_image_read(ico_reader_t *file, int index, int *error) {
  io_glue *ig = file->ig;
  ico_reader_image_entry *im;
  long bi_size, width, height, planes, bit_count;
  ico_image_t *result;

  if (index < 0 || index >= file->count) {
    *error = ICOERR_Bad_Image_Index;
    return NULL;
  }

  im = file->images + index;
  if (i_io_seek(ig, im->offset, SEEK_SET) != im->offset) {
    *error = ICOERR_File_Error;
    return NULL;
  }

  if (!read_packed(ig, "dddww xxxx xxxx xxxx xxxx xxxx xxxx", &bi_size, 
		   &width, &height, &planes, &bit_count)) {
    *error = ICOERR_Short_File;
    return NULL;
  }

  /* the bitmapinfoheader height includes the height of 
     the and and xor masks */
  if (bi_size != 40 || width != im->width || height != im->height * 2
      || planes != 1) { /* don't know how to handle planes != 1 */
    *error = ICOERR_Invalid_File;
    return NULL;
  }

  if (bit_count != 1 && bit_count != 4 && bit_count != 8
      && bit_count != 24 && bit_count != 32) {
    *error = ICOERR_Unknown_Bits;
    return 0;
  }

  result = malloc(sizeof(ico_image_t));
  if (!result) {
    *error = ICOERR_Out_Of_Memory;
    return NULL;
  }
  result->width = width;
  result->height = im->height;
  result->direct = bit_count > 8;
  result->bit_count = bit_count;
  result->palette = NULL;
  result->image_data = NULL;
  result->mask_data = NULL;
  result->hotspot_x = im->hotspot_x;
  result->hotspot_y = im->hotspot_y;
    
  if (bit_count == 32) {
    result->palette_size = 0;

    result->image_data = malloc(result->width * result->height * sizeof(ico_color_t));
    if (!result->image_data) {
      free(result);
      *error = ICOERR_Out_Of_Memory;
      return NULL;
    }
    if (!read_32bit_data(file, result, error)) {
      free(result->image_data);
      free(result);
      return NULL;
    }
  }
  else if (bit_count == 24) {
    result->palette_size = 0;

    result->image_data = malloc(result->width * result->height * sizeof(ico_color_t));
    if (!result->image_data) {
      free(result);
      *error = ICOERR_Out_Of_Memory;
      return NULL;
    }
    if (!read_24bit_data(file, result, error)) {
      free(result->image_data);
      free(result);
      return NULL;
    }
  }
  else {
    int read_result;

    result->palette_size = 1 << bit_count;
    result->palette = malloc(sizeof(ico_color_t) * result->palette_size);
    if (!result->palette) {
      free(result);
      *error = ICOERR_Out_Of_Memory;
      return NULL;
    }

    result->image_data = malloc(result->width * result->height);
    if (!result->image_data) {
      *error = ICOERR_Out_Of_Memory;
      free(result->palette);
      free(result);
      return 0;
    }      
    
    if (!read_palette(file, result, error)) {
      free(result->palette);
      free(result->image_data);
      free(result);
      return 0;
    }

    switch (bit_count) {
    case 1:
      read_result = read_1bit_data(file, result, error);
      break;

    case 4:
      read_result = read_4bit_data(file, result, error);
      break;
      
    case 8:
      read_result = read_8bit_data(file, result, error);
      break;

    default:
      assert(0); /* this can't happen in theory */
      read_result = 0;
      break;
    }

    if (!read_result) {
      free(result->palette);
      free(result->image_data);
      free(result);
      return 0;
    }
  }

  result->mask_data = malloc(result->width * result->height);
  if (!result->mask_data) {
    *error = ICOERR_Out_Of_Memory;
    free(result->palette);
    free(result->image_data);
    free(result);
    return 0;
  }

  if (!read_mask(file, result, error)) {
    free(result->mask_data);
    free(result->palette);
    free(result->image_data);
    free(result);
    return 0;
  }

  return result;
}

/*
=item ico_image_release

Release an image structure returned by ico_image_read.

=cut
*/

void
ico_image_release(ico_image_t *image) {
  free(image->mask_data);
  free(image->palette);
  free(image->image_data);
  free(image);
}

/*
=item ico_reader_close

Releases the read file structure.

=cut
*/

void
ico_reader_close(ico_reader_t *file) {
  i_io_close(file->ig);
  free(file->images);
  free(file);
}

/*
=back

=head1 WRITING ICON FILES

=over

=item ico_write(ig, images, image_count, type, &error)

Parameters:

=over

=item *

io_glue *ig - an Imager IO object.  This only needs to implement
writing for ico_write()

=item *

ico_image_t *images - array of images to be written.

=item *

int image_count - number of images

=item *

int type - must be ICON_ICON or ICON_CURSOR

=item *

int *error - set to an error code on failure.

=back

Returns non-zero on success.

=cut
*/

int
ico_write(i_io_glue_t *ig, ico_image_t const *images, int image_count,
	  int type, int *error) {
  int i;
  int start_offset = 6 + 16 * image_count;
  int current_offset = start_offset;

  if (type != ICON_ICON && type != ICON_CURSOR) {
    *error = ICOERR_Bad_File_Type;
    return 0;
  }

  /* validate the images */
  if (!ico_write_validate(images, image_count, error))
    return 0;

  /* write the header */
  if (!write_packed(ig, "www", 0, type, image_count)) {
    *error = ICOERR_Write_Failure;
    return 0;
  }

  /* work out the offsets of each image */
  for (i = 0; i < image_count; ++i) {
    ico_image_t const *image = images + i;
    int bits, colors;
    int size = ico_image_size(image, &bits, &colors);
    int width_byte = image->width == 256 ? 0 : image->width;
    int height_byte = image->height == 256 ? 0 : image->height;

    if (type == ICON_ICON) {
      if (!write_packed(ig, "bbbbwwdd", width_byte, height_byte,
			colors, 0, 1, bits, (unsigned long)size, 
			(unsigned long)current_offset)) {
	*error = ICOERR_Write_Failure;
	return 0;
      }
    }
    else {
      int hotspot_x = image->hotspot_x;
      int hotspot_y = image->hotspot_y;

      if (hotspot_x < 0)
	hotspot_x = 0;
      else if (hotspot_x >= image->width)
	hotspot_x = image->width - 1;
      if (hotspot_y < 0)
	hotspot_y = 0;
      else if (hotspot_y >= image->height)
	hotspot_y = image->height - 1;

      if (!write_packed(ig, "bbbbwwdd", width_byte, height_byte,
			colors, 0, hotspot_x, hotspot_y, (unsigned long)size, 
			(unsigned long)current_offset)) {
	*error = ICOERR_Write_Failure;
	return 0;
      }
    }
    current_offset += size;
  }
  
  /* write out each image */
  for (i = 0; i < image_count; ++i) {
    ico_image_t const *image = images + i;

    if (image->direct) {
      if (!write_32_bit(ig, image, error))
	return 0;
    }
    else {
      if (image->palette_size <= 2) {
	if (!write_1_bit(ig, image, error))
	  return 0;
      }
      else if (image->palette_size <= 16) {
	if (!write_4_bit(ig, image, error))
	  return 0;
      }
      else {
	if (!write_8_bit(ig, image, error))
	  return 0;
      }
    }
    if (!write_mask(ig, image, error))
      return 0;
  }

  return 1;
}

/*
=back

=head1 ERROR MESSAGES

=over

=item ico_error_message

Converts an error code into an error message.

=cut
*/

size_t
ico_error_message(int error, char *buffer, size_t buffer_size) {
  char const *msg;
  size_t size;

  switch (error) {
  case ICOERR_Short_File:
    msg = "Short read";
    break;

  case ICOERR_File_Error:
    msg = "I/O error";
    break;

  case ICOERR_Write_Failure:
    msg = "Write failure";
    break;

  case ICOERR_Invalid_File:
    msg = "Not an icon file";
    break;

  case ICOERR_Unknown_Bits:
    msg = "Unknown value for bits/pixel";
    break;

  case ICOERR_Bad_Image_Index:
    msg = "Image index out of range";
    break;

  case ICOERR_Bad_File_Type:
    msg = "Bad file type parameter";
    break;

  case ICOERR_Invalid_Width:
    msg = "Invalid image width";
    break;

  case ICOERR_Invalid_Height:
    msg = "Invalid image height";
    break;
    
  case ICOERR_Invalid_Palette:
    msg = "Invalid Palette";
    break;

  case ICOERR_No_Data:
    msg = "No image data in image supplied to ico_write";
    break;

  case ICOERR_Out_Of_Memory:
    msg = "Out of memory";
    break;

  default:
    msg = "Unknown error code";
    break;
  }

  size = strlen(msg) + 1;
  if (size > buffer_size)
    size = buffer_size;
  memcpy(buffer, msg, size);
  buffer[size-1] = '\0';

  return size;
}

/*
=back

=head1 PRIVATE FUNCTIONS

=over

=item read_packed

Reads packed data from a stream, unpacking it.

=cut
*/

static
int read_packed(io_glue *ig, const char *format, ...) {
  unsigned char buffer[100];
  va_list ap;
  long *p;
  int size;
  const char *formatp;
  unsigned char *bufp;

  /* read efficiently, work out the size of the buffer */
  size = 0;
  formatp = format;
  while (*formatp) {
    switch (*formatp++) {
    case 'b': 
    case 'x': size += 1; break;
    case 'w': size += 2; break;
    case 'd': size += 4; break;
    case ' ': break; /* space to separate components */
    default:
      fprintf(stderr, "invalid unpack char in %s\n", format);
      exit(1);
    }
  }

  if (size > sizeof(buffer)) {
    /* catch if we need a bigger buffer, but 100 is plenty */
    fprintf(stderr, "format %s too long for buffer\n", format);
    exit(1);
  }

  if (i_io_read(ig, buffer, size) != size) {
    return 0;
  }

  va_start(ap, format);

  bufp = buffer;
  while (*format) {

    switch (*format) {
    case 'b':
      p = va_arg(ap, long *);
      *p = *bufp++;
      break;

    case 'w':
      p = va_arg(ap, long *);
      *p = bufp[0] + (bufp[1] << 8);
      bufp += 2;
      break;

    case 'd':
      p = va_arg(ap, long *);
      *p = bufp[0] + (bufp[1] << 8) + (bufp[2] << 16) + (bufp[3] << 24);
      bufp += 4;
      break;

    case 'x':
      ++bufp; /* skip a byte */
      break;

    case ' ':
      /* nothing to do */
      break;
    }
    ++format;
  }
  return 1;
}

/*
=item read_palette

Reads the palette data for an icon image.

=cut
*/

static
int
read_palette(ico_reader_t *file, ico_image_t *image, int *error) {
  int palette_bytes = image->palette_size * 4;
  unsigned char *read_buffer = malloc(palette_bytes);
  unsigned char *inp;
  ico_color_t *outp;
  int i;

  if (!read_buffer) {
    *error = ICOERR_Out_Of_Memory;
    return 0;
  }

  if (i_io_read(file->ig, read_buffer, palette_bytes) != palette_bytes) {
    *error = ICOERR_Short_File;
    free(read_buffer);
    return 0;
  }

  inp = read_buffer;
  outp = image->palette;
  for (i = 0; i < image->palette_size; ++i) {
    outp->b = *inp++;
    outp->g = *inp++;
    outp->r = *inp++;
    outp->a = 255;
    ++inp;
    ++outp;
  }
  free(read_buffer);

  return 1;
}

/*
=item read_32bit_data

Reads 32 bit image data.

=cut
*/

static
int
read_32bit_data(ico_reader_t *file, ico_image_t *image, int *error) {
  int line_bytes = image->width * 4;
  unsigned char *buffer = malloc(line_bytes);
  int y;
  int x;
  unsigned char *inp;
  ico_color_t *outp;

  if (!buffer) {
    *error = ICOERR_Out_Of_Memory;
    return 0;
  }

  for (y = image->height - 1; y >= 0; --y) {
    if (i_io_read(file->ig, buffer, line_bytes) != line_bytes) {
      free(buffer);
      *error = ICOERR_Short_File;
      return 0;
    }
    outp = image->image_data;
    outp += y * image->width;
    inp = buffer;
    for (x = 0; x < image->width; ++x) {
      outp->b = inp[0];
      outp->g = inp[1];
      outp->r = inp[2];
      outp->a = inp[3];
      ++outp;
      inp += 4;
    }
  }
  free(buffer);

  return 1;
}

/*
=item read_24bit_data

Reads 24 bit image data.

=cut
*/

static
int
read_24bit_data(ico_reader_t *file, ico_image_t *image, int *error) {
  int line_bytes = image->width * 3;
  unsigned char *buffer;
  int y;
  int x;
  unsigned char *inp;
  ico_color_t *outp;

  line_bytes = (line_bytes + 3) / 4 * 4;

  buffer = malloc(line_bytes);

  if (!buffer) {
    *error = ICOERR_Out_Of_Memory;
    return 0;
  }

  for (y = image->height - 1; y >= 0; --y) {
    if (i_io_read(file->ig, buffer, line_bytes) != line_bytes) {
      free(buffer);
      *error = ICOERR_Short_File;
      return 0;
    }
    outp = image->image_data;
    outp += y * image->width;
    inp = buffer;
    for (x = 0; x < image->width; ++x) {
      outp->b = inp[0];
      outp->g = inp[1];
      outp->r = inp[2];
      outp->a = 255;
      ++outp;
      inp += 3;
    }
  }
  free(buffer);

  return 1;
}

/*
=item read_8bit_data

Reads 8 bit image data.

=cut
*/

static
int
read_8bit_data(ico_reader_t *file, ico_image_t *image, int *error) {
  int line_bytes = (image->width + 3) / 4 * 4;
  unsigned char *buffer = malloc(line_bytes);
  int y;
  int x;
  unsigned char *inp, *outp;

  if (!buffer) {
    *error = ICOERR_Out_Of_Memory;
    return 0;
  }

  for (y = image->height - 1; y >= 0; --y) {
    outp = image->image_data;
    outp += y * image->width;
    if (i_io_read(file->ig, buffer, line_bytes) != line_bytes) {
      free(buffer);
      *error = ICOERR_Short_File;
      return 0;
    }
    for (x = 0, inp = buffer; x < image->width; ++x) {
      *outp++ = *inp++;
    }
  }
  free(buffer);

  return 1;
}

/*
=item read_4bit_data

Reads 4 bit image data.

=cut
*/

static
int
read_4bit_data(ico_reader_t *file, ico_image_t *image, int *error) {
  /* 2 pixels per byte, rounded up to the nearest dword */
  int line_bytes = ((image->width + 1) / 2 + 3) / 4 * 4;
  unsigned char *read_buffer = malloc(line_bytes);
  int y;
  int x;
  unsigned char *inp, *outp;

  if (!read_buffer) {
    *error = ICOERR_Out_Of_Memory;
    return 0;
  }

  for (y = image->height - 1; y >= 0; --y) {
    if (i_io_read(file->ig, read_buffer, line_bytes) != line_bytes) {
      free(read_buffer);
      *error = ICOERR_Short_File;
      return 0;
    }
    
    outp = image->image_data;
    outp += y * image->width;
    inp = read_buffer;
    for (x = 0; x < image->width; ++x) {
      /* yes, this is kind of ugly */
      if (x & 1) {
	*outp++ = *inp++ & 0x0F;
      }
      else {
	*outp++ = *inp >> 4;
      }
    }
  }
  free(read_buffer);

  return 1;
}

/*
=item read_1bit_data

Reads 1 bit image data.

=cut
*/

static
int
read_1bit_data(ico_reader_t *file, ico_image_t *image, int *error) {
  /* 8 pixels per byte, rounded up to the nearest dword */
  int line_bytes = ((image->width + 7) / 8 + 3) / 4 * 4;
  unsigned char *read_buffer = malloc(line_bytes);
  int y;
  int x;
  unsigned char *inp, *outp;

  if (!read_buffer) {
    *error = ICOERR_Out_Of_Memory;
    return 0;
  }

  for (y = image->height - 1; y >= 0; --y) {
    if (i_io_read(file->ig, read_buffer, line_bytes) != line_bytes) {
      free(read_buffer);
      *error = ICOERR_Short_File;
      return 0;
    }
    
    outp = image->image_data;
    outp += y * image->width;
    inp = read_buffer;
    for (x = 0; x < image->width; ++x) {
      *outp++ = (*inp >> (7 - (x & 7))) & 1;
      if ((x & 7) == 7)
	++inp;
    }
  }
  free(read_buffer);

  return 1;
}

/* this is very similar to the 1 bit reader <sigh> */
/*
=item read_mask

Reads the AND mask from an icon image.

=cut
*/

static
int
read_mask(ico_reader_t *file, ico_image_t *image, int *error) {
  /* 8 pixels per byte, rounded up to the nearest dword */
  int line_bytes = ((image->width + 7) / 8 + 3) / 4 * 4;
  unsigned char *read_buffer = malloc(line_bytes);
  int y;
  int x;
  int mask;
  unsigned char *inp, *outp;

  if (!read_buffer) {
    *error = ICOERR_Out_Of_Memory;
    return 0;
  }

  for (y = image->height - 1; y >= 0; --y) {
    if (i_io_read(file->ig, read_buffer, line_bytes) != line_bytes) {
      free(read_buffer);
      *error = ICOERR_Short_File;
      return 0;
    }
    
    outp = image->mask_data + y * image->width;
    inp = read_buffer;
    mask = 0x80;
    for (x = 0; x < image->width; ++x) {
      *outp++ = (*inp & mask) ? 1 : 0;
      mask >>= 1;
      if (!mask) {
        mask = 0x80;
	++inp;
      }
    }
  }
  free(read_buffer);

  return 1;
}

/*
=item ico_write_validate

Check each image to make sure it can go into an icon file.

=cut
*/

static int
ico_write_validate(ico_image_t const *images, int image_count, int *error) {
  int i;

  for (i = 0; i < image_count; ++i) {
    ico_image_t const *image = images + i;

    if (image->width < 1 || image->width > 256) {
      *error = ICOERR_Invalid_Width;
      return 0;
    }
    if (image->height < 1 || image->height > 256) {
      *error = ICOERR_Invalid_Height;
      return 0;
    }
    if (!image->image_data) {
      *error = ICOERR_No_Data;
      return 0;
    }
    if (!image->direct) {
      if (image->palette_size < 0 || image->palette_size > 256 
	  || !image->palette) {
	*error = ICOERR_Invalid_Palette;
	return 0;
      }
    }
  }

  return 1;
}

/*
=item ico_image_size

Calculate how much space the icon takes up in the file.

=cut
*/

static int
ico_image_size(ico_image_t const *image, int *bits, int *colors) {
  int size = 40; /* start with the BITMAPINFOHEADER */

  /* add in the image area */
  if (image->direct) {
    *bits = 32;
    *colors = 0;
    size += image->width * 4 * image->height;
  }
  else {
    if (image->palette_size <= 2) {
      *bits = 1;
      *colors = 2;
    }
    else if (image->palette_size <= 16) {
      *bits = 4;
      *colors = 16;
    }
    else {
      *bits = 8;
      *colors = 0;
    }

    /* palette size */
    size += *colors * 4;

    /* image data size */
    size += (image->width * *bits + 31) / 32 * 4 * image->height;
  }

  /* add in the mask */
  size += (image->width + 31) / 32 * 4 * image->height;

  return size;
}

/*
=item write_packed

Pack numbers given a format to a stream.

=cut
*/

static int 
write_packed(i_io_glue_t *ig, char const *format, ...) {
  unsigned char buffer[100];
  va_list ap;
  unsigned long p;
  int size;
  const char *formatp;
  unsigned char *bufp;

  /* write efficiently, work out the size of the buffer */
  size = 0;
  formatp = format;
  while (*formatp) {
    switch (*formatp++) {
    case 'b': size++; break;
    case 'w': size += 2; break;
    case 'd': size += 4; break;
    case ' ': break; /* space to separate components */
    default:
      fprintf(stderr, "invalid unpack char in %s\n", format);
      exit(1);
    }
  }

  if (size > sizeof(buffer)) {
    /* catch if we need a bigger buffer, but 100 is plenty */
    fprintf(stderr, "format %s too long for buffer\n", format);
    exit(1);
  }

  va_start(ap, format);

  bufp = buffer;
  while (*format) {

    switch (*format) {
    case 'b':
      p = va_arg(ap, int);
      *bufp++ = p;
      break;

    case 'w':
      p = va_arg(ap, int);
      *bufp++ = p & 0xFF;
      *bufp++  = (p >> 8) & 0xFF;
      break;

    case 'd':
      p = va_arg(ap, unsigned long);
      *bufp++ = p & 0xFF;
      *bufp++ = (p >> 8) & 0xFF;
      *bufp++ = (p >> 16) & 0xFF;
      *bufp++ = (p >> 24) & 0xFF;
      break;

    case ' ':
      /* nothing to do */
      break;
    }
    ++format;
  }

  if (i_io_write(ig, buffer, size) != size)
    return 0;
  
  return 1;
}

/*
=item write_palette

Write the palette for an icon.

=cut
*/

static int
write_palette(i_io_glue_t *ig, ico_image_t const *image, int *error) {
  int full_size = image->palette_size;
  unsigned char *writebuf, *outp;
  ico_color_t *colorp;
  int i;

  if (image->palette_size <= 2)
    full_size = 2;
  else if (image->palette_size <= 16)
    full_size = 16;
  else
    full_size = 256;

  writebuf = calloc(full_size, 4);
  if (!writebuf) {
    *error = ICOERR_Out_Of_Memory;
    return 0;
  }
  outp = writebuf;
  colorp = image->palette;
  for (i = 0; i < image->palette_size; ++i) {
    *outp++ = colorp->b;
    *outp++ = colorp->g;
    *outp++ = colorp->r;
    *outp++ = 0xFF;
    ++colorp;
  }
  for (; i < full_size; ++i) {
    *outp++ = 0;
    *outp++ = 0;
    *outp++ = 0;
    *outp++ = 0;
  }

  if (i_io_write(ig, writebuf, full_size * 4) != full_size * 4) {
    *error = ICOERR_Write_Failure;
    free(writebuf);
    return 0;
  }

  free(writebuf);

  return 1;
}

/*
=item write_bitmapinfoheader

Write the BITMAPINFOHEADER for an icon image.

=cut
*/

static int
write_bitmapinfoheader(i_io_glue_t *ig, ico_image_t const *image, int *error,
			int bit_count, int clr_used) {
  if (!write_packed(ig, "d dd w w d d dd dd", 
		    40UL, /* biSize */
		    (unsigned long)image->width, 
                    (unsigned long)2 * image->height, /* biWidth/biHeight */
		    1, bit_count, /* biPlanes, biBitCount */
		    0UL, 0UL, /* biCompression, biSizeImage */
		    0UL, 0UL, /* bi(X|Y)PetsPerMeter */
		    (unsigned long)clr_used, /* biClrUsed */
                    0UL)) { /* biClrImportant */
    *error = ICOERR_Write_Failure;
    return 0;
  }

  return 1;
}

/*
=item write_32_bit

Write 32-bit image data to the icon.

=cut
*/

static int
write_32_bit(i_io_glue_t *ig, ico_image_t const *image, int *error) {
  unsigned char *writebuf;
  ico_color_t *data = image->image_data, *colorp;
  unsigned char *writep;
  int x, y;

  if (!write_bitmapinfoheader(ig, image, error, 32, 0)) {
    return 0;
  }

  writebuf = malloc(image->width * 4);
  if (!writebuf) {
    *error = ICOERR_Out_Of_Memory;
    return 0;
  }

  for (y = image->height-1; y >= 0; --y) {
    writep = writebuf;
    colorp = data + y * image->width;
    for (x = 0; x < image->width; ++x) {
      *writep++ = colorp->b;
      *writep++ = colorp->g;
      *writep++ = colorp->r;
      *writep++ = colorp->a;
      ++colorp;
    }
    if (i_io_write(ig, writebuf, image->width * 4) != image->width * 4) {
      *error = ICOERR_Write_Failure;
      free(writebuf);
      return 0;
    }
  }

  free(writebuf);

  return 1;
}

/*
=item write_8_bit

Write 8 bit image data.

=cut
*/

static int
write_8_bit(i_io_glue_t *ig, ico_image_t const *image, int *error) {
  static const unsigned char zeros[3] = { '\0' };
  int y;
  const unsigned char *data = image->image_data;
  int zero_count = (0U - (unsigned)image->width) & 3;

  if (!write_bitmapinfoheader(ig, image, error, 8, 256)) {
    return 0;
  }

  if (!write_palette(ig, image, error))
    return 0;

  for (y = image->height-1; y >= 0; --y) {
    if (i_io_write(ig, data + y * image->width, 
		   image->width) != image->width) {
      *error = ICOERR_Write_Failure;
      return 0;
    }
    if (zero_count) {
      if (i_io_write(ig, zeros, zero_count) != zero_count) {
	*error = ICOERR_Write_Failure;
	return 0;
      }
    }
  }

  return 1;
}

/*
=item write_4_bit

Write 4 bit image data.

=cut
*/

static int
write_4_bit(i_io_glue_t *ig, ico_image_t const *image, int *error) {
  int line_size = ((image->width + 1) / 2 + 3) / 4 * 4;
  unsigned char *writebuf, *outp;
  int x, y;
  unsigned char const *data = image->image_data;
  unsigned char const *pixelp;
  
  if (!write_bitmapinfoheader(ig, image, error, 4, 16)) {
    return 0;
  }

  if (!write_palette(ig, image, error))
    return 0;

  writebuf = malloc(line_size);
  if (!writebuf) {
    *error = ICOERR_Out_Of_Memory;
    return 0;
  }

  for (y = image->height-1; y >= 0; --y) {
    pixelp = data + y * image->width;
    outp = writebuf;
    memset(writebuf, 0, line_size);
    for (x = 0; x < image->width; ++x) {
      if (x & 1) {
	*outp |= *pixelp++ & 0x0F;
	++outp;
      }
      else {
	*outp |= *pixelp++ << 4;
      }
    }

    if (i_io_write(ig, writebuf, line_size) != line_size) {
      *error = ICOERR_Write_Failure;
      free(writebuf);
      return 0;
    }
  }

  free(writebuf);

  return 1;
}

/*
=item write_1_bit

Write 1 bit image data.

=cut
*/

static int
write_1_bit(i_io_glue_t *ig, ico_image_t const *image, int *error) {
  int line_size = (image->width + 31) / 32 * 4;
  unsigned char *writebuf = malloc(line_size);
  unsigned char *outp;
  unsigned char const *data, *pixelp;
  int x,y;
  unsigned mask;

  if (!write_bitmapinfoheader(ig, image, error, 1, 2)) {
    return 0;
  }

  if (!write_palette(ig, image, error))
    return 0;

  if (!writebuf) {
    *error = ICOERR_Out_Of_Memory;
    return 0;
  }
  
  data = image->image_data;
  for (y = image->height-1; y >= 0; --y) {
    memset(writebuf, 0, line_size);
    pixelp = data + y * image->width;
    outp = writebuf;
    mask = 0x80;
    for (x = 0; x < image->width; ++x) {
      if (*pixelp)
	*outp |= mask;
      mask >>= 1;
      if (!mask) {
	mask = 0x80;
	outp++;
      }
    }
    if (i_io_write(ig, writebuf, line_size) != line_size) {
      *error = ICOERR_Write_Failure;
      free(writebuf);
      return 0;
    }
  }

  free(writebuf);

  return 1;
}

/*
=item write_mask

Write the AND mask.

=cut
*/

static int
write_mask(i_io_glue_t *ig, ico_image_t const *image, int *error) {
  int line_size = (image->width + 31) / 32 * 4;
  unsigned char *writebuf = malloc(line_size);
  unsigned char *outp;
  unsigned char const *data, *pixelp;
  int x,y;
  unsigned mask;

  if (!writebuf) {
    *error = ICOERR_Out_Of_Memory;
    return 0;
  }
  
  data = image->mask_data;
  if (data) {
    for (y = image->height-1; y >= 0; --y) {
      memset(writebuf, 0, line_size);
      pixelp = data + y * image->width;
      outp = writebuf;
      mask = 0x80;
      for (x = 0; x < image->width; ++x) {
	if (*pixelp)
	  *outp |= mask;
	mask >>= 1;
	if (!mask) {
	  mask = 0x80;
	  outp++;
	}
        ++pixelp;
      }
      if (i_io_write(ig, writebuf, line_size) != line_size) {
	*error = ICOERR_Write_Failure;
	free(writebuf);
	return 0;
      }
    }
  }
  else {
    memset(writebuf, 0, line_size);
    for (y = image->height-1; y >= 0; --y) {
      if (i_io_write(ig, writebuf, line_size) != line_size) {
	*error = ICOERR_Write_Failure;
	free(writebuf);
	return 0;
      }
    }
  }

  free(writebuf);

  return 1;
}

/*
=back

=head1 AUTHOR

Tony Cook <tonyc@cpan.org>

=head1 REVISION

$Revision$

=cut
*/
