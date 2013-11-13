#include "imext.h"
#include "imicon.h"
#include "msicon.h"
#include <string.h>

static void
ico_push_error(int error) {
  char error_buf[ICO_MAX_MESSAGE];

  ico_error_message(error, error_buf, sizeof(error_buf));
  i_push_error(error, error_buf);
}

static
i_img *
read_one_icon(ico_reader_t *file, int index, int masked) {
  ico_image_t *image;
  int error;
  i_img *result;

  image = ico_image_read(file, index, &error);
  if (!image) {
    ico_push_error(error);
    i_push_error(0, "error reading ICO/CUR image");
    return NULL;
  }

  if (masked) {
    /* check to make sure we should do the masking, if the mask has
       nothing set we don't mask */
    int pos;
    int total = image->width * image->height;
    unsigned char *inp = image->mask_data;

    masked = 0;
    for (pos = 0; pos < total; ++pos) {
      if (*inp++) {
	masked = 1;
	break;
      }
    }
  }

  if (image->direct) {
    int x, y;
    i_color *line_buf;
    i_color *outp;
    ico_color_t *inp = image->image_data;
    int channels = masked || image->bit_count == 32 ? 4 : 3;

    if (!i_int_check_image_file_limits(image->width, image->height, channels, 1)) {
      ico_image_release(image);
      return NULL;
    }

    
    result = i_img_8_new(image->width, image->height, channels);
    if (!result) {
      ico_image_release(image);
      return NULL;
    }

    line_buf = mymalloc(image->width * sizeof(i_color));

    for (y = 0; y < image->height; ++y) {
      outp = line_buf;
      for (x = 0; x < image->width; ++x) {
	outp->rgba.r = inp->r;
	outp->rgba.g = inp->g;
	outp->rgba.b = inp->b;
	outp->rgba.a = inp->a;
	++outp;
	++inp;
      }
      i_plin(result, 0, image->width, y, line_buf);
    }

    myfree(line_buf);
  }
  else {
    int pal_index;
    int y;
    unsigned char *image_data;
    int channels = masked ? 4 : 3;

    if (!i_int_check_image_file_limits(image->width, image->height, channels, 1)) {
      ico_image_release(image);
      return NULL;
    }

    result = i_img_pal_new(image->width, image->height, channels, 256);
    if (!result) {
      ico_image_release(image);
      return NULL;
    }
    
    /* fill in the palette */
    for (pal_index = 0; pal_index < image->palette_size; ++pal_index) {
      i_color c;
      c.rgba.r = image->palette[pal_index].r;
      c.rgba.g = image->palette[pal_index].g;
      c.rgba.b = image->palette[pal_index].b;
      c.rgba.a = 255;

      if (i_addcolors(result, &c, 1) < 0) {
	i_push_error(0, "could not add color to palette");
	ico_image_release(image);
	i_img_destroy(result);
	return NULL;
      }
    }

    /* fill in the image data */
    image_data = image->image_data;
    for (y = 0; y < image->height; ++y) {
      i_ppal(result, 0, image->width, y, image_data);
      image_data += image->width;
    }
  }

  {
    unsigned char *inp = image->mask_data;
    char *outp;
    int x, y;
    char *mask;
    /* fill in the mask tag */
    /* space for " .\n", width + 1 chars per line and NUL */
    mask = mymalloc(3 + (image->width + 1) * image->height + 1);

    outp = mask;
    *outp++ = '.';
    *outp++ = '*';
    *outp++ = '\n';
    for (y = 0; y < image->height; ++y) {
      for (x = 0; x < image->width; ++x) {
	*outp++ = *inp++ ? '*' : '.';
      }
      if (y != image->height - 1) /* not on the last line */
	*outp++ = '\n';
    }
    *outp++ = '\0';

    if (ico_type(file) == ICON_ICON)
      i_tags_set(&result->tags, "ico_mask", mask, (outp-mask)-1);
    else
      i_tags_set(&result->tags, "cur_mask", mask, (outp-mask)-1);
    
    myfree(mask);
  }

  /* if the user requests, treat the mask as an alpha channel.
     Note: this converts the image into a direct image if it was paletted
  */
  if (masked) {
    unsigned char *inp = image->mask_data;
    int x, y;
    i_color *line_buf = mymalloc(sizeof(i_color) * image->width);

    for (y = 0; y < image->height; ++y) {
      int changed = 0;
      int first = 0;
      int last = 0;

      for (x = 0; x < image->width; ++x) {
	if (*inp++) {
	  if (!changed) {
	    first = x;
	    i_glin(result, first, image->width, y, line_buf);
	    changed = 1;
	  }
	  last = x;
	  line_buf[x-first].rgba.a = 0;
	}
      }
      if (changed) {
	i_plin(result, first, last + 1, y, line_buf);
      }
    }
    myfree(line_buf);
  }
  if (ico_type(file) == ICON_ICON) {
    i_tags_setn(&result->tags, "ico_bits", image->bit_count);
    i_tags_set(&result->tags, "i_format", "ico", 3);
  }
  else {
    i_tags_setn(&result->tags, "cur_bits", image->bit_count);
    i_tags_set(&result->tags, "i_format", "cur", 3);
    i_tags_setn(&result->tags, "cur_hotspotx", image->hotspot_x);
    i_tags_setn(&result->tags, "cur_hotspoty", image->hotspot_y);
  }

  ico_image_release(image);

  return result;
}

