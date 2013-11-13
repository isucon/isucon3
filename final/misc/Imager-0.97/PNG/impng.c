#include "impng.h"
#include "png.h"
#include <stdlib.h>
#include <string.h>

/* this is a way to get number of channels from color space 
 * Color code to channel number */

static int CC2C[PNG_COLOR_MASK_PALETTE|PNG_COLOR_MASK_COLOR|PNG_COLOR_MASK_ALPHA];

#define PNG_BYTES_TO_CHECK 4

static i_img *
read_direct8(png_structp png_ptr, png_infop info_ptr, int channels, i_img_dim width, i_img_dim height);

static i_img *
read_direct16(png_structp png_ptr, png_infop info_ptr, int channels, i_img_dim width, i_img_dim height);

static i_img *
read_paletted(png_structp png_ptr, png_infop info_ptr, int channels, i_img_dim width, i_img_dim height);

static i_img *
read_bilevel(png_structp png_ptr, png_infop info_ptr, i_img_dim width, i_img_dim height);

static int
write_direct8(png_structp png_ptr, png_infop info_ptr, i_img *im);

static int
write_direct16(png_structp png_ptr, png_infop info_ptr, i_img *im);

static int
write_paletted(png_structp png_ptr, png_infop info_ptr, i_img *im, int bits);

static int
write_bilevel(png_structp png_ptr, png_infop info_ptr, i_img *im);

static void 
get_png_tags(i_img *im, png_structp png_ptr, png_infop info_ptr, int bit_depth, int color_type);

static int
set_png_tags(i_img *im, png_structp png_ptr, png_infop info_ptr);

static const char *
get_string2(i_img_tags *tags, const char *name, char *buf, size_t *size);

unsigned
i_png_lib_version(void) {
  return png_access_version_number();
}

static char const * const
features[] =
  {
#ifdef PNG_BENIGN_ERRORS_SUPPORTED
    "benign-errors",
#endif
#ifdef PNG_READ_SUPPORTED
    "read",
#endif
#ifdef PNG_WRITE_SUPPORTED
    "write",
#endif
#ifdef PNG_MNG_FEATURES_SUPPORTED
    "mng-features",
#endif
#ifdef PNG_CHECK_cHRM_SUPPORTED
    "check-cHRM",
#endif
#ifdef PNG_SET_USER_LIMITS_SUPPORTED
    "user-limits",
#endif
    NULL
  };

const char * const *
i_png_features(void) {
  return features;
}

static void
wiol_read_data(png_structp png_ptr, png_bytep data, png_size_t length) {
  io_glue *ig = png_get_io_ptr(png_ptr);
  ssize_t rc = i_io_read(ig, data, length);
  if (rc != length) png_error(png_ptr, "Read overflow error on an iolayer source.");
}

static void
wiol_write_data(png_structp png_ptr, png_bytep data, png_size_t length) {
  ssize_t rc;
  io_glue *ig = png_get_io_ptr(png_ptr);
  rc = i_io_write(ig, data, length);
  if (rc != length) png_error(png_ptr, "Write error on an iolayer source.");
}

static void
wiol_flush_data(png_structp png_ptr) {
  io_glue *ig = png_get_io_ptr(png_ptr);
  if (!i_io_flush(ig))
    png_error(png_ptr, "Error flushing output");
}

static void
error_handler(png_structp png_ptr, png_const_charp msg) {
  mm_log((1, "PNG error: '%s'\n", msg));

  i_push_error(0, msg);
  longjmp(png_jmpbuf(png_ptr), 1);
}

/*

  For writing a warning might have information about an error, so send
  it to the error stack.

*/
static void
write_warn_handler(png_structp png_ptr, png_const_charp msg) {
  mm_log((1, "PNG write warning '%s'\n", msg));

  i_push_error(0, msg);
}

#define PNG_DIM_MAX 0x7fffffffL

