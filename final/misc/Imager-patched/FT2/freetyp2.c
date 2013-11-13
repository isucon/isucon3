/*
=head1 NAME

freetyp2.c - font support via the FreeType library version 2.

=head1 SYNOPSIS

  if (!i_ft2_init()) { error }
  FT2_Fonthandle *font;
  font = i_ft2_new(name, index);
  if (!i_ft2_setdpi(font, xdpi, ydpi)) { error }
  if (!i_ft2_getdpi(font, &xdpi, &ydpi)) { error }
  double matrix[6];
  if (!i_ft2_settransform(font, matrix)) { error }
  i_img_dim bbox[BOUNDING_BOX_COUNT];
  if (!i_ft2_bbox(font, cheight, cwidth, text, length, bbox, utf8)) { error }
  i_img *im = ...;
  i_color cl;
  if (!i_ft2_text(font, im, tx, ty, cl, cheight, cwidth, text, length, align,
                  aa, vlayout, utf8)) { error }
  if (!i_ft2_cp(font, im, tx, ty, channel, cheight, cwidth, text, length,
                align, aa)) { error }
  i_ft2_destroy(font);

=head1 DESCRIPTION

Implements Imager font support using the FreeType2 library.

The FreeType2 library understands several font file types, including
Truetype, Type1 and Windows FNT.

=over 

=cut
*/

#include "imext.h"
#include "imft2.h"
#include <stdio.h>
#include <math.h>
#include <string.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#ifdef FT_MULTIPLE_MASTERS_H
#ifndef T1_CONFIG_OPTION_NO_MM_SUPPORT
#define IM_FT2_MM
#include FT_MULTIPLE_MASTERS_H
#endif
#endif

static void ft2_push_message(int code);

static void ft2_final(void *);

static im_slot_t slot = -1;

typedef struct {
  int initialized;
  FT_Library library;
  im_context_t ctx;
} ft2_state;

static ft2_state *
i_ft2_init(void);

static i_img_dim i_min(i_img_dim a, i_img_dim b);
static i_img_dim i_max(i_img_dim a, i_img_dim b);

int
i_ft2_version(int runtime, char *buf, size_t buf_size) {
  char work[100];

  i_clear_error();

  if (buf_size == 0) {
    i_push_error(0, "zero size buffer supplied");
    return 0;
  }
  if (runtime) {
    ft2_state *ft2;
    /* initialized to work around a bug in FT2
       http://lists.nongnu.org/archive/html/freetype-devel/2002-09/msg00058.html
       Though I don't know why I still see this in 2.4.2
     */
    FT_Int major = 1, minor = 1, patch = 1;

    if ((ft2 = i_ft2_init()) == NULL)
      return 0;

    FT_Library_Version(ft2->library, &major, &minor, &patch);
    sprintf(work, "%d.%d.%d", (int)major, (int)minor, (int)patch);
  }
  else {
    sprintf(work, "%d.%d.%d", FREETYPE_MAJOR, FREETYPE_MINOR, FREETYPE_PATCH);
  }
  strncpy(buf, work, buf_size);
  buf[buf_size-1] = '\0';

  return 1;
}

void
i_ft2_start(void) {
  if (slot == -1)
    slot = im_context_slot_new(ft2_final);
}

/*
=item i_ft2_init(void)

Initializes the Freetype 2 library.

Returns ft2_state * on success or NULL on failure.

=cut
*/

static ft2_state *
i_ft2_init(void) {
  FT_Error error;
  im_context_t ctx = im_get_context();
  ft2_state *ft2 = im_context_slot_get(ctx, slot);

  if (ft2 == NULL) {
    ft2 = mymalloc(sizeof(ft2_state));
    ft2->initialized = 0;
    ft2->library = NULL;
    ft2->ctx = ctx;
    im_context_slot_set(ctx, slot, ft2);
    mm_log((1, "created FT2 state %p for context %p\n", ft2, ctx));
  }

  i_clear_error();
  if (!ft2->initialized) {
    error = FT_Init_FreeType(&ft2->library);
    if (error) {
      ft2_push_message(error);
      i_push_error(0, "Initializing Freetype2");
      return NULL;
    }
    mm_log((1, "initialized FT2 state %p\n", ft2));

    ft2->initialized = 1;
  }

  return ft2;
}

static void
ft2_final(void *state) {
  ft2_state *ft2 = state;

  if (ft2->initialized) {
    mm_log((1, "finalizing FT2 state %p\n", state));
    FT_Done_FreeType(ft2->library);
    ft2->library = NULL;
    ft2->initialized = 0;
  }

  mm_log((1, "freeing FT2 state %p\n", state));
  myfree(state);
}

struct FT2_Fonthandle {
  FT_Face face;
  ft2_state *state;
  int xdpi, ydpi;
  int hint;
  FT_Encoding encoding;

  /* used to adjust so we can align the draw point to the top-left */
  double matrix[6];

#ifdef IM_FT2_MM
  /* Multiple master data if any */
  int has_mm;
  FT_Multi_Master mm;
#endif
};

