#include "imext.h"
#include "imt1.h"
#include <t1lib.h>
#include <string.h>

static int t1_get_flags(char const *flags);
static char *t1_from_utf8(char const *in, size_t len, int *outlen);
static undef_int i_init_t1_low(int t1log);
static void t1_push_error(void);
static void i_t1_set_aa(int st);

static int t1_active_fonts = 0;
static int t1_initialized = 0;
static int t1_aa = 0;

struct i_t1_font_tag {
  int font_id;
};

static i_mutex_t mutex;

/*
=item i_t1_start()

Initialize the font driver.  This does not actually initialize T1Lib,
it just allocates the mutex we use to gate access to it.

=cut
*/

void
i_t1_start(void) {
  mutex = i_mutex_new();
}

/* 
=item i_init_t1(t1log)

Initializes the t1lib font rendering engine.

=cut
*/

undef_int
i_init_t1(int t1log) {
  undef_int result;
  i_mutex_lock(mutex);

  result = i_init_t1_low(t1log);

  i_mutex_unlock(mutex);

  return result;
}

static undef_int
i_init_t1_low(int t1log) {
  int init_flags = IGNORE_CONFIGFILE|IGNORE_FONTDATABASE;

  mm_log((1,"init_t1(%d)\n", t1log));

  i_clear_error();

  if (t1_active_fonts) {
    mm_log((1, "Cannot re-initialize T1 - active fonts\n"));
    i_push_error(0, "Cannot re-initialize T1 - active fonts");
    return 1;
  }

  if (t1_initialized) {
    T1_CloseLib();
    t1_initialized = 0;
  }
  
  if (t1log)
    init_flags |= LOGFILE;
  if ((T1_InitLib(init_flags) == NULL)){
    mm_log((1,"Initialization of t1lib failed\n"));
    i_push_error(0, "T1_InitLib failed");
    return(1);
  }
  T1_SetLogLevel(T1LOG_DEBUG);

  ++t1_initialized;

  return(0);
}

/* 
=item i_close_t1()

Shuts the t1lib font rendering engine down.

  This it seems that this function is never used.

=cut
*/

void
i_close_t1(void) {
  i_mutex_lock(mutex);
  T1_CloseLib();
  t1_initialized = 0;
  i_mutex_unlock(mutex);
}


/*
=item i_t1_new(pfb, afm)

Loads the fonts with the given filenames, returns its font id

 pfb -  path to pfb file for font
 afm -  path to afm file for font

=cut
*/

i_t1_font_t
i_t1_new(char *pfb,char *afm) {
  int font_id;
  i_t1_font_t font;

  i_mutex_lock(mutex);

  i_clear_error();

  if (!t1_initialized && i_init_t1_low(0)) {
    i_mutex_unlock(mutex);
    return NULL;
  }

  mm_log((1,"i_t1_new(pfb %s,afm %s)\n",pfb,(afm?afm:"NULL")));
  font_id = T1_AddFont(pfb);
  if (font_id<0) {
    mm_log((1,"i_t1_new: Failed to load pfb file '%s' - return code %d.\n",pfb,font_id));
    t1_push_error();
    i_mutex_unlock(mutex);
    return NULL;
  }
  
  if (afm != NULL) {
    mm_log((1,"i_t1_new: requesting afm file '%s'.\n",afm));
    if (T1_SetAfmFileName(font_id,afm)<0) mm_log((1,"i_t1_new: afm loading of '%s' failed.\n",afm));
  }

  if (T1_LoadFont(font_id)) {
    mm_log((1, "i_t1_new() -> -1 - T1_LoadFont failed (%d)\n", T1_errno));
    t1_push_error();
    i_push_error(0, "loading font");
    T1_DeleteFont(font_id);
    i_mutex_unlock(mutex);
    return NULL;
  }

  ++t1_active_fonts;

  i_mutex_unlock(mutex);

  font = mymalloc(sizeof(*font));
  font->font_id = font_id;

  mm_log((1, "i_t1_new() -> %p (%d)\n", font, font_id));

  return font;
}

/*
=item i_t1_destroy(font)

Frees resources for a t1 font with given font id.

   font - font to free

=cut
*/

int
i_t1_destroy(i_t1_font_t font) {
  int result;

  i_mutex_lock(mutex);

  mm_log((1,"i_t1_destroy(font %p (%d))\n", font, font->font_id));

  --t1_active_fonts;

  result = T1_DeleteFont(font->font_id);
  myfree(font);

  i_mutex_unlock(mutex);

  return result;
}