i_img *
i_readico_single(io_glue *ig, int index, int masked) {
  ico_reader_t *file;
  i_img *result;
  int error;

  i_clear_error();

  file = ico_reader_open(ig, &error);
  if (!file) {
    ico_push_error(error);
    i_push_error(0, "error opening ICO/CUR file");
    return NULL;
  }

  /* the index is range checked by msicon.c - don't duplicate it here */

  result = read_one_icon(file, index, masked);
  ico_reader_close(file);

  return result;
}

i_img **
i_readico_multi(io_glue *ig, int *count, int masked) {
  ico_reader_t *file;
  int index;
  int error;
  i_img **imgs;

  i_clear_error();

  file = ico_reader_open(ig, &error);
  if (!file) {
    ico_push_error(error);
    i_push_error(0, "error opening ICO/CUR file");
    return NULL;
  }

  imgs = mymalloc(sizeof(i_img *) * ico_image_count(file));

  *count = 0;
  for (index = 0; index < ico_image_count(file); ++index) {
    i_img *im = read_one_icon(file, index, masked);
    if (!im)
      break;

    imgs[(*count)++] = im;
  }

  ico_reader_close(file);

  if (*count == 0) {
    myfree(imgs);
    return NULL;
  }

  return imgs;
}

static int
validate_image(i_img *im) {
  if (im->xsize > 256 || im->ysize > 256) {
    i_push_error(0, "image too large for ico file");
    return 0;
  }
  if (im->channels < 1 || im->channels > 4) {
    /* this shouldn't happen, but check anyway */
    i_push_error(0, "invalid channels");
    return 0;
  }

  return 1;
}

static int
translate_mask(i_img *im, unsigned char *out, const char *in) {
  int x, y;
  int one, zero;
  int len = strlen(in);
  int pos;
  int newline; /* set to the first newline type we see */
  int notnewline; /* set to whatever in ( "\n\r" newline isn't ) */

  if (len < 3)
    return 0;

  zero = in[0];
  one = in[1];
  if (in[2] == '\n' || in[2] == '\r') {
    newline = in[2];
    notnewline = '\n' + '\r' - newline;
  }
  else {
    return 0;
  }

  pos = 3;
  y = 0;
  while (y < im->ysize && pos < len) {
    x = 0;
    while (x < im->xsize && pos < len) {
      if (in[pos] == newline) {
	/* don't process it, we look for it later */
	break;
      }
      else if (in[pos] == notnewline) {
	++pos; /* just drop it */
      }
      else if (in[pos] == one) {
	*out++ = 1;
        ++x;
	++pos;
      }
      else if (in[pos] == zero) {
	*out++ = 0;
        ++x;
	++pos;
      }
      else if (in[pos] == ' ' || in[pos] == '\t') {
	/* just ignore whitespace */
	++pos;
      }
      else {
	return 0;
      }
    }
    while (x++ < im->xsize) {
      *out++ = 0;
    }
    while (pos < len && in[pos] != newline)
      ++pos;
    if (pos < len && in[pos] == newline)
      ++pos; /* actually skip the newline */

    ++y;
  }
  while (y++ < im->ysize) {
    for (x = 0; x < im->xsize; ++x)
      *out++ = 0;
  }

  return 1;
}