/* the following is used to select a "best" encoding */
static struct enc_score {
  FT_Encoding encoding;
  int score;
} enc_scores[] =
{
  /* the selections here are fairly arbitrary
     ideally we need to give the user a list of encodings available
     and a mechanism to choose one */
  { ft_encoding_unicode,        10 },
  { ft_encoding_sjis,            8 },
  { ft_encoding_gb2312,          8 },
  { ft_encoding_big5,            8 },
  { ft_encoding_wansung,         8 },
  { ft_encoding_johab,           8 },  
  { ft_encoding_latin_2,         6 },
  { ft_encoding_apple_roman,     6 },
  { ft_encoding_adobe_standard,  6 },
  { ft_encoding_adobe_expert,    6 },
};

/*
=item i_ft2_new(char *name, int index)

Creates a new font object, from the file given by I<name>.  I<index>
is the index of the font in a file with multiple fonts, where 0 is the
first font.

Return NULL on failure.

=cut
*/

FT2_Fonthandle *
i_ft2_new(const char *name, int index) {
  FT_Error error;
  FT2_Fonthandle *result;
  FT_Face face;
  int i, j;
  FT_Encoding encoding;
  int score;
  ft2_state *ft2;

  mm_log((1, "i_ft2_new(name %p, index %d)\n", name, index));

  if ((ft2 = i_ft2_init()) == NULL)
    return NULL;

  i_clear_error();
  error = FT_New_Face(ft2->library, name, index, &face);
  if (error) {
    ft2_push_message(error);
    i_push_error(error, "Opening face");
    mm_log((2, "error opening face '%s': %d\n", name, error));
    return NULL;
  }

  encoding = face->num_charmaps ? face->charmaps[0]->encoding : ft_encoding_unicode;
  score = 0;
  for (i = 0; i < face->num_charmaps; ++i) {
    FT_Encoding enc_entry = face->charmaps[i]->encoding;
    mm_log((2, "i_ft2_new, encoding %X platform %u encoding %u\n",
            (unsigned)enc_entry, face->charmaps[i]->platform_id,
            face->charmaps[i]->encoding_id));
    for (j = 0; j < sizeof(enc_scores) / sizeof(*enc_scores); ++j) {
      if (enc_scores[j].encoding == enc_entry && enc_scores[j].score > score) {
        encoding = enc_entry;
        score = enc_scores[j].score;
        break;
      }
    }
  }
  FT_Select_Charmap(face, encoding);
  mm_log((2, "i_ft2_new, selected encoding %X\n", (unsigned)encoding));

  result = mymalloc(sizeof(FT2_Fonthandle));
  result->face = face;
  result->state = ft2;
  result->xdpi = result->ydpi = 72;
  result->encoding = encoding;

  /* by default we disable hinting on a call to i_ft2_settransform()
     if we don't do this, then the hinting can the untransformed text
     to be a different size to the transformed text.
     Obviously we have it initially enabled.
  */
  result->hint = 1; 

  /* I originally forgot this:   :/ */
  /*i_ft2_settransform(result, matrix); */
  result->matrix[0] = 1; result->matrix[1] = 0; result->matrix[2] = 0;
  result->matrix[3] = 0; result->matrix[4] = 1; result->matrix[5] = 0;

#ifdef IM_FT2_MM
 {
   FT_Multi_Master *mm = &result->mm;
   int i;

   if ((face->face_flags & FT_FACE_FLAG_MULTIPLE_MASTERS) != 0 
       && (error = FT_Get_Multi_Master(face, mm)) == 0) {
     mm_log((2, "MM Font, %d axes, %d designs\n", mm->num_axis, mm->num_designs));
     for (i = 0; i < mm->num_axis; ++i) {
       mm_log((2, "  axis %d name %s range %ld - %ld\n", i, mm->axis[i].name,
               (long)(mm->axis[i].minimum), (long)(mm->axis[i].maximum)));
     }
     result->has_mm = 1;
   }
   else {
     mm_log((2, "No multiple masters\n"));
     result->has_mm = 0;
   }
 }
#endif

  return result;
}

/*
=item i_ft2_destroy(FT2_Fonthandle *handle)

Destroys a font object, which must have been the return value of
i_ft2_new().

=cut
*/
void
i_ft2_destroy(FT2_Fonthandle *handle) {
  FT_Done_Face(handle->face);
  myfree(handle);
}

/*
=item i_ft2_setdpi(FT2_Fonthandle *handle, int xdpi, int ydpi)

Sets the resolution in dots per inch at which point sizes scaled, by
default xdpi and ydpi are 72, so that 1 point maps to 1 pixel.

Both xdpi and ydpi should be positive.

Return true on success.

=cut
*/
int
i_ft2_setdpi(FT2_Fonthandle *handle, int xdpi, int ydpi) {
  i_clear_error();
  if (xdpi > 0 && ydpi > 0) {
    handle->xdpi = xdpi;
    handle->ydpi = ydpi;
    return 1;
  }
  else {
    i_push_error(0, "resolutions must be positive");
    return 0;
  }
}

/*
=item i_ft2_getdpi(FT2_Fonthandle *handle, int *xdpi, int *ydpi)

Retrieves the current horizontal and vertical resolutions at which
point sizes are scaled.

=cut
*/
int
i_ft2_getdpi(FT2_Fonthandle *handle, int *xdpi, int *ydpi) {
  *xdpi = handle->xdpi;
  *ydpi = handle->ydpi;

  return 1;
}