/*
=item i_t1_set_aa(st)

Sets the antialiasing level of the t1 library.

   st - 0 =  NONE, 1 = LOW, 2 =  HIGH.

Must be called with the mutex locked.

=cut
*/

static void
i_t1_set_aa(int st) {
  int i;
  unsigned long cst[17];

  if (t1_aa == st)
    return;

  switch(st) {
  case 0:
    T1_AASetBitsPerPixel( 8 );
    T1_AASetLevel( T1_AA_NONE );
    T1_AANSetGrayValues( 0, 255 );
    mm_log((1,"setting T1 antialias to none\n"));
    break;
  case 1:
    T1_AASetBitsPerPixel( 8 );
    T1_AASetLevel( T1_AA_LOW );
    T1_AASetGrayValues( 0,65,127,191,255 );
    mm_log((1,"setting T1 antialias to low\n"));
    break;
  case 2:
    T1_AASetBitsPerPixel(8);
    T1_AASetLevel(T1_AA_HIGH);
    for(i=0;i<17;i++) cst[i]=(i*255)/16;
    T1_AAHSetGrayValues( cst );
    mm_log((1,"setting T1 antialias to high\n"));
  }
  
  t1_aa = st;
}


/* 
=item i_t1_cp(im, xb, yb, channel, fontnum, points, str, len, align,aa)

Interface to text rendering into a single channel in an image

   im        pointer to image structure
   xb        x coordinate of start of string
   yb        y coordinate of start of string ( see align )
   channel - destination channel
   fontnum - t1 library font id
   points  - number of points in fontheight
   str     - string to render
   len     - string length
   align   - (0 - top of font glyph | 1 - baseline )
   aa      - anti-aliasing level

=cut
*/

undef_int
i_t1_cp(i_t1_font_t font, i_img *im,i_img_dim xb,i_img_dim yb,int channel,double points,char* str,size_t len,int align, int utf8, char const *flags, int aa) {
  GLYPH *glyph;
  int xsize,ysize,x,y;
  i_color val;
  int mod_flags = t1_get_flags(flags);
  int fontnum = font->font_id;

  unsigned int ch_mask_store;
  
  i_clear_error();

  mm_log((1, "i_t1_cp(font %p (%d), im %p, (xb,yb)=" i_DFp ", channel %d, points %g, str %p, len %u, align %d, utf8 %d, flags '%s', aa %d)\n",
	  font, fontnum, im, i_DFcp(xb, yb), channel, points, str, (unsigned)len, align, utf8, flags, aa));

  if (im == NULL) {
    mm_log((1,"i_t1_cp: Null image in input\n"));
    i_push_error(0, "null image");
    return(0);
  }

  i_mutex_lock(mutex);

  i_t1_set_aa(aa);

  if (utf8) {
    int worklen;
    char *work = t1_from_utf8(str, len, &worklen);
    if (work == NULL) {
      i_mutex_unlock(mutex);
      return 0;
    }
    glyph=T1_AASetString( fontnum, work, worklen, 0, mod_flags, points, NULL);
    myfree(work);
  }
  else {
    glyph=T1_AASetString( fontnum, str, len, 0, mod_flags, points, NULL);
  }
  if (glyph == NULL) {
    t1_push_error();
    i_push_error(0, "i_t1_cp: T1_AASetString failed");
    i_mutex_unlock(mutex);
    return 0;
  }

  mm_log((1,"metrics: ascent: %d descent: %d\n",glyph->metrics.ascent,glyph->metrics.descent));
  mm_log((1," leftSideBearing: %d rightSideBearing: %d\n",glyph->metrics.leftSideBearing,glyph->metrics.rightSideBearing));
  mm_log((1," advanceX: %d  advanceY: %d\n",glyph->metrics.advanceX,glyph->metrics.advanceY));
  mm_log((1,"bpp: %lu\n", (unsigned long)glyph->bpp));
  
  xsize=glyph->metrics.rightSideBearing-glyph->metrics.leftSideBearing;
  ysize=glyph->metrics.ascent-glyph->metrics.descent;
  
  mm_log((1,"width: %d height: %d\n",xsize,ysize));

  ch_mask_store=im->ch_mask;
  im->ch_mask=1<<channel;

  if (align==1) { xb+=glyph->metrics.leftSideBearing; yb-=glyph->metrics.ascent; }
  
  for(y=0;y<ysize;y++) for(x=0;x<xsize;x++) {
    val.channel[channel]=glyph->bits[y*xsize+x];
    i_ppix(im,x+xb,y+yb,&val);
  }
  
  im->ch_mask=ch_mask_store;

  i_mutex_unlock(mutex);

  return 1;
}