static void 
derive_mask(i_img *im, ico_image_t *ico) {

  if (im->channels == 1 || im->channels == 3) {
    /* msicon.c's default mask is what we want */
    myfree(ico->mask_data);
    ico->mask_data = NULL;
  }
  else {
    int channel = im->channels - 1;
    i_sample_t *linebuf = mymalloc(sizeof(i_sample_t) * im->xsize);
    int x, y;
    unsigned char *out = ico->mask_data;

    for (y = 0; y < im->ysize; ++y) {
      i_gsamp(im, 0, im->xsize, y, linebuf, &channel, 1);
      for (x = 0; x < im->xsize; ++x) {
	*out++ = linebuf[x] == 255 ? 0 : 1;
      }
    }
    myfree(linebuf);
  }
}

static void
fill_image_base(i_img *im, ico_image_t *ico, const char *mask_name) {
  int x, y;

  ico->width = im->xsize;
  ico->height = im->ysize;
  ico->direct = im->type == i_direct_type;
  if (ico->direct) {
    int channels[4];
    int set_alpha = 0;
    ico_color_t *out;
    i_sample_t *in;
    unsigned char *linebuf = mymalloc(ico->width * 4);
    ico->image_data = mymalloc(sizeof(ico_color_t) * ico->width * ico->height);
    
    switch (im->channels) {
    case 1:
      channels[0] = channels[1] = channels[2] = channels[3] = 0;
      ++set_alpha;
      break;

    case 2:
      channels[0] = channels[1] = channels[2] = 0;
      channels[3] = 1;
      break;

    case 3:
      channels[0] = 0;
      channels[1] = 1;
      channels[2] = 2;
      channels[3] = 2;
      ++set_alpha;
      break;

    case 4:
      channels[0] = 0;
      channels[1] = 1;
      channels[2] = 2;
      channels[3] = 3;
      break;
    }
    
    out = ico->image_data;
    for (y = 0; y < im->ysize; ++y) {
      i_gsamp(im, 0, im->xsize, y, linebuf, channels, 4);
      in = linebuf;
      for (x = 0; x < im->xsize; ++x) {
	out->r = *in++;
	out->g = *in++;
	out->b = *in++;
	out->a = set_alpha ? 255 : *in;
	in++;
	++out;
      }
    }
    myfree(linebuf);
    ico->palette = NULL;
  }
  else {
    unsigned char *out;
    i_color *colors;
    int i;
    i_palidx *in;
    i_palidx *linebuf = mymalloc(sizeof(i_palidx) * ico->width);

    ico->image_data = mymalloc(sizeof(ico_color_t) * ico->width * ico->height);

    out = ico->image_data;
    for (y = 0; y < im->ysize; ++y) {
      i_gpal(im, 0, im->xsize, y, linebuf);
      in = linebuf;
      for (x = 0; x < im->xsize; ++x) {
	*out++ = *in++;
      }
    }
    myfree(linebuf);

    ico->palette_size = i_colorcount(im);
    ico->palette = mymalloc(sizeof(ico_color_t) * ico->palette_size);
    colors = mymalloc(sizeof(i_color) * ico->palette_size);
    i_getcolors(im, 0, colors, ico->palette_size);
    for (i = 0; i < ico->palette_size; ++i) {
      if (im->channels == 1 || im->channels == 2) {
	ico->palette[i].r = ico->palette[i].g =
	  ico->palette[i].b = colors[i].rgba.r;
      }
      else {
	ico->palette[i].r = colors[i].rgba.r;
	ico->palette[i].g = colors[i].rgba.g;
	ico->palette[i].b = colors[i].rgba.b;
      }
    }
    myfree(colors);
  }

  {
    /* build the mask */
    int mask_index;

    ico->mask_data = mymalloc(im->xsize * im->ysize);

    if (!i_tags_find(&im->tags, mask_name, 0, &mask_index)
        || !im->tags.tags[mask_index].data
        || !translate_mask(im, ico->mask_data, 
                           im->tags.tags[mask_index].data)) {
      derive_mask(im, ico);
    }
  }
}