/*
=item i_ft2_settransform(FT2_FontHandle *handle, double *matrix)

Sets a transormation matrix for output.

This should be a 2 x 3 matrix like:

 matrix[0]   matrix[1]   matrix[2]
 matrix[3]   matrix[4]   matrix[5]

=cut
*/
int
i_ft2_settransform(FT2_Fonthandle *handle, const double *matrix) {
  FT_Matrix m;
  FT_Vector v;
  int i;

  m.xx = matrix[0] * 65536;
  m.xy = matrix[1] * 65536;
  v.x  = matrix[2]; /* this could be pels of 26.6 fixed - not sure */
  m.yx = matrix[3] * 65536;
  m.yy = matrix[4] * 65536;
  v.y  = matrix[5]; /* see just above */

  FT_Set_Transform(handle->face, &m, &v);

  for (i = 0; i < 6; ++i)
    handle->matrix[i] = matrix[i];
  handle->hint = 0;

  return 1;
}

/*
=item i_ft2_sethinting(FT2_Fonthandle *handle, int hinting)

If hinting is non-zero then glyph hinting is enabled, otherwise disabled.

i_ft2_settransform() disables hinting to prevent distortions in
gradual text transformations.

=cut
*/
int i_ft2_sethinting(FT2_Fonthandle *handle, int hinting) {
  handle->hint = hinting;
  return 1;
}

/*
=item i_ft2_bbox(FT2_Fonthandle *handle, double cheight, double cwidth, char *text, size_t len, i_img_dim *bbox)

Retrieves bounding box information for the font at the given 
character width and height.  This ignores the transformation matrix.

Returns non-zero on success.

=cut
*/
int
i_ft2_bbox(FT2_Fonthandle *handle, double cheight, double cwidth, 
           char const *text, size_t len, i_img_dim *bbox, int utf8) {
  FT_Error error;
  i_img_dim width;
  int index;
  int first;
  int ascent = 0, descent = 0;
  int glyph_ascent, glyph_descent;
  FT_Glyph_Metrics *gm;
  int start = 0;
  int loadFlags = FT_LOAD_DEFAULT;
  int rightb = 0;

  i_clear_error();

  mm_log((1, "i_ft2_bbox(handle %p, cheight %f, cwidth %f, text %p, len %u, bbox %p)\n",
	  handle, cheight, cwidth, text, (unsigned)len, bbox));

  error = FT_Set_Char_Size(handle->face, cwidth*64, cheight*64, 
                           handle->xdpi, handle->ydpi);
  if (error) {
    ft2_push_message(error);
    i_push_error(0, "setting size");
  }

  if (!handle->hint)
    loadFlags |= FT_LOAD_NO_HINTING;

  first = 1;
  width = 0;
  while (len) {
    unsigned long c;
    if (utf8) {
      c = i_utf8_advance(&text, &len);
      if (c == ~0UL) {
        i_push_error(0, "invalid UTF8 character");
        return 0;
      }
    }
    else {
      c = (unsigned char)*text++;
      --len;
    }

    index = FT_Get_Char_Index(handle->face, c);
    error = FT_Load_Glyph(handle->face, index, loadFlags);
    if (error) {
      ft2_push_message(error);
      i_push_errorf(0, "loading glyph for character \\x%02lx (glyph 0x%04X)", 
                    c, index);
      return 0;
    }
    gm = &handle->face->glyph->metrics;
    glyph_ascent = gm->horiBearingY / 64;
    glyph_descent = glyph_ascent - gm->height/64;
    if (first) {
      start = gm->horiBearingX / 64;
      /* handles -ve values properly */
      ascent = glyph_ascent;
      descent = glyph_descent;
      first = 0;
    }

    if (glyph_ascent > ascent)
      ascent = glyph_ascent;
    if (glyph_descent < descent)
      descent = glyph_descent;

    width += gm->horiAdvance / 64;

    if (len == 0) {
      /* last character 
       handle the case where the right the of the character overlaps the 
       right*/
      rightb = (gm->horiAdvance - gm->horiBearingX - gm->width)/64;
      /*if (rightb > 0)
        rightb = 0;*/
    }
  }

  bbox[BBOX_NEG_WIDTH] = start;
  bbox[BBOX_GLOBAL_DESCENT] = handle->face->size->metrics.descender / 64;
  bbox[BBOX_POS_WIDTH] = width;
  if (rightb < 0)
    bbox[BBOX_POS_WIDTH] -= rightb;
  bbox[BBOX_GLOBAL_ASCENT] = handle->face->size->metrics.ascender / 64;
  bbox[BBOX_DESCENT] = descent;
  bbox[BBOX_ASCENT] = ascent;
  bbox[BBOX_ADVANCE_WIDTH] = width;
  bbox[BBOX_RIGHT_BEARING] = rightb;
  mm_log((1, " bbox=> negw=%" i_DF " glob_desc=%" i_DF " pos_wid=%" i_DF
	  " glob_asc=%" i_DF " desc=%" i_DF " asc=%" i_DF " adv_width=%" i_DF
	  " rightb=%" i_DF "\n",
	  i_DFc(bbox[0]), i_DFc(bbox[1]), i_DFc(bbox[2]), i_DFc(bbox[3]),
	  i_DFc(bbox[4]), i_DFc(bbox[5]), i_DFc(bbox[6]), i_DFc(bbox[7])));

  return BBOX_RIGHT_BEARING + 1;
}