static void
t1_fix_bbox(BBox *bbox, const char *str, size_t len, int advance, 
	    int space_position) {
  /* never called with len == 0 */
  if (str[0] == space_position && bbox->llx > 0)
    bbox->llx = 0;
  if (str[len-1] == space_position && bbox->urx < advance)
    bbox->urx = advance;
  if (bbox->lly > bbox->ury)
    bbox->lly = bbox->ury = 0; 
}

/*
=item i_t1_bbox(handle, fontnum, points, str, len, cords)

function to get a strings bounding box given the font id and sizes

   handle  - pointer to font handle   
   fontnum - t1 library font id
   points  - number of points in fontheight
   str     - string to measure
   len     - string length
   cords   - the bounding box (modified in place)

=cut
*/

int
i_t1_bbox(i_t1_font_t font, double points,const char *str,size_t len, i_img_dim cords[6], int utf8,char const *flags) {
  BBox bbox;
  BBox gbbox;
  int mod_flags = t1_get_flags(flags);
  i_img_dim advance;
  int fontnum = font->font_id;
  int space_position;

  i_clear_error();

  i_mutex_lock(mutex);

  space_position = T1_GetEncodingIndex(fontnum, "space");
  
  mm_log((1,"i_t1_bbox(font %p (%d),points %.2f,str '%.*s', len %u)\n",
	  font, fontnum,points,(int)len,str,(unsigned)len));
  if (T1_LoadFont(fontnum) == -1) {
    t1_push_error();
    i_mutex_unlock(mutex);
    return 0;
  }

  if (len == 0) {
    /* len == 0 has special meaning to T1lib, but it means there's
       nothing to draw, so return that */
    bbox.llx = bbox.lly = bbox.urx = bbox.ury = 0;
    advance = 0;
  }
  else {
    if (utf8) {
      int worklen;
      char *work = t1_from_utf8(str, len, &worklen);
      if (!work) {
	i_mutex_unlock(mutex);
	return 0;
      }
      advance = T1_GetStringWidth(fontnum, work, worklen, 0, mod_flags);
      bbox = T1_GetStringBBox(fontnum,work,worklen,0,mod_flags);
      t1_fix_bbox(&bbox, work, worklen, advance, space_position);
      myfree(work);
    }
    else {
      advance = T1_GetStringWidth(fontnum, (char *)str, len, 0, mod_flags);
      bbox = T1_GetStringBBox(fontnum,(char *)str,len,0,mod_flags);
      t1_fix_bbox(&bbox, str, len, advance, space_position);
    }
  }
  gbbox = T1_GetFontBBox(fontnum);
  
  mm_log((1,"bbox: (%d, %d, %d, %d, %d, %d)\n",
	  (int)(bbox.llx*points/1000),
	  (int)(gbbox.lly*points/1000),
	  (int)(bbox.urx*points/1000),
	  (int)(gbbox.ury*points/1000),
	  (int)(bbox.lly*points/1000),
	  (int)(bbox.ury*points/1000) ));


  cords[BBOX_NEG_WIDTH]=((double)bbox.llx*points)/1000;
  cords[BBOX_POS_WIDTH]=((double)bbox.urx*points)/1000;

  cords[BBOX_GLOBAL_DESCENT]=((double)gbbox.lly*points)/1000;
  cords[BBOX_GLOBAL_ASCENT]=((double)gbbox.ury*points)/1000;

  cords[BBOX_DESCENT]=((double)bbox.lly*points)/1000;
  cords[BBOX_ASCENT]=((double)bbox.ury*points)/1000;

  cords[BBOX_ADVANCE_WIDTH] = ((double)advance * points)/1000;
  cords[BBOX_RIGHT_BEARING] = 
    cords[BBOX_ADVANCE_WIDTH] - cords[BBOX_POS_WIDTH];

  i_mutex_unlock(mutex);

  return BBOX_RIGHT_BEARING+1;
}