undef_int
i_writepng_wiol(i_img *im, io_glue *ig) {
  png_structp png_ptr;
  png_infop info_ptr = NULL;
  i_img_dim width,height;
  volatile int cspace,channels;
  int bits;
  int is_bilevel = 0, zero_is_white;

  mm_log((1,"i_writepng(im %p ,ig %p)\n", im, ig));

  i_clear_error();

  if (im->xsize > PNG_UINT_31_MAX || im->ysize > PNG_UINT_31_MAX) {
    i_push_error(0, "image too large for PNG");
    return 0;
  }

  height = im->ysize;
  width  = im->xsize;

  /* if we ever have 64-bit i_img_dim
   * the libpng docs state that png_set_user_limits() can be used to
   * override the PNG_USER_*_MAX limits, but as implemented they
   * don't.  We check against the theoretical limit of PNG here, and
   * try to override the limits below, in case the libpng
   * implementation ever matches the documentation.
   *
   * https://sourceforge.net/tracker/?func=detail&atid=105624&aid=3314943&group_id=5624
   * fixed in libpng 1.5.3
   */
  if (width > PNG_DIM_MAX || height > PNG_DIM_MAX) {
    i_push_error(0, "Image too large for PNG");
    return 0;
  }

  channels=im->channels;

  if (i_img_is_monochrome(im, &zero_is_white)) {
    is_bilevel = 1;
    bits = 1;
    cspace = PNG_COLOR_TYPE_GRAY;
    mm_log((1, "i_writepng: bilevel output\n"));
  }
  else if (im->type == i_palette_type) {
    int colors = i_colorcount(im);

    cspace = PNG_COLOR_TYPE_PALETTE;
    bits = 1;
    while ((1 << bits) < colors) {
      bits += bits;
    }
    mm_log((1, "i_writepng: paletted output\n"));
  }
  else {
    switch (channels) {
    case 1:
      cspace = PNG_COLOR_TYPE_GRAY;
      break;
    case 2:
      cspace = PNG_COLOR_TYPE_GRAY_ALPHA;
      break;
    case 3:
      cspace = PNG_COLOR_TYPE_RGB;
      break;
    case 4:
      cspace = PNG_COLOR_TYPE_RGB_ALPHA;
      break;
    default:
      fprintf(stderr, "Internal error, channels = %d\n", channels);
      abort();
    }
    bits = im->bits > 8 ? 16 : 8;
    mm_log((1, "i_writepng: direct output\n"));
  }

  mm_log((1,"i_writepng: cspace=%d, bits=%d\n",cspace, bits));

  /* Create and initialize the png_struct with the desired error handler
   * functions.  If you want to use the default stderr and longjump method,
   * you can supply NULL for the last three parameters.  We also check that
   * the library version is compatible with the one used at compile time,
   * in case we are using dynamically linked libraries.  REQUIRED.
   */
  
  png_ptr = png_create_write_struct(PNG_LIBPNG_VER_STRING, NULL, 
				    error_handler, write_warn_handler);
  
  if (png_ptr == NULL) return 0;

  
  /* Allocate/initialize the image information data.  REQUIRED */
  info_ptr = png_create_info_struct(png_ptr);

  if (info_ptr == NULL) {
    png_destroy_write_struct(&png_ptr, &info_ptr);
    return 0;
  }
  
  /* Set error handling.  REQUIRED if you aren't supplying your own
   * error hadnling functions in the png_create_write_struct() call.
   */
  if (setjmp(png_jmpbuf(png_ptr))) {
    png_destroy_write_struct(&png_ptr, &info_ptr);
    return(0);
  }
  
  png_set_write_fn(png_ptr, (png_voidp) (ig), wiol_write_data, wiol_flush_data);

  /* Set the image information here.  Width and height are up to 2^31,
   * bit_depth is one of 1, 2, 4, 8, or 16, but valid values also depend on
   * the color_type selected. color_type is one of PNG_COLOR_TYPE_GRAY,
   * PNG_COLOR_TYPE_GRAY_ALPHA, PNG_COLOR_TYPE_PALETTE, PNG_COLOR_TYPE_RGB,
   * or PNG_COLOR_TYPE_RGB_ALPHA.  interlace is either PNG_INTERLACE_NONE or
   * PNG_INTERLACE_ADAM7, and the compression_type and filter_type MUST
   * currently be PNG_COMPRESSION_TYPE_BASE and PNG_FILTER_TYPE_BASE. REQUIRED
   */

  /* by default, libpng (not PNG) limits the image size to a maximum
   * 1000000 pixels in each direction, but Imager doesn't.
   * Configure libpng to avoid that limit.
   */
  png_set_user_limits(png_ptr, width, height);

  png_set_IHDR(png_ptr, info_ptr, width, height, bits, cspace,
	       PNG_INTERLACE_NONE, PNG_COMPRESSION_TYPE_BASE, PNG_FILTER_TYPE_BASE);

  if (!set_png_tags(im, png_ptr, info_ptr)) {
    png_destroy_write_struct(&png_ptr, &info_ptr);
    return 0;
  }

  if (is_bilevel) {
    if (!write_bilevel(png_ptr, info_ptr, im)) {
      png_destroy_write_struct(&png_ptr, &info_ptr);
      return 0;
    }
  }
  else if (im->type == i_palette_type) {
    if (!write_paletted(png_ptr, info_ptr, im, bits)) {
      png_destroy_write_struct(&png_ptr, &info_ptr);
      return 0;
    }
  }
  else if (bits == 16) {
    if (!write_direct16(png_ptr, info_ptr, im)) {
      png_destroy_write_struct(&png_ptr, &info_ptr);
      return 0;
    }
  }
  else {
    if (!write_direct8(png_ptr, info_ptr, im)) {
      png_destroy_write_struct(&png_ptr, &info_ptr);
      return 0;
    }
  }

  png_write_end(png_ptr, info_ptr);

  png_destroy_write_struct(&png_ptr, &info_ptr);

  if (i_io_close(ig))
    return 0;

  return(1);
}

typedef struct {
  char *warnings;
} i_png_read_state, *i_png_read_statep;

static void
read_warn_handler(png_structp, png_const_charp);

static void
cleanup_read_state(i_png_read_statep);