/*
=item transform_box(FT2_FontHandle *handle, int bbox[4])

bbox contains coorinates of a the top-left and bottom-right of a bounding 
box relative to a point.

This is then transformed and the values in bbox[4] are the top-left
and bottom-right of the new bounding box.

This is meant to provide the bounding box of a transformed character
box.  The problem is that if the character was round and is rotated,
the real bounding box isn't going to be much different from the
original, but this function will return a _bigger_ bounding box.  I
suppose I could work my way through the glyph outline, but that's
too much hard work.

=cut
*/
void ft2_transform_box(FT2_Fonthandle *handle, i_img_dim bbox[4]) {
  double work[8];
  double *matrix = handle->matrix;
  
  work[0] = matrix[0] * bbox[0] + matrix[1] * bbox[1];
  work[1] = matrix[3] * bbox[0] + matrix[4] * bbox[1];
  work[2] = matrix[0] * bbox[2] + matrix[1] * bbox[1];
  work[3] = matrix[3] * bbox[2] + matrix[4] * bbox[1];
  work[4] = matrix[0] * bbox[0] + matrix[1] * bbox[3];
  work[5] = matrix[3] * bbox[0] + matrix[4] * bbox[3];
  work[6] = matrix[0] * bbox[2] + matrix[1] * bbox[3];
  work[7] = matrix[3] * bbox[2] + matrix[4] * bbox[3];

  bbox[0] = floor(i_min(i_min(work[0], work[2]),i_min(work[4], work[6])));
  bbox[1] = floor(i_min(i_min(work[1], work[3]),i_min(work[5], work[7])));
  bbox[2] = ceil(i_max(i_max(work[0], work[2]),i_max(work[4], work[6])));
  bbox[3] = ceil(i_max(i_max(work[1], work[3]),i_max(work[5], work[7])));
}

/*
=item expand_bounds(int bbox[4], int bbox2[4]) 

Treating bbox[] and bbox2[] as 2 bounding boxes, produces a new
bounding box in bbox[] that encloses both.

=cut
*/
static void expand_bounds(i_img_dim bbox[4], i_img_dim bbox2[4]) {
  bbox[0] = i_min(bbox[0], bbox2[0]);
  bbox[1] = i_min(bbox[1], bbox2[1]);
  bbox[2] = i_max(bbox[2], bbox2[2]);
  bbox[3] = i_max(bbox[3], bbox2[3]);
}