/*
=item i_t1_text(im, xb, yb, cl, fontnum, points, str, len, align, utf8, flags, aa)

Interface to text rendering in a single color onto an image

   im      - pointer to image structure
   xb      - x coordinate of start of string
   yb      - y coordinate of start of string ( see align )
   cl      - color to draw the text in
   fontnum - t1 library font id
   points  - number of points in fontheight
   str     - char pointer to string to render
   len     - string length
   align   - (0 - top of font glyph | 1 - baseline )
   utf8    - str is utf8
   flags   - formatting flags
   aa      - anti-aliasing level

=cut
*/

undef_int
i_t1_text(i_t1_font_t font, i_img *im, i_img_dim xb, i_img_dim yb,const i_color *cl, double points,const char* str,size_t len,int align, int utf8, char const *flags, int aa) {
  GLYPH *glyph;
  int xsize,ysize,y;
  int mod_flags = t1_get_flags(flags);
  i_render *r;
  int fontnum = font->font_id;

  mm_log((1, "i_t1_text(font %p (%d), im %p, (xb,yb)=" i_DFp ", cl (%d,%d,%d,%d), points %g, str %p, len %u, align %d, utf8 %d, flags '%s', aa %d)\n",
	  font, fontnum, im, i_DFcp(xb, yb), cl->rgba.r, cl->rgba.g, cl->rgba.b, cl->rgba.a, points, str, (unsigned)len, align, utf8, flags, aa));

  i_clear_error();

  if (im == NULL) {
    i_push_error(0, "null image");
    mm_log((1,"i_t1_text: Null image in input\n"));
    return(0);
  }

  i_mutex_lock(mutex);

  i_t1_set_aa(aa);

  if (utf8) {
    int worklen;
    char *work = t1_from_utf8(str, len, &worklen);
    if (!work) {
      i_mutex_unlock(mutex);
      return 0;
    }
    glyph=T1_AASetString( fontnum, work, worklen, 0, mod_flags, points, NULL);
    myfree(work);
  }
  else {
    /* T1_AASetString() accepts a char * not a const char */
    glyph=T1_AASetString( fontnum, (char *)str, len, 0, mod_flags, points, NULL);
  }
  if (glyph == NULL) {
    mm_log((1, "T1_AASetString failed\n"));
    t1_push_error();
    i_push_error(0, "i_t1_text(): T1_AASetString failed");
    i_mutex_unlock(mutex);
    return 0;
  }

  mm_log((1,"metrics:  ascent: %d descent: %d\n",glyph->metrics.ascent,glyph->metrics.descent));
  mm_log((1," leftSideBearing: %d rightSideBearing: %d\n",glyph->metrics.leftSideBearing,glyph->metrics.rightSideBearing));
  mm_log((1," advanceX: %d advanceY: %d\n",glyph->metrics.advanceX,glyph->metrics.advanceY));
  mm_log((1,"bpp: %lu\n",(unsigned long)glyph->bpp));
  
  xsize=glyph->metrics.rightSideBearing-glyph->metrics.leftSideBearing;
  ysize=glyph->metrics.ascent-glyph->metrics.descent;
  
  mm_log((1,"width: %d height: %d\n",xsize,ysize));

  if (align==1) { xb+=glyph->metrics.leftSideBearing; yb-=glyph->metrics.ascent; }

  r = i_render_new(im, xsize);
  for(y=0;y<ysize;y++) {
    i_render_color(r, xb, yb+y, xsize, (unsigned char *)glyph->bits+y*xsize, cl);
  }
  i_render_delete(r);

  i_mutex_unlock(mutex);
    
  return 1;
}

/*
=item t1_get_flags(flags)

Processes the characters in I<flags> to create a mod_flags value used
by some T1Lib functions.

=cut
 */
static int
t1_get_flags(char const *flags) {
  int mod_flags = T1_KERNING;

  while (*flags) {
    switch (*flags++) {
    case 'u': case 'U': mod_flags |= T1_UNDERLINE; break;
    case 'o': case 'O': mod_flags |= T1_OVERLINE; break;
    case 's': case 'S': mod_flags |= T1_OVERSTRIKE; break;
      /* ignore anything we don't recognize */
    }
  }

  return mod_flags;
}

/*
=item t1_from_utf8(char const *in, size_t len, int *outlen)

Produces an unencoded version of I<in> by dropping any Unicode
character over 255.

Returns a newly allocated buffer which should be freed with myfree().
Sets *outlen to the number of bytes used in the output string.

=cut
*/