i_img*
i_readpng_wiol(io_glue *ig, int flags) {
  i_img *im = NULL;
  png_structp png_ptr;
  png_infop info_ptr;
  png_uint_32 width, height;
  int bit_depth, color_type, interlace_type;
  int channels;
  unsigned int sig_read;
  i_png_read_state rs;

  rs.warnings = NULL;
  sig_read  = 0;

  mm_log((1,"i_readpng_wiol(ig %p)\n", ig));
  i_clear_error();

  png_ptr = png_create_read_struct(PNG_LIBPNG_VER_STRING, &rs, 
				   error_handler, read_warn_handler);
  if (!png_ptr) {
    i_push_error(0, "Cannot create PNG read structure");
    return NULL;
  }
  png_set_read_fn(png_ptr, (png_voidp) (ig), wiol_read_data);

#if defined(PNG_BENIGN_ERRORS_SUPPORTED)
  png_set_benign_errors(png_ptr, (flags & IMPNG_READ_IGNORE_BENIGN_ERRORS) ? 1 : 0);
#elif PNG_LIBPNG_VER >= 10400
  if (flags & IMPNG_READ_IGNORE_BENIGN_ERRORS) {
    i_push_error(0, "libpng not configured to ignore benign errors");
    png_destroy_read_struct(&png_ptr, (png_infopp)NULL, (png_infopp)NULL);
    return NULL;
  }
#else
  if (flags & IMPNG_READ_IGNORE_BENIGN_ERRORS) {
    i_push_error(0, "libpng too old to ignore benign errors");
    png_destroy_read_struct(&png_ptr, (png_infopp)NULL, (png_infopp)NULL);
    return NULL;
  }
#endif

  info_ptr = png_create_info_struct(png_ptr);
  if (info_ptr == NULL) {
    png_destroy_read_struct(&png_ptr, (png_infopp)NULL, (png_infopp)NULL);
    i_push_error(0, "Cannot create PNG info structure");
    return NULL;
  }
  
  if (setjmp(png_jmpbuf(png_ptr))) {
    if (im) i_img_destroy(im);
    mm_log((1,"i_readpng_wiol: error.\n"));
    png_destroy_read_struct(&png_ptr, &info_ptr, (png_infopp)NULL);
    cleanup_read_state(&rs);
    return NULL;
  }

  /* we do our own limit checks */
  png_set_user_limits(png_ptr, PNG_DIM_MAX, PNG_DIM_MAX);

  png_set_sig_bytes(png_ptr, sig_read);
  png_read_info(png_ptr, info_ptr);
  png_get_IHDR(png_ptr, info_ptr, &width, &height, &bit_depth, &color_type, &interlace_type, NULL, NULL);
  
  mm_log((1, "png_get_IHDR results: width %u, height %u, bit_depth %d, color_type %d, interlace_type %d\n",
	  (unsigned)width, (unsigned)height, bit_depth,color_type,interlace_type));
  
  CC2C[PNG_COLOR_TYPE_GRAY]=1;
  CC2C[PNG_COLOR_TYPE_PALETTE]=3;
  CC2C[PNG_COLOR_TYPE_RGB]=3;
  CC2C[PNG_COLOR_TYPE_RGB_ALPHA]=4;
  CC2C[PNG_COLOR_TYPE_GRAY_ALPHA]=2;
  channels = CC2C[color_type];

  mm_log((1,"i_readpng_wiol: channels %d\n",channels));

  if (!i_int_check_image_file_limits(width, height, channels, sizeof(i_sample_t))) {
    mm_log((1, "i_readpnm: image size exceeds limits\n"));
    png_destroy_read_struct(&png_ptr, &info_ptr, (png_infopp)NULL);
    return NULL;
  }

  if (color_type == PNG_COLOR_TYPE_PALETTE) {
    im = read_paletted(png_ptr, info_ptr, channels, width, height);
  }
  else if (color_type == PNG_COLOR_TYPE_GRAY
	   && bit_depth == 1
	   && !png_get_valid(png_ptr, info_ptr, PNG_INFO_tRNS)) {
    im = read_bilevel(png_ptr, info_ptr, width, height);
  }
  else if (bit_depth == 16) {
    im = read_direct16(png_ptr, info_ptr, channels, width, height);
  }
  else {
    im = read_direct8(png_ptr, info_ptr, channels, width, height);
  }

  if (im)
    get_png_tags(im, png_ptr, info_ptr, bit_depth, color_type);

  png_destroy_read_struct(&png_ptr, &info_ptr, (png_infopp)NULL);

  if (im) {
    if (rs.warnings) {
      i_tags_set(&im->tags, "png_warnings", rs.warnings, -1);
    }
  }
  cleanup_read_state(&rs);
  
  mm_log((1,"(%p) <- i_readpng_wiol\n", im));  
  
  return im;
}

static i_img *
read_direct8(png_structp png_ptr, png_infop info_ptr, int channels,
	     i_img_dim width, i_img_dim height) {
  i_img * volatile vim = NULL;
  int color_type = png_get_color_type(png_ptr, info_ptr);
  int bit_depth = png_get_bit_depth(png_ptr, info_ptr);
  i_img_dim y;
  int number_passes, pass;
  i_img *im;
  unsigned char *line;
  unsigned char * volatile vline = NULL;

  if (setjmp(png_jmpbuf(png_ptr))) {
    if (vim) i_img_destroy(vim);
    if (vline) myfree(vline);

    return NULL;
  }

  number_passes = png_set_interlace_handling(png_ptr);
  mm_log((1,"number of passes=%d\n",number_passes));

  png_set_strip_16(png_ptr);
  png_set_packing(png_ptr);

  if (color_type == PNG_COLOR_TYPE_GRAY && bit_depth < 8)
    png_set_expand(png_ptr);
    
  if (png_get_valid(png_ptr, info_ptr, PNG_INFO_tRNS)) {
    channels++;
    mm_log((1, "image has transparency, adding alpha: channels = %d\n", channels));
    png_set_expand(png_ptr);
  }
  
  png_read_update_info(png_ptr, info_ptr);
  
  im = vim = i_img_8_new(width,height,channels);
  if (!im) {
    png_destroy_read_struct(&png_ptr, &info_ptr, (png_infopp)NULL);
    return NULL;
  }
  
  line = vline = mymalloc(channels * width);
  for (pass = 0; pass < number_passes; pass++) {
    for (y = 0; y < height; y++) {
      if (pass > 0)
	i_gsamp(im, 0, width, y, line, NULL, channels);
      png_read_row(png_ptr,(png_bytep)line, NULL);
      i_psamp(im, 0, width, y, line, NULL, channels);
    }
  }
  myfree(line);
  vline = NULL;
  
  png_read_end(png_ptr, info_ptr); 

  return im;
}