static void
unfill_image(ico_image_t *ico) {
  myfree(ico->image_data);
  if (ico->palette)
    myfree(ico->palette);
  if (ico->mask_data)
    myfree(ico->mask_data);
}

static void
fill_image_icon(i_img *im, ico_image_t *ico) {
  fill_image_base(im, ico, "ico_mask");
  ico->hotspot_x = ico->hotspot_y = 0;
}

int
i_writeico_wiol(i_io_glue_t *ig, i_img *im) {
  ico_image_t ico;
  int error;

  i_clear_error();

  if (!validate_image(im))
    return 0;

  fill_image_icon(im, &ico);

  if (!ico_write(ig, &ico, 1, ICON_ICON, &error)) {
    ico_push_error(error);
    unfill_image(&ico);
    return 0;
  }

  unfill_image(&ico);

  if (i_io_close(ig) < 0) {
    i_push_error(0, "error closing output");
    return 0;
  }

  return 1;
}

int
i_writeico_multi_wiol(i_io_glue_t *ig, i_img **ims, int count) {
  ico_image_t *icons;
  int error;
  int i;

  i_clear_error();

  if (count > 0xFFFF) {
    i_push_error(0, "too many images for ico files");
    return 0;
  }

  for (i = 0; i < count; ++i)
    if (!validate_image(ims[i]))
      return 0;

  icons = mymalloc(sizeof(ico_image_t) * count);

  for (i = 0; i < count; ++i)
    fill_image_icon(ims[i], icons + i);

  if (!ico_write(ig, icons, count, ICON_ICON, &error)) {
    ico_push_error(error);
    for (i = 0; i < count; ++i)
      unfill_image(icons + i);
    myfree(icons);
    return 0;
  }

  for (i = 0; i < count; ++i)
    unfill_image(icons + i);
  myfree(icons);

  if (i_io_close(ig) < 0) {
    i_push_error(0, "error closing output");
    return 0;
  }

  return 1;
}

void
fill_image_cursor(i_img *im, ico_image_t *ico) {
  int hotx, hoty;
  fill_image_base(im, ico, "ico_mask");

  if (!i_tags_get_int(&im->tags, "cur_hotspotx", 0, &hotx))
    hotx = 0;
  if (!i_tags_get_int(&im->tags, "cur_hotspoty", 0, &hoty))
    hoty = 0;

  if (hotx < 0)
    hotx = 0;
  else if (hotx >= im->xsize)
    hotx = im->xsize - 1;

  if (hoty < 0)
    hoty = 0;
  else if (hoty >= im->ysize)
    hoty = im->ysize - 1;
  
  ico->hotspot_x = hotx;
  ico->hotspot_y = hoty;
}

int
i_writecur_wiol(i_io_glue_t *ig, i_img *im) {
  ico_image_t ico;
  int error;

  i_clear_error();

  if (!validate_image(im))
    return 0;

  fill_image_cursor(im, &ico);

  if (!ico_write(ig, &ico, 1, ICON_CURSOR, &error)) {
    ico_push_error(error);
    unfill_image(&ico);
    return 0;
  }

  unfill_image(&ico);

  if (i_io_close(ig) < 0) {
    i_push_error(0, "error closing output");
    return 0;
  }

  return 1;
}

int
i_writecur_multi_wiol(i_io_glue_t *ig, i_img **ims, int count) {
  ico_image_t *icons;
  int error;
  int i;

  i_clear_error();

  if (count > 0xFFFF) {
    i_push_error(0, "too many images for ico files");
    return 0;
  }

  for (i = 0; i < count; ++i)
    if (!validate_image(ims[i]))
      return 0;

  icons = mymalloc(sizeof(ico_image_t) * count);

  for (i = 0; i < count; ++i)
    fill_image_cursor(ims[i], icons + i);

  if (!ico_write(ig, icons, count, ICON_CURSOR, &error)) {
    ico_push_error(error);
    for (i = 0; i < count; ++i)
      unfill_image(icons + i);
    myfree(icons);
    return 0;
  }

  for (i = 0; i < count; ++i)
    unfill_image(icons + i);
  myfree(icons);

  if (i_io_close(ig) < 0) {
    i_push_error(0, "error closing output");
    return 0;
  }

  return 1;
}