static char *
t1_from_utf8(char const *in, size_t len, int *outlen) {
  /* at this point len is from a STRLEN which should be size_t and can't
     be too big for mymalloc */
  char *out = mymalloc(len+1); /* rechecked 29jul11 tonyc */
  char *p = out;
  unsigned long c;

  while (len) {
    c = i_utf8_advance(&in, &len);
    if (c == ~0UL) {
      myfree(out);
      i_push_error(0, "invalid UTF8 character");
      return 0;
    }
    /* yeah, just drop them */
    if (c < 0x100) {
      *p++ = (char)c;
    }
  }
  *p = '\0';
  *outlen = p - out;

  return out;
}

/*
=item i_t1_has_chars(font_num, text, len, utf8, out)

Check if the given characters are defined by the font.  Note that len
is the number of bytes, not the number of characters (when utf8 is
non-zero).

out[char index] will be true if the character exists.

Accepts UTF-8, but since T1 can only have 256 characters, any chars
with values over 255 will simply be returned as false.

Returns the number of characters that were checked.

=cut
*/

int
i_t1_has_chars(i_t1_font_t font, const char *text, size_t len, int utf8,
               char *out) {
  int count = 0;
  int font_num = font->font_id;
  
  i_mutex_lock(mutex);

  mm_log((1, "i_t1_has_chars(font_num %d, text %p, len %u, utf8 %d)\n", 
          font_num, text, (unsigned)len, utf8));

  i_clear_error();
  if (T1_LoadFont(font_num)) {
    t1_push_error();
    i_mutex_unlock(mutex);
    return 0;
  }

  while (len) {
    unsigned long c;
    if (utf8) {
      c = i_utf8_advance(&text, &len);
      if (c == ~0UL) {
        i_push_error(0, "invalid UTF8 character");
	i_mutex_unlock(mutex);
        return 0;
      }
    }
    else {
      c = (unsigned char)*text++;
      --len;
    }
    
    if (c >= 0x100) {
      /* limit of 256 characters for T1 */
      *out++ = 0;
    }
    else {
      char const * name = T1_GetCharName(font_num, (unsigned char)c);

      if (name) {
        *out++ = strcmp(name, ".notdef") != 0;
      }
      else {
        mm_log((2, "  No name found for character %lx\n", c));
        *out++ = 0;
      }
    }
    ++count;
  }

  i_mutex_unlock(mutex);

  return count;
}

/*
=item i_t1_face_name(font, name_buf, name_buf_size)

Copies the face name of the given C<font_num> to C<name_buf>.  Returns
the number of characters required to store the name (which can be
larger than C<name_buf_size>, including the space required to store
the terminating NUL).

If name_buf is too small (as specified by name_buf_size) then the name
will be truncated.  name_buf will always be NUL termintaed.

=cut
*/

int
i_t1_face_name(i_t1_font_t font, char *name_buf, size_t name_buf_size) {
  char *name;
  int font_num = font->font_id;

  i_mutex_lock(mutex);

  T1_errno = 0;
  if (T1_LoadFont(font_num)) {
    t1_push_error();
    i_mutex_unlock(mutex);
    return 0;
  }
  name = T1_GetFontName(font_num);

  if (name) {
    size_t len = strlen(name);
    strncpy(name_buf, name, name_buf_size);
    name_buf[name_buf_size-1] = '\0';
    i_mutex_unlock(mutex);
    return len + 1;
  }
  else {
    t1_push_error();
    i_mutex_unlock(mutex);
    return 0;
  }
}

int
i_t1_glyph_name(i_t1_font_t font, unsigned long ch, char *name_buf, 
                 size_t name_buf_size) {
  char *name;
  int font_num = font->font_id;

  i_clear_error();
  if (ch > 0xFF) {
    return 0;
  }

  i_mutex_lock(mutex);

  if (T1_LoadFont(font_num)) {
    t1_push_error();
    i_mutex_unlock(mutex);
    return 0;
  }
  name = T1_GetCharName(font_num, (unsigned char)ch);
  if (name) {
    if (strcmp(name, ".notdef")) {
      size_t len = strlen(name);
      strncpy(name_buf, name, name_buf_size);
      name_buf[name_buf_size-1] = '\0';
      i_mutex_unlock(mutex);
      return len + 1;
    }
    else {
      i_mutex_unlock(mutex);
      return 0;
    }
  }
  else {
    t1_push_error();
    i_mutex_unlock(mutex);
    return 0;
  }
}