/*
=item i_ft2_bbox_r(FT2_Fonthandle *handle, double cheight, double cwidth, char *text, size_t len, int vlayout, int utf8, i_img_dim *bbox)

Retrieves bounding box information for the font at the given 
character width and height.

This version finds the rectangular bounding box of the glyphs, with
the text as transformed by the transformation matrix.  As with
i_ft2_bbox (bbox[0], bbox[1]) will the the offset from the start of
the topline to the top-left of the bounding box.  Unlike i_ft2_bbox()
this could be near the bottom left corner of the box.

(bbox[4], bbox[5]) is the offset to the start of the baseline.
(bbox[6], bbox[7]) is the offset from the start of the baseline to the
end of the baseline.

Returns non-zero on success.

=cut
*/
int
i_ft2_bbox_r(FT2_Fonthandle *handle, double cheight, double cwidth, 
           char const *text, size_t len, int vlayout, int utf8, i_img_dim *bbox) {
  FT_Error error;
  int index;
  int first;
  i_img_dim ascent = 0, descent = 0;
  int glyph_ascent, glyph_descent;
  FT_Glyph_Metrics *gm;
  i_img_dim work[4];
  i_img_dim bounds[4] = { 0 };
  double x = 0, y = 0;
  int i;
  FT_GlyphSlot slot;
  int loadFlags = FT_LOAD_DEFAULT;

  if (vlayout)
    loadFlags |= FT_LOAD_VERTICAL_LAYOUT;
  if (!handle->hint)
    loadFlags |= FT_LOAD_NO_HINTING;

  error = FT_Set_Char_Size(handle->face, cwidth*64, cheight*64, 
                           handle->xdpi, handle->ydpi);
  if (error) {
    ft2_push_message(error);
    i_push_error(0, "setting size");
  }

  first = 1;
  while (len) {
    unsigned long c;
    if (utf8) {
      c = i_utf8_advance(&text, &len);
      if (c == ~0UL) {
        i_push_error(0, "invalid UTF8 character");
        return 0;
      }
    }
    else {
      c = (unsigned char)*text++;
      --len;
    }

    index = FT_Get_Char_Index(handle->face, c);
    error = FT_Load_Glyph(handle->face, index, loadFlags);
    if (error) {
      ft2_push_message(error);
      i_push_errorf(0, "loading glyph for character \\x%02lx (glyph 0x%04X)",
                    c, index);
      return 0;
    }
    slot = handle->face->glyph; 
    gm = &slot->metrics;

    /* these probably don't mean much for vertical layouts */
    glyph_ascent = gm->horiBearingY / 64;
    glyph_descent = glyph_ascent - gm->height/64;
    if (vlayout) {
      work[0] = gm->vertBearingX;
      work[1] = gm->vertBearingY;
    }
    else {
      work[0] = gm->horiBearingX;
      work[1] = gm->horiBearingY;
    }
    work[2] = gm->width  + work[0];
    work[3] = work[1] - gm->height;
    if (first) {
      bbox[4] = work[0] * handle->matrix[0] + work[1] * handle->matrix[1] + handle->matrix[2];
      bbox[5] = work[0] * handle->matrix[3] + work[1] * handle->matrix[4] + handle->matrix[5];
      bbox[4] = bbox[4] < 0 ? -(-bbox[4] + 32)/64 : (bbox[4] + 32) / 64;
      bbox[5] /= 64;
    }
    ft2_transform_box(handle, work);
    for (i = 0; i < 4; ++i)
      work[i] /= 64;
    work[0] += x;
    work[1] += y;
    work[2] += x;
    work[3] += y;
    if (first) {
      for (i = 0; i < 4; ++i)
        bounds[i] = work[i];
      ascent = glyph_ascent;
      descent = glyph_descent;
      first = 0;
    }
    else {
      expand_bounds(bounds, work);
    }
    x += slot->advance.x / 64;
    y += slot->advance.y / 64;

    if (glyph_ascent > ascent)
      ascent = glyph_ascent;
    if (glyph_descent > descent)
      descent = glyph_descent;

    if (len == 0) {
      /* last character 
       handle the case where the right the of the character overlaps the 
       right*/
      /*int rightb = gm->horiAdvance - gm->horiBearingX - gm->width;
      if (rightb < 0)
      width -= rightb / 64;*/
    }
  }

  /* at this point bounds contains the bounds relative to the CP,
     and x, y hold the final position relative to the CP */
  /*bounds[0] -= x;
  bounds[1] -= y;
  bounds[2] -= x;
  bounds[3] -= y;*/

  bbox[0] = bounds[0];
  bbox[1] = -bounds[3];
  bbox[2] = bounds[2];
  bbox[3] = -bounds[1];
  bbox[6] = x;
  bbox[7] = -y;

  return 1;
}

static int
make_bmp_map(FT_Bitmap *bitmap, unsigned char *map);