static i_img *
read_direct16(png_structp png_ptr, png_infop info_ptr, int channels,
	     i_img_dim width, i_img_dim height) {
  i_img * volatile vim = NULL;
  i_img_dim x, y;
  int number_passes, pass;
  i_img *im;
  unsigned char *line;
  unsigned char * volatile vline = NULL;
  unsigned *bits_line;
  unsigned * volatile vbits_line = NULL;
  size_t row_bytes;

  if (setjmp(png_jmpbuf(png_ptr))) {
    if (vim) i_img_destroy(vim);
    if (vline) myfree(vline);
    if (vbits_line) myfree(vbits_line);

    return NULL;
  }

  number_passes = png_set_interlace_handling(png_ptr);
  mm_log((1,"number of passes=%d\n",number_passes));

  if (png_get_valid(png_ptr, info_ptr, PNG_INFO_tRNS)) {
    channels++;
    mm_log((1, "image has transparency, adding alpha: channels = %d\n", channels));
    png_set_expand(png_ptr);
  }
  
  png_read_update_info(png_ptr, info_ptr);
  
  im = vim = i_img_16_new(width,height,channels);
  if (!im) {
    png_destroy_read_struct(&png_ptr, &info_ptr, (png_infopp)NULL);
    return NULL;
  }
  
  row_bytes = png_get_rowbytes(png_ptr, info_ptr);
  line = vline = mymalloc(row_bytes);
  memset(line, 0, row_bytes);
  bits_line = vbits_line = mymalloc(sizeof(unsigned) * width * channels);
  for (pass = 0; pass < number_passes; pass++) {
    for (y = 0; y < height; y++) {
      if (pass > 0) {
	i_gsamp_bits(im, 0, width, y, bits_line, NULL, channels, 16);
	for (x = 0; x < width * channels; ++x) {
	  line[x*2] = bits_line[x] >> 8;
	  line[x*2+1] = bits_line[x] & 0xff;
	}
      }
      png_read_row(png_ptr,(png_bytep)line, NULL);
      for (x = 0; x < width * channels; ++x)
	bits_line[x] = (line[x*2] << 8) + line[x*2+1];
      i_psamp_bits(im, 0, width, y, bits_line, NULL, channels, 16);
    }
  }
  myfree(line);
  myfree(bits_line);
  vline = NULL;
  vbits_line = NULL;
  
  png_read_end(png_ptr, info_ptr); 

  return im;
}

static i_img *
read_bilevel(png_structp png_ptr, png_infop info_ptr,
	     i_img_dim width, i_img_dim height) {
  i_img * volatile vim = NULL;
  i_img_dim x, y;
  int number_passes, pass;
  i_img *im;
  unsigned char *line;
  unsigned char * volatile vline = NULL;
  i_color palette[2];

  if (setjmp(png_jmpbuf(png_ptr))) {
    if (vim) i_img_destroy(vim);
    if (vline) myfree(vline);

    return NULL;
  }

  number_passes = png_set_interlace_handling(png_ptr);
  mm_log((1,"number of passes=%d\n",number_passes));

  png_set_packing(png_ptr);

  png_set_expand(png_ptr);  
  
  png_read_update_info(png_ptr, info_ptr);
  
  im = vim = i_img_pal_new(width, height, 1, 256);
  if (!im) {
    png_destroy_read_struct(&png_ptr, &info_ptr, (png_infopp)NULL);
    return NULL;
  }

  palette[0].channel[0] = palette[0].channel[1] = palette[0].channel[2] = 
    palette[0].channel[3] = 0;
  palette[1].channel[0] = palette[1].channel[1] = palette[1].channel[2] = 
    palette[1].channel[3] = 255;
  i_addcolors(im, palette, 2);
  
  line = vline = mymalloc(width);
  memset(line, 0, width);
  for (pass = 0; pass < number_passes; pass++) {
    for (y = 0; y < height; y++) {
      if (pass > 0) {
	i_gpal(im, 0, width, y, line);
	/* expand indexes back to 0/255 */
	for (x = 0; x < width; ++x)
	  line[x] = line[x] ? 255 : 0;
      }
      png_read_row(png_ptr,(png_bytep)line, NULL);

      /* back to palette indexes */
      for (x = 0; x < width; ++x)
	line[x] = line[x] ? 1 : 0;
      i_ppal(im, 0, width, y, line);
    }
  }
  myfree(line);
  vline = NULL;
  
  png_read_end(png_ptr, info_ptr); 

  return im;
}

/* FIXME: do we need to unscale palette color values from the 
   supplied alphas? */
static i_img *
read_paletted(png_structp png_ptr, png_infop info_ptr, int channels,
	      i_img_dim width, i_img_dim height) {
  i_img * volatile vim = NULL;
  int color_type = png_get_color_type(png_ptr, info_ptr);
  int bit_depth = png_get_bit_depth(png_ptr, info_ptr);
  i_img_dim y;
  int number_passes, pass;
  i_img *im;
  unsigned char *line;
  unsigned char * volatile vline = NULL;
  int num_palette, i;
  png_colorp png_palette;
  png_bytep png_pal_trans;
  png_color_16p png_color_trans;
  int num_pal_trans;

  if (setjmp(png_jmpbuf(png_ptr))) {
    if (vim) i_img_destroy(vim);
    if (vline) myfree(vline);

    return NULL;
  }

  number_passes = png_set_interlace_handling(png_ptr);
  mm_log((1,"number of passes=%d\n",number_passes));

  png_set_strip_16(png_ptr);
  png_set_packing(png_ptr);

  if (color_type == PNG_COLOR_TYPE_GRAY && bit_depth < 8)
    png_set_expand(png_ptr);
    
  if (!png_get_PLTE(png_ptr, info_ptr, &png_palette, &num_palette)) {
    i_push_error(0, "Paletted image with no PLTE chunk");
    return NULL;
  }

  if (png_get_tRNS(png_ptr, info_ptr, &png_pal_trans, &num_pal_trans,
		   &png_color_trans)) {
    channels++;
  }
  else {
    num_pal_trans = 0;
  }
  
  png_read_update_info(png_ptr, info_ptr);
  
  im = vim = i_img_pal_new(width, height, channels, 256);
  if (!im) {
    png_destroy_read_struct(&png_ptr, &info_ptr, (png_infopp)NULL);
    return NULL;
  }

  for (i = 0; i < num_palette; ++i) {
    i_color c;

    c.rgba.r = png_palette[i].red;
    c.rgba.g = png_palette[i].green;
    c.rgba.b = png_palette[i].blue;
    if (i < num_pal_trans)
      c.rgba.a = png_pal_trans[i];
    else
      c.rgba.a = 255;
    i_addcolors(im, &c, 1);
  }

  line = vline = mymalloc(width);
  for (pass = 0; pass < number_passes; pass++) {
    for (y = 0; y < height; y++) {
      if (pass > 0)
	i_gpal(im, 0, width, y, line);
      png_read_row(png_ptr,(png_bytep)line, NULL);
      i_ppal(im, 0, width, y, line);
    }
  }
  myfree(line);
  vline = NULL;
  
  png_read_end(png_ptr, info_ptr); 

  return im;
}