static void
t1_push_error(void) {
#if T1LIB_VERSION > 5 || T1LIB_VERSION == 5 && T1LIB_VERSION >= 1
  /* I don't know when T1_StrError() was introduced, be conservative */
  i_push_error(T1_errno, T1_StrError(T1_errno));
#else
  switch (T1_errno) {
  case 0: 
    i_push_error(0, "No error"); 
    break;

#ifdef T1ERR_SCAN_FONT_FORMAT
  case T1ERR_SCAN_FONT_FORMAT:
    i_push_error(T1ERR_SCAN_FONT_FORMAT, "Attempt to Load Multiple Master Font"); 
    break;
#endif

#ifdef T1ERR_SCAN_FILE_OPEN_ERR
  case T1ERR_SCAN_FILE_OPEN_ERR:
    i_push_error(T1ERR_SCAN_FILE_OPEN_ERR, "Type 1 Font File Open Error"); 
    break;
#endif

#ifdef T1ERR_SCAN_OUT_OF_MEMORY
  case T1ERR_SCAN_OUT_OF_MEMORY:
    i_push_error(T1ERR_SCAN_OUT_OF_MEMORY, "Virtual Memory Exceeded"); 
    break;
#endif

#ifdef T1ERR_SCAN_ERROR
  case T1ERR_SCAN_ERROR:
    i_push_error(T1ERR_SCAN_ERROR, "Syntactical Error Scanning Font File"); 
    break;
#endif

#ifdef T1ERR_SCAN_FILE_EOF
  case T1ERR_SCAN_FILE_EOF:
    i_push_error(T1ERR_SCAN_FILE_EOF, "Premature End of Font File Encountered"); 
    break;
#endif

#ifdef T1ERR_PATH_ERROR
  case T1ERR_PATH_ERROR:
    i_push_error(T1ERR_PATH_ERROR, "Path Construction Error"); 
    break;
#endif

#ifdef T1ERR_PARSE_ERROR
  case T1ERR_PARSE_ERROR:
    i_push_error(T1ERR_PARSE_ERROR, "Font is Corrupt"); 
    break;
#endif

#ifdef T1ERR_TYPE1_ABORT
  case T1ERR_TYPE1_ABORT:
    i_push_error(T1ERR_TYPE1_ABORT, "Rasterization Aborted"); 
    break;
#endif

#ifdef T1ERR_INVALID_FONTID
  case T1ERR_INVALID_FONTID:
    i_push_error(T1ERR_INVALID_FONTID, "Font ID Invalid in this Context"); 
    break;
#endif

#ifdef T1ERR_INVALID_PARAMETER
  case T1ERR_INVALID_PARAMETER:
    i_push_error(T1ERR_INVALID_PARAMETER, "Invalid Argument in Function Call"); 
    break;
#endif

#ifdef T1ERR_OP_NOT_PERMITTED
  case T1ERR_OP_NOT_PERMITTED:
    i_push_error(T1ERR_OP_NOT_PERMITTED, "Operation not Permitted"); 
    break;
#endif

#ifdef T1ERR_ALLOC_MEM
  case T1ERR_ALLOC_MEM:
    i_push_error(T1ERR_ALLOC_MEM, "Memory Allocation Error"); 
    break;
#endif

#ifdef T1ERR_FILE_OPEN_ERR
  case T1ERR_FILE_OPEN_ERR:
    i_push_error(T1ERR_FILE_OPEN_ERR, "Error Opening File"); 
    break;
#endif

#ifdef T1ERR_UNSPECIFIED
  case T1ERR_UNSPECIFIED:
    i_push_error(T1ERR_UNSPECIFIED, "Unspecified T1Lib Error"); 
    break;
#endif

#ifdef T1ERR_NO_AFM_DATA
  case T1ERR_NO_AFM_DATA:
    i_push_error(T1ERR_NO_AFM_DATA, "Missing AFM Data"); 
    break;
#endif

#ifdef T1ERR_X11
  case T1ERR_X11:
    i_push_error(T1ERR_X11, "X11 Interface Error"); 
    break;
#endif

#ifdef T1ERR_COMPOSITE_CHAR
  case T1ERR_COMPOSITE_CHAR:
    i_push_error(T1ERR_COMPOSITE_CHAR, "Missing Component of Composite Character"); 
    break;
#endif

#ifdef T1ERR_SCAN_ENCODING
  case T1ERR_SCAN_ENCODING:
    i_push_error(T1ERR_SCAN_ENCODING, "Error Scanning Encoding File"); 
    break;
#endif

  default:
    i_push_errorf(T1_errno, "unknown error %d", (int)T1_errno);
  }
#endif
}