/*
=item i_ft2_text(FT2_Fonthandle *handle, i_img *im, int tx, int ty, i_color *cl, double cheight, double cwidth, char *text, size_t len, int align, int aa)

Renders I<text> to (I<tx>, I<ty>) in I<im> using color I<cl> at the given 
I<cheight> and I<cwidth>.

If align is 0, then the text is rendered with the top-left of the
first character at (I<tx>, I<ty>).  If align is non-zero then the text
is rendered with (I<tx>, I<ty>) aligned with the base-line of the
characters.

If aa is non-zero then the text is anti-aliased.

Returns non-zero on success.

=cut
*/
int
i_ft2_text(FT2_Fonthandle *handle, i_img *im, i_img_dim tx, i_img_dim ty, const i_color *cl,
           double cheight, double cwidth, char const *text, size_t len,
	   int align, int aa, int vlayout, int utf8) {
  FT_Error error;
  int index;
  FT_Glyph_Metrics *gm;
  i_img_dim bbox[BOUNDING_BOX_COUNT];
  FT_GlyphSlot slot;
  int x, y;
  unsigned char map[256];
  char last_mode = ft_pixel_mode_none; 
  int last_grays = -1;
  int loadFlags = FT_LOAD_DEFAULT;
  i_render *render = NULL;
  unsigned char *work_bmp = NULL;
  size_t work_bmp_size = 0;

  mm_log((1, "i_ft2_text(handle %p, im %p, (tx,ty) (" i_DFp "), cl %p (#%02x%02x%02x%02x), cheight %f, cwidth %f, text %p, len %u, align %d, aa %d, vlayout %d, utf8 %d)\n",
	  handle, im, i_DFcp(tx, ty), cl, cl->rgba.r, cl->rgba.g, cl->rgba.b,
	  cl->rgba.a, cheight, cwidth, text, (unsigned)len, align, aa,
	  vlayout, utf8));

  i_clear_error();

  if (vlayout) {
    if (!FT_HAS_VERTICAL(handle->face)) {
      i_push_error(0, "face has no vertical metrics");
      return 0;
    }
    loadFlags |= FT_LOAD_VERTICAL_LAYOUT;
  }
  if (!handle->hint)
    loadFlags |= FT_LOAD_NO_HINTING;

  /* set the base-line based on the string ascent */
  if (!i_ft2_bbox(handle, cheight, cwidth, text, len, bbox, utf8))
    return 0;

  render = i_render_new(im, bbox[BBOX_POS_WIDTH] - bbox[BBOX_NEG_WIDTH]);

  work_bmp_size = bbox[BBOX_POS_WIDTH] - bbox[BBOX_NEG_WIDTH];
  work_bmp = mymalloc(work_bmp_size);

  if (!align) {
    /* this may need adjustment */
    tx -= bbox[0] * handle->matrix[0] + bbox[5] * handle->matrix[1] + handle->matrix[2];
    ty += bbox[0] * handle->matrix[3] + bbox[5] * handle->matrix[4] + handle->matrix[5];
  }
  while (len) {
    unsigned long c;
    if (utf8) {
      c = i_utf8_advance(&text, &len);
      if (c == ~0UL) {
        i_push_error(0, "invalid UTF8 character");
        return 0;
      }
    }
    else {
      c = (unsigned char)*text++;
      --len;
    }
    
    index = FT_Get_Char_Index(handle->face, c);
    error = FT_Load_Glyph(handle->face, index, loadFlags);
    if (error) {
      ft2_push_message(error);
      i_push_errorf(0, "loading glyph for character \\x%02lx (glyph 0x%04X)",
                    c, index);
      if (render)
        i_render_delete(render);
      return 0;
    }
    slot = handle->face->glyph;
    gm = &slot->metrics;

    if (gm->width) {
      error = FT_Render_Glyph(slot, aa ? ft_render_mode_normal : ft_render_mode_mono);
      if (error) {
	ft2_push_message(error);
	i_push_errorf(0, "rendering glyph 0x%04lX (character \\x%02X)", c, index);
	if (render)
	  i_render_delete(render);
	return 0;
      }
      if (slot->bitmap.pixel_mode == ft_pixel_mode_mono) {
	unsigned char *bmp = slot->bitmap.buffer;
	if (work_bmp_size < slot->bitmap.width) {
	  work_bmp_size = slot->bitmap.width;
	  work_bmp =  myrealloc(work_bmp, work_bmp_size);
	}
	for (y = 0; y < slot->bitmap.rows; ++y) {
	  int pos = 0;
	  int bit = 0x80;
	  unsigned char *p = work_bmp;
	  for (x = 0; x < slot->bitmap.width; ++x) {
	    *p++ = (bmp[pos] & bit) ? 0xff : 0;

	    bit >>= 1;
	    if (bit == 0) {
	      bit = 0x80;
	      ++pos;
	    }
	  }
          i_render_color(render, tx + slot->bitmap_left, ty-slot->bitmap_top+y,
                         slot->bitmap.width, work_bmp, cl);

	  bmp += slot->bitmap.pitch;
	}
      }
      else {
	unsigned char *bmp = slot->bitmap.buffer;

	/* grey scale or something we can treat as greyscale */
	/* we create a map to convert from the bitmap values to 0-255 */
	if (last_mode != slot->bitmap.pixel_mode 
	    || last_grays != slot->bitmap.num_grays) {
	  if (!make_bmp_map(&slot->bitmap, map))
	    return 0;
	  last_mode = slot->bitmap.pixel_mode;
	  last_grays = slot->bitmap.num_grays;
	}

	for (y = 0; y < slot->bitmap.rows; ++y) {
          if (last_mode == ft_pixel_mode_grays &&
              last_grays != 255) {
            for (x = 0; x < slot->bitmap.width; ++x) 
              bmp[x] = map[bmp[x]];
          }
          i_render_color(render, tx + slot->bitmap_left, ty-slot->bitmap_top+y,
                         slot->bitmap.width, bmp, cl);
	  bmp += slot->bitmap.pitch;
	}
      }
    }

    tx += slot->advance.x / 64;
    ty -= slot->advance.y / 64;
  }

  if (render)
    i_render_delete(render);

  if (work_bmp)
    myfree(work_bmp);

  return 1;
}

/*
=item i_ft2_cp(FT2_Fonthandle *handle, i_img *im, int tx, int ty, int channel, double cheight, double cwidth, char *text, size_t len, int align, int aa, int vlayout, int utf8)

Renders I<text> to (I<tx>, I<ty>) in I<im> to I<channel> at the given 
I<cheight> and I<cwidth>.

If align is 0, then the text is rendered with the top-left of the
first character at (I<tx>, I<ty>).  If align is non-zero then the text
is rendered with (I<tx>, I<ty>) aligned with the base-line of the
characters.

If C<utf8> is non-zero the text is treated as UTF-8 encoded

If C<aa> is non-zero then the text is drawn anti-aliased.

Returns non-zero on success.

=cut
*/