struct png_text_name {
  const char *keyword;
  const char *tagname;
};

static const struct png_text_name
text_tags[] = {
  { "Author", "png_author" },
  { "Comment", "i_comment" },
  { "Copyright", "png_copyright" },
  { "Creation Time", "png_creation_time" },
  { "Description", "png_description" },
  { "Disclaimer", "png_disclaimer" },
  { "Software", "png_software" },
  { "Source", "png_source" },
  { "Title", "png_title" },
  { "Warning", "png_warning" }
};

static const int text_tags_count = sizeof(text_tags) / sizeof(*text_tags);

static const char * const
chroma_tags[] = {
  "png_chroma_white_x",
  "png_chroma_white_y",
  "png_chroma_red_x",
  "png_chroma_red_y",
  "png_chroma_green_x",
  "png_chroma_green_y",
  "png_chroma_blue_x",
  "png_chroma_blue_y"
};

static const int chroma_tag_count = sizeof(chroma_tags) / sizeof(*chroma_tags);

static void
get_png_tags(i_img *im, png_structp png_ptr, png_infop info_ptr,
	     int bit_depth, int color_type) {
  png_uint_32 xres, yres;
  int unit_type;

  i_tags_set(&im->tags, "i_format", "png", -1);
  if (png_get_pHYs(png_ptr, info_ptr, &xres, &yres, &unit_type)) {
    mm_log((1,"pHYs (%u, %u) %d\n", (unsigned)xres, (unsigned)yres, unit_type));
    if (unit_type == PNG_RESOLUTION_METER) {
      i_tags_set_float2(&im->tags, "i_xres", 0, xres * 0.0254, 5);
      i_tags_set_float2(&im->tags, "i_yres", 0, yres * 0.0254, 5);
    }
    else {
      i_tags_setn(&im->tags, "i_xres", xres);
      i_tags_setn(&im->tags, "i_yres", yres);
      i_tags_setn(&im->tags, "i_aspect_only", 1);
    }
  }
  {
    int interlace = png_get_interlace_type(png_ptr, info_ptr);

    i_tags_setn(&im->tags, "png_interlace", interlace != PNG_INTERLACE_NONE);
    switch (interlace) {
    case PNG_INTERLACE_NONE:
      i_tags_set(&im->tags, "png_interlace_name", "none", -1);
      break;
      
    case PNG_INTERLACE_ADAM7:
      i_tags_set(&im->tags, "png_interlace_name", "adam7", -1);
      break;
      
    default:
      i_tags_set(&im->tags, "png_interlace_name", "unknown", -1);
      break;
    }
  }

  /* the various readers can call png_set_expand(), libpng will make
     it's internal record of bit_depth at least 8 in that case */
  i_tags_setn(&im->tags, "png_bits", bit_depth);
  
  if (png_get_valid(png_ptr, info_ptr, PNG_INFO_sRGB)) {
    int intent;
    if (png_get_sRGB(png_ptr, info_ptr, &intent)) {
      i_tags_setn(&im->tags, "png_srgb_intent", intent);
    }
  }
  else {
    /* Ignore these if there's an sRGB chunk, libpng simulates
       their existence if there's an sRGB chunk, and the PNG spec says
       that these are ignored if the sRGB is present, so ignore them.
    */
    double gamma;
    double chroma[8];

    if (png_get_gAMA(png_ptr, info_ptr, &gamma)) {
      i_tags_set_float2(&im->tags, "png_gamma", 0, gamma, 4);
    }

    if (png_get_cHRM(png_ptr, info_ptr, chroma+0, chroma+1,
		     chroma+2, chroma+3, chroma+4, chroma+5,
		     chroma+6, chroma+7)) {
      int i;

      for (i = 0; i < chroma_tag_count; ++i)
	i_tags_set_float2(&im->tags, chroma_tags[i], 0, chroma[i], 4);
    }
  }

  {
    int num_text;
    png_text *text;

    if (png_get_text(png_ptr, info_ptr, &text, &num_text)) {
      int i;
      int custom_index = 0;
      for (i = 0; i < num_text; ++i) {
	int j;
	int found = 0;
	int compressed = text[i].compression == PNG_ITXT_COMPRESSION_zTXt
	  || text[i].compression == PNG_TEXT_COMPRESSION_zTXt;

	for (j = 0; j < text_tags_count; ++j) {
	  if (strcmp(text_tags[j].keyword, text[i].key) == 0) {
	    char tag_name[50];
	    i_tags_set(&im->tags, text_tags[j].tagname, text[i].text, -1);
	    if (compressed) {
	      sprintf(tag_name, "%s_compressed", text_tags[j].tagname);
	      i_tags_setn(&im->tags, tag_name, 1);
	    }
	    found = 1;
	    break;
	  }
	}

	if (!found) {
	  char tag_name[50];
	  sprintf(tag_name, "png_text%d_key", custom_index);
	  i_tags_set(&im->tags, tag_name, text[i].key, -1);
	  sprintf(tag_name, "png_text%d_text", custom_index);
	  i_tags_set(&im->tags, tag_name, text[i].text, -1);
	  sprintf(tag_name, "png_text%d_type", custom_index);
	  i_tags_set(&im->tags, tag_name, 
		     (text[i].compression == PNG_TEXT_COMPRESSION_NONE
		      || text[i].compression == PNG_TEXT_COMPRESSION_zTXt) ?
		     "text" : "itxt", -1);
	  if (compressed) {
	    sprintf(tag_name, "png_text%d_compressed", custom_index);
	    i_tags_setn(&im->tags, tag_name, 1);
	  }
	  ++custom_index;
	}
      }
    }
  }

  {
    png_time *mod_time;

    if (png_get_tIME(png_ptr, info_ptr, &mod_time)) {
      char time_formatted[80];

      sprintf(time_formatted, "%d-%02d-%02dT%02d:%02d:%02d",
	      mod_time->year, mod_time->month, mod_time->day,
	      mod_time->hour, mod_time->minute, mod_time->second);
      i_tags_set(&im->tags, "png_time", time_formatted, -1);
    }
  }

  {
    png_color_16 *back;
    i_color c;

    if (png_get_bKGD(png_ptr, info_ptr, &back)) {
      switch (color_type) {
      case PNG_COLOR_TYPE_GRAY:
      case PNG_COLOR_TYPE_GRAY_ALPHA:
	{
	  /* lib png stores the raw gray value rather than scaling it
	     to 16-bit (or 8), we use 8-bit color for i_background */

	  int gray;
	  switch (bit_depth) {
	  case 16:
	    gray = back->gray >> 8;
	    break;
	  case 8:
	    gray = back->gray;
	    break;
	  case 4:
	    gray = 0x11 * back->gray;
	    break;
	  case 2:
	    gray = 0x55 * back->gray;
	    break;
	  case 1:
	    gray = back->gray ? 0xFF : 0;
	    break;
	  default:
	    gray = 0;
	  }
	  c.rgb.r = c.rgb.g = c.rgb.b = gray;
	  break;
	}

      case PNG_COLOR_TYPE_RGB:
      case PNG_COLOR_TYPE_RGB_ALPHA:
	{
	  c.rgb.r = bit_depth == 16 ? (back->red   >> 8) : back->red;
	  c.rgb.g = bit_depth == 16 ? (back->green >> 8) : back->green;
	  c.rgb.b = bit_depth == 16 ? (back->blue  >> 8) : back->blue;
	  break;
	}

      case PNG_COLOR_TYPE_PALETTE:
	c.rgb.r = back->red;
	c.rgb.g = back->green;
	c.rgb.b = back->blue;
	break;
      }

      c.rgba.a = 255;
      i_tags_set_color(&im->tags, "i_background", 0, &c);
    }
  }
}

#define GET_STR_BUF_SIZE 40

static int
set_png_tags(i_img *im, png_structp png_ptr, png_infop info_ptr) {
  double xres, yres;
  int aspect_only, have_res = 1;

  if (i_tags_get_float(&im->tags, "i_xres", 0, &xres)) {
    if (i_tags_get_float(&im->tags, "i_yres", 0, &yres))
      ; /* nothing to do */
    else
      yres = xres;
  }
  else {
    if (i_tags_get_float(&im->tags, "i_yres", 0, &yres))
      xres = yres;
    else
      have_res = 0;
  }
  if (have_res) {
    aspect_only = 0;
    i_tags_get_int(&im->tags, "i_aspect_only", 0, &aspect_only);
    xres /= 0.0254;
    yres /= 0.0254;
    png_set_pHYs(png_ptr, info_ptr, xres + 0.5, yres + 0.5, 
                 aspect_only ? PNG_RESOLUTION_UNKNOWN : PNG_RESOLUTION_METER);
  }

  {
    int intent;
    if (i_tags_get_int(&im->tags, "png_srgb_intent", 0, &intent)) {
      if (intent < 0 || intent >= PNG_sRGB_INTENT_LAST) {
	i_push_error(0, "tag png_srgb_intent out of range");
	return 0;
      }
      png_set_sRGB(png_ptr, info_ptr, intent);
    }
    else {
      double chroma[8], gamma;
      int i;
      int found_chroma_count = 0;

      for (i = 0; i < chroma_tag_count; ++i) {
	if (i_tags_get_float(&im->tags, chroma_tags[i], 0, chroma+i))
	  ++found_chroma_count;
      }

      if (found_chroma_count) {
	if (found_chroma_count != chroma_tag_count) {
	  i_push_error(0, "all png_chroma_* tags must be supplied or none");
	  return 0;
	}

	png_set_cHRM(png_ptr, info_ptr, chroma[0], chroma[1], chroma[2],
		     chroma[3], chroma[4], chroma[5], chroma[6], chroma[7]);
      }

      if (i_tags_get_float(&im->tags, "png_gamma", 0, &gamma)) {
	png_set_gAMA(png_ptr, info_ptr, gamma);
      }
    }
  }

  {
    /* png_set_text() is sparsely documented, it isn't indicated whether
       multiple calls add to or replace the lists of texts, and
       whether the text/keyword data is copied or not.

       Examining the linpng code reveals that png_set_text() adds to
       the list and that the text is copied.
    */
    int i;

    /* do our standard tags */
    for (i = 0; i < text_tags_count; ++i) {
      char buf[GET_STR_BUF_SIZE];
      size_t size;
      const char *data;
      
      data = get_string2(&im->tags, text_tags[i].tagname, buf, &size);
      if (data) {
	png_text text;
	int compression = size > 1000;
	char compress_tag[40];

	if (memchr(data, '\0',  size)) {
	  i_push_errorf(0, "tag %s may not contain NUL characters", text_tags[i].tagname);
	  return 0;
	}
      
	sprintf(compress_tag, "%s_compressed", text_tags[i].tagname);
	i_tags_get_int(&im->tags, compress_tag, 0, &compression);
	
	text.compression = compression ? PNG_TEXT_COMPRESSION_zTXt
	  : PNG_TEXT_COMPRESSION_NONE;
	text.key = (char *)text_tags[i].keyword;
	text.text_length = size;
	text.text = (char *)data;
#ifdef PNG_iTXt_SUPPORTED
	text.itxt_length = 0;
	text.lang = NULL;
	text.lang_key = NULL;
#endif

	png_set_text(png_ptr, info_ptr, &text, 1);
      }
    }

    /* for non-standard tags ensure keywords are limited to 1 to 79
       characters */
    i = 0;
    while (1) {
      char tag_name[50];
      char key_buf[GET_STR_BUF_SIZE], value_buf[GET_STR_BUF_SIZE];
      const char *key, *value;
      size_t key_size, value_size;

      sprintf(tag_name, "png_text%d_key", i);
      key = get_string2(&im->tags, tag_name, key_buf, &key_size);
      
      if (key) {
	size_t k;
	if (key_size < 1 || key_size > 79) {
	  i_push_errorf(0, "tag %s must be between 1 and 79 characters in length", tag_name);
	  return 0;
	}

	if (key[0] == ' ' || key[key_size-1] == ' ') {
	  i_push_errorf(0, "tag %s may not contain leading or trailing spaces", tag_name);
	  return 0;
	}

	if (strstr(key, "  ")) {
	  i_push_errorf(0, "tag %s may not contain consecutive spaces", tag_name);
	  return 0;
	}

	for (k = 0; k < key_size; ++k) {
	  if (key[k] < 32 || (key[k] > 126 && key[k] < 161)) {
	    i_push_errorf(0, "tag %s may only contain Latin1 characters 32-126, 161-255", tag_name);
	    return 0;
	  }
	}
      }

      sprintf(tag_name, "png_text%d_text", i);
      value = get_string2(&im->tags, tag_name, value_buf, &value_size);

      if (value) {
	if (memchr(value, '\0', value_size)) {
	  i_push_errorf(0, "tag %s may not contain NUL characters", tag_name);
	  return 0;
	}
      }

      if (key && value) {
	png_text text;
	int compression = value_size > 1000;

	sprintf(tag_name, "png_text%d_compressed", i);
	i_tags_get_int(&im->tags, tag_name, 0, &compression);

	text.compression = compression ? PNG_TEXT_COMPRESSION_zTXt
	  : PNG_TEXT_COMPRESSION_NONE;
	text.key = (char *)key;
	text.text_length = value_size;
	text.text = (char *)value;
#ifdef PNG_iTXt_SUPPORTED
	text.itxt_length = 0;
	text.lang = NULL;
	text.lang_key = NULL;
#endif

	png_set_text(png_ptr, info_ptr, &text, 1);
      }
      else if (key) {
	i_push_errorf(0, "tag png_text%d_key found but not png_text%d_text", i, i);
	return 0;
      }
      else if (value) {
	i_push_errorf(0, "tag png_text%d_text found but not png_text%d_key", i, i);
	return 0;
      }
      else {
	break;
      }
      ++i;
    }
  }

  {
    char buf[GET_STR_BUF_SIZE];
    size_t time_size;
    const char *timestr = get_string2(&im->tags, "png_time", buf, &time_size);

    if (timestr) {
      int year, month, day, hour, minute, second;
      png_time mod_time;

      if (sscanf(timestr, "%d-%d-%dT%d:%d:%d", &year, &month, &day, &hour, &minute, &second) == 6) {
	/* rough validation */
	if (month < 1 || month > 12
	    || day < 1 || day > 31
	    || hour < 0 || hour > 23
	    || minute < 0 || minute > 59
	    || second < 0 || second > 60) {
	  i_push_error(0, "invalid date/time for png_time");
	  return 0;
	}
	mod_time.year = year;
	mod_time.month = month;
	mod_time.day = day;
	mod_time.hour = hour;
	mod_time.minute = minute;
	mod_time.second = second;

	png_set_tIME(png_ptr, info_ptr, &mod_time);
      }
      else {
	i_push_error(0, "png_time must be formatted 'y-m-dTh:m:s'");
	return 0;
      }
    }
  }

  {
    /* no bKGD support yet, maybe later
       it may be simpler to do it in the individual writers
     */
  }

  return 1;
}