int
i_ft2_cp(FT2_Fonthandle *handle, i_img *im, i_img_dim tx, i_img_dim ty, int channel,
         double cheight, double cwidth, char const *text, size_t len, int align,
         int aa, int vlayout, int utf8) {
  i_img_dim bbox[8];
  i_img *work;
  i_color cl;
  int y;
  unsigned char *bmp;

  mm_log((1, "i_ft2_cp(handle %p, im %p, (tx, ty) (" i_DFp "), channel %d, cheight %f, cwidth %f, text %p, len %u, align %d, aa %d, vlayout %d, utf8 %d)\n", 
	  handle, im, i_DFcp(tx, ty), channel, cheight, cwidth, text, (unsigned)len, align, aa, vlayout, utf8));

  i_clear_error();

  if (vlayout && !FT_HAS_VERTICAL(handle->face)) {
    i_push_error(0, "face has no vertical metrics");
    return 0;
  }

  if (!i_ft2_bbox_r(handle, cheight, cwidth, text, len, vlayout, utf8, bbox))
    return 0;

  work = i_img_8_new(bbox[2]-bbox[0]+1, bbox[3]-bbox[1]+1, 1);
  cl.channel[0] = 255;
  cl.channel[1] = 255;
  if (!i_ft2_text(handle, work, -bbox[0], -bbox[1], &cl, cheight, cwidth, 
                  text, len, 1, aa, vlayout, utf8))
    return 0;

  if (!align) {
    tx -= bbox[4];
    ty += bbox[5];
  }
  
  /* render to the specified channel */
  /* this will be sped up ... */
  bmp = mymalloc(work->xsize);
  for (y = 0; y < work->ysize; ++y) {
    i_gsamp(work, 0, work->xsize, y, bmp, NULL, 1);
    i_psamp(im, tx + bbox[0], tx + bbox[0] + work->xsize,
	    ty + y + bbox[1], bmp, &channel, 1);
  }
  myfree(bmp);
  i_img_destroy(work);
  return 1;
}

/*
=item i_ft2_has_chars(handle, char *text, size_t len, int utf8, char *out)

Check if the given characters are defined by the font.

Returns the number of characters that were checked.

=cut
*/
size_t
i_ft2_has_chars(FT2_Fonthandle *handle, char const *text, size_t len, 
                    int utf8, char *out) {
  int count = 0;
  mm_log((1, "i_ft2_has_chars(handle %p, text %p, len %u, utf8 %d)\n", 
	  handle, text, (unsigned)len, utf8));

  i_clear_error();

  while (len) {
    unsigned long c;
    int index;
    if (utf8) {
      c = i_utf8_advance(&text, &len);
      if (c == ~0UL) {
        i_push_error(0, "invalid UTF8 character");
        return 0;
      }
    }
    else {
      c = (unsigned char)*text++;
      --len;
    }
    
    index = FT_Get_Char_Index(handle->face, c);
    *out++ = index != 0;
    ++count;
  }

  return count;
}

/* uses a method described in fterrors.h to build an error translation
   function
*/
#undef __FTERRORS_H__
#define FT_ERRORDEF(e, v, s) case v: i_push_error(code, s); return;
#define FT_ERROR_START_LIST 
#define FT_ERROR_END_LIST 

/*
=back

=head2 Internal Functions

These functions are used in the implementation of freetyp2.c and should not
(usually cannot) be called from outside it.

=over

=item ft2_push_message(int code)

Pushes an error message corresponding to code onto the error stack.

=cut
*/

#define UNKNOWN_ERROR_FORMAT "Unknown Freetype2 error code 0x%04X"

static void
ft2_push_message(int code) {
  char unknown[40];

  switch (code) {
#include FT_ERRORS_H
  }

#ifdef IMAGER_SNPRINTF
  snprintf(unknown, sizeof(unknown), UNKNOWN_ERROR_FORMAT, code);
#else
  sprintf(unknown, UNKNOWN_ERROR_FORMAT, code);
#endif
  i_push_error(code, unknown);
}

/*
=item make_bmp_map(FT_Bitmap *bitmap, unsigned char *map)

Creates a map to convert grey levels from the glyphs bitmap into
values scaled 0..255.

=cut
*/
static int
make_bmp_map(FT_Bitmap *bitmap, unsigned char *map) {
  int scale;
  int i;

  switch (bitmap->pixel_mode) {
  case ft_pixel_mode_grays:
    scale = bitmap->num_grays;
    break;
    
  default:
    i_push_errorf(0, "I can't handle pixel mode %d", bitmap->pixel_mode);
    return 0;
  }

  /* build the table */
  for (i = 0; i < scale; ++i)
    map[i] = i * 255 / (bitmap->num_grays - 1);

  return 1;
}

/* FREETYPE_PATCH was introduced in 2.0.6, we don't want a false 
   positive on 2.0.0 to 2.0.4, so we accept a false negative in 2.0.5 */
#ifndef FREETYPE_PATCH
#define FREETYPE_PATCH 4
#endif

/* FT_Get_Postscript_Name() was introduced in FT2.0.5 */
#define IM_HAS_FACE_NAME (FREETYPE_MINOR > 0 || FREETYPE_PATCH >= 5)
/* #define IM_HAS_FACE_NAME 0 */ 

/*
=item i_ft2_face_name(handle, name_buf, name_buf_size)

Fills the given buffer with the Postscript Face name of the font,
if there is one.

Returns the number of bytes copied, including the terminating NUL.

=cut
*/

size_t
i_ft2_face_name(FT2_Fonthandle *handle, char *name_buf, size_t name_buf_size) {
#if IM_HAS_FACE_NAME
  char const *name = FT_Get_Postscript_Name(handle->face);

  i_clear_error();

  if (name) {
    strncpy(name_buf, name, name_buf_size);
    name_buf[name_buf_size-1] = '\0';

    return strlen(name) + 1;
  }
  else {
    i_push_error(0, "no face name available");
    *name_buf = '\0';

    return 0;
  }
#else
  i_clear_error();
  i_push_error(0, "Freetype 2.0.6 or later required");
  *name_buf = '\0';

  return 0;
#endif
}