static const char *
get_string2(i_img_tags *tags, const char *name, char *buf, size_t *size) {
  int index;

  if (i_tags_find(tags, name, 0, &index)) {
    const i_img_tag *entry = tags->tags + index;
    
    if (entry->data) {
      *size = entry->size;

      return entry->data;
    }
    else {
      *size = sprintf(buf, "%d", entry->idata);

      return buf;
    }
  }
  return NULL;
}

static int
write_direct8(png_structp png_ptr, png_infop info_ptr, i_img *im) {
  unsigned char *data, *volatile vdata = NULL;
  i_img_dim y;

  if (setjmp(png_jmpbuf(png_ptr))) {
    if (vdata)
      myfree(vdata);

    return 0;
  }

  png_write_info(png_ptr, info_ptr);

  vdata = data = mymalloc(im->xsize * im->channels);
  for (y = 0; y < im->ysize; y++) {
    i_gsamp(im, 0, im->xsize, y, data, NULL, im->channels);
    png_write_row(png_ptr, (png_bytep)data);
  }
  myfree(data);

  return 1;
}

static int
write_direct16(png_structp png_ptr, png_infop info_ptr, i_img *im) {
  unsigned *data, *volatile vdata = NULL;
  unsigned char *tran_data, * volatile vtran_data = NULL;
  i_img_dim samples_per_row = im->xsize * im->channels;
  
  i_img_dim y;

  if (setjmp(png_jmpbuf(png_ptr))) {
    if (vdata)
      myfree(vdata);
    if (vtran_data)
      myfree(vtran_data);

    return 0;
  }

  png_write_info(png_ptr, info_ptr);

  vdata = data = mymalloc(samples_per_row * sizeof(unsigned));
  vtran_data = tran_data = mymalloc(samples_per_row * 2);
  for (y = 0; y < im->ysize; y++) {
    i_img_dim i;
    unsigned char *p = tran_data;
    i_gsamp_bits(im, 0, im->xsize, y, data, NULL, im->channels, 16);
    for (i = 0; i < samples_per_row; ++i) {
      p[0] = data[i] >> 8;
      p[1] = data[i] & 0xff;
      p += 2;
    }
    png_write_row(png_ptr, (png_bytep)tran_data);
  }
  myfree(tran_data);
  myfree(data);

  return 1;
}

static int
write_paletted(png_structp png_ptr, png_infop info_ptr, i_img *im, int bits) {
  unsigned char *data, *volatile vdata = NULL;
  i_img_dim y;
  unsigned char pal_map[256];
  png_color pcolors[256];
  i_color colors[256];
  int count = i_colorcount(im);
  int i;

  if (setjmp(png_jmpbuf(png_ptr))) {
    if (vdata)
      myfree(vdata);

    return 0;
  }

  i_getcolors(im, 0, colors, count);
  if (im->channels < 3) {
    /* convert the greyscale palette to color */
    int i;
    for (i = 0; i < count; ++i) {
      i_color *c = colors + i;
      c->channel[3] = c->channel[1];
      c->channel[2] = c->channel[1] = c->channel[0];
    }
  }

  if (i_img_has_alpha(im)) {
    int i;
    int bottom_index = 0, top_index = count-1;

    /* fill out the palette map */
    for (i = 0; i < count; ++i)
      pal_map[i] = i;

    /* the PNG spec suggests sorting the palette by alpha, but that's
       unnecessary - all we want to do is move the opaque entries to
       the end */
    while (bottom_index < top_index) {
      if (colors[bottom_index].rgba.a == 255) {
	pal_map[bottom_index] = top_index;
	pal_map[top_index--] = bottom_index;
      }
      ++bottom_index;
    }
  }

  for (i = 0; i < count; ++i) {
    int srci = i_img_has_alpha(im) ? pal_map[i] : i;

    pcolors[i].red = colors[srci].rgb.r;
    pcolors[i].green = colors[srci].rgb.g;
    pcolors[i].blue = colors[srci].rgb.b;
  }

  png_set_PLTE(png_ptr, info_ptr, pcolors, count);

  if (i_img_has_alpha(im)) {
    unsigned char trans[256];
    int i;

    for (i = 0; i < count && colors[pal_map[i]].rgba.a != 255; ++i) {
      trans[i] = colors[pal_map[i]].rgba.a;
    }
    png_set_tRNS(png_ptr, info_ptr, trans, i, NULL);
  }

  png_write_info(png_ptr, info_ptr);

  png_set_packing(png_ptr);

  vdata = data = mymalloc(im->xsize);
  for (y = 0; y < im->ysize; y++) {
    i_gpal(im, 0, im->xsize, y, data);
    if (i_img_has_alpha(im)) {
      i_img_dim x;
      for (x = 0; x < im->xsize; ++x)
	data[x] = pal_map[data[x]];
    }
    png_write_row(png_ptr, (png_bytep)data);
  }
  myfree(data);

  return 1;
}

static int
write_bilevel(png_structp png_ptr, png_infop info_ptr, i_img *im) {
  unsigned char *data, *volatile vdata = NULL;
  i_img_dim y;

  if (setjmp(png_jmpbuf(png_ptr))) {
    if (vdata)
      myfree(vdata);

    return 0;
  }

  png_write_info(png_ptr, info_ptr);

  png_set_packing(png_ptr);

  vdata = data = mymalloc(im->xsize);
  for (y = 0; y < im->ysize; y++) {
    i_gsamp(im, 0, im->xsize, y, data, NULL, 1);
    png_write_row(png_ptr, (png_bytep)data);
  }
  myfree(data);

  return 1;
}

static void
read_warn_handler(png_structp png_ptr, png_const_charp msg) {
  i_png_read_statep rs = (i_png_read_statep)png_get_error_ptr(png_ptr);
  char *workp;
  size_t new_size;

  mm_log((1, "PNG read warning '%s'\n", msg));

  /* in case this is part of an error report */
  i_push_error(0, msg);
  
  /* and save in the warnings so if we do manage to succeed, we 
   * can save it as a tag
   */
  new_size = (rs->warnings ? strlen(rs->warnings) : 0)
    + 1 /* NUL */
    + strlen(msg) /* new text */
    + 1; /* newline */
  workp = myrealloc(rs->warnings, new_size);
  if (!rs->warnings)
    *workp = '\0';
  strcat(workp, msg);
  strcat(workp, "\n");
  rs->warnings = workp;
}

static void
cleanup_read_state(i_png_read_statep rs) {
  if (rs->warnings)
    myfree(rs->warnings);
}