int
i_ft2_can_face_name(void) {
  return IM_HAS_FACE_NAME;
}

/* FT_Has_PS_Glyph_Names() was introduced in FT2.1.1 */
/* well, I assume FREETYPE_MAJOR is 2, since we're here */
#if FREETYPE_MINOR < 1 || (FREETYPE_MINOR == 1 && FREETYPE_PATCH < 1)
#define FT_Has_PS_Glyph_Names(face) (FT_HAS_GLYPH_NAMES(face))
#endif

int
i_ft2_glyph_name(FT2_Fonthandle *handle, unsigned long ch, char *name_buf, 
                 size_t name_buf_size, int reliable_only) {
#ifdef FT_CONFIG_OPTION_NO_GLYPH_NAMES
  i_clear_error();
  *name_buf = '\0';
  i_push_error(0, "FT2 configured without glyph name support");

  return 0;
#else
  FT_UInt index;

  i_clear_error();

  if (!FT_HAS_GLYPH_NAMES(handle->face)) {
    i_push_error(0, "no glyph names in font");
    *name_buf = '\0';
    return 0;
  }
  if (reliable_only && !FT_Has_PS_Glyph_Names(handle->face)) {
    i_push_error(0, "no reliable glyph names in font - set reliable_only to 0 to try anyway");
    *name_buf = '\0';
    return 0;
  }

  index = FT_Get_Char_Index(handle->face, ch);
  
  if (index) {
    FT_Error error = FT_Get_Glyph_Name(handle->face, index, name_buf, 
                                       name_buf_size);
    if (error) {
      ft2_push_message(error);
      *name_buf = '\0';
      return 0;
    }
    if (strcmp(name_buf, ".notdef") == 0) {
      *name_buf = 0;
      return 0;
    }
    if (*name_buf) {
      return strlen(name_buf) + 1;
    }
    else {
      return 0;
    }
  }
  else {
    *name_buf = 0;
    return 0;
  }
#endif
}

int
i_ft2_can_do_glyph_names(void) {
#ifdef FT_CONFIG_OPTION_NO_GLYPH_NAMES
  return 0;
#else
  return 1;
#endif
}

int 
i_ft2_face_has_glyph_names(FT2_Fonthandle *handle) {
#ifdef FT_CONFIG_OPTION_NO_GLYPH_NAMES
  return 0;
#else
  return FT_HAS_GLYPH_NAMES(handle->face);
  /* return FT_Has_PS_Glyph_Names(handle->face);*/
#endif
}

int
i_ft2_is_multiple_master(FT2_Fonthandle *handle) {
  i_clear_error();
#ifdef IM_FT2_MM
  return handle->has_mm;
#else
  return 0;
#endif
}

int
i_ft2_get_multiple_masters(FT2_Fonthandle *handle, i_font_mm *mm) {
#ifdef IM_FT2_MM
  int i;
  FT_Multi_Master *mms = &handle->mm;

  i_clear_error();
  if (!handle->has_mm) {
    i_push_error(0, "Font has no multiple masters");
    return 0;
  }
  mm->num_axis = mms->num_axis;
  mm->num_designs = mms->num_designs;
  for (i = 0; i < mms->num_axis; ++i) {
    mm->axis[i].name = mms->axis[i].name;
    mm->axis[i].minimum = mms->axis[i].minimum;
    mm->axis[i].maximum = mms->axis[i].maximum;
  }

  return 1;
#else
  i_clear_error();
  i_push_error(0, "Multiple master functions unavailable");
  return 0;
#endif
}

int
i_ft2_set_mm_coords(FT2_Fonthandle *handle, int coord_count, const long *coords) {
#ifdef IM_FT2_MM
  int i;
  FT_Long ftcoords[T1_MAX_MM_AXIS];
  FT_Error error;

  i_clear_error();
  if (!handle->has_mm) {
    i_push_error(0, "Font has no multiple masters");
    return 0;
  }
  if (coord_count != handle->mm.num_axis) {
    i_push_error(0, "Number of MM coords doesn't match MM axis count");
    return 0;
  }
  for (i = 0; i < coord_count; ++i)
    ftcoords[i] = coords[i];

  error = FT_Set_MM_Design_Coordinates(handle->face, coord_count, ftcoords);
  if (error) {
    ft2_push_message(error);
    return 0;
  }
  
  return 1;
#else 
  i_clear_error();
  i_push_error(0, "Multiple master functions unavailable");

  return 0;
#endif
}

static i_img_dim
i_min(i_img_dim a, i_img_dim b) {
  return a < b ? a : b;
}

static i_img_dim
i_max(i_img_dim a, i_img_dim b) {
  return a > b ? a : b;
}

/*
=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>, with a fair amount of help from
reading the code in font.c.

=head1 SEE ALSO

font.c, Imager::Font(3), Imager(3)

http://www.freetype.org/

=cut
*/

