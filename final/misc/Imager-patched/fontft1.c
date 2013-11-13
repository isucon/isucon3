#include "imager.h"
#include "imrender.h"

#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

#include <stdio.h>
#include <stdlib.h>


/*
=head1 NAME

fontft1.c - Freetype 1.x font driver for Imager

=head1 SYNOPSIS

  handle = i_tt_new(path_to_ttf);
  rc = i_tt_bbox(handle, points, "foo", 3, int cords[6], utf8);
  i_tt_destroy(handle);

  // and much more

=head1 DESCRIPTION

fontft1.c implements font creation, rendering, bounding box functions and
more for Imager using Freetype 1.x.

In general this driver should be ignored in favour of the FT2 driver.

=head1 FUNCTION REFERENCE

Some of these functions are internal.

=over

=cut

*/


/* Truetype font support */
/* These are enabled by default when configuring Freetype 1.x
   I haven't a clue how to reliably detect it at compile time.

   We need a compilation probe in Makefile.PL
*/
#define FTXPOST 1
#define FTXERR18 1

#include <freetype.h>
#define TT_CHC 5

#ifdef FTXPOST
#include <ftxpost.h>
#endif

#ifdef FTXERR18
#include <ftxerr18.h>
#endif

/* some versions of FT1.x don't seem to define this - it's font defined
   so it won't change */
#ifndef TT_MS_LANGID_ENGLISH_GENERAL
#define TT_MS_LANGID_ENGLISH_GENERAL 0x0409
#endif

static im_slot_t slot = -1;

/* convert a code point into an index in the glyph cache */
#define TT_HASH(x) ((x) & 0xFF)

typedef struct {
  int initialized;
  TT_Engine engine;
} i_tt_engine;

typedef struct i_glyph_entry_ {
  TT_Glyph glyph;
  unsigned long ch;
} i_tt_glyph_entry;

#define TT_NOCHAR (~0UL)

struct TT_Instancehandle_ {
  TT_Instance instance;
  TT_Instance_Metrics imetrics;
  TT_Glyph_Metrics gmetrics[256];
  i_tt_glyph_entry glyphs[256];
  int smooth;
  int order;
  i_img_dim ptsize;
};

typedef struct TT_Instancehandle_ TT_Instancehandle;

struct TT_Fonthandle_ {
  TT_Face face;
  TT_Face_Properties properties;
  TT_Instancehandle instanceh[TT_CHC];
  TT_CharMap char_map;
#ifdef FTXPOST
  int loaded_names;
  TT_Error load_cond;
#endif
};

/* Defines */

#define USTRCT(x) ((x).z)
#define TT_VALID( handle )  ( ( handle ).z != NULL )

static void i_tt_push_error(TT_Error rc);
static void i_tt_uninit(void *);

/* Prototypes */

static  int i_tt_get_instance( TT_Fonthandle *handle, i_img_dim points, int smooth );
static void i_tt_init_raster_map( TT_Raster_Map* bit, i_img_dim width, i_img_dim height, int smooth );
static void i_tt_done_raster_map( TT_Raster_Map *bit );
static void i_tt_clear_raster_map( TT_Raster_Map* bit );
static void i_tt_blit_or( TT_Raster_Map *dst, TT_Raster_Map *src,i_img_dim x_off, i_img_dim y_off );
static  int i_tt_get_glyph( TT_Fonthandle *handle, int inst, unsigned long j );
static void 
i_tt_render_glyph( TT_Glyph glyph, TT_Glyph_Metrics* gmetrics, 
                   TT_Raster_Map *bit, TT_Raster_Map *small_bit, 
                   i_img_dim x_off, i_img_dim y_off, int smooth );
static int
i_tt_render_all_glyphs( TT_Fonthandle *handle, int inst, TT_Raster_Map *bit, 
                        TT_Raster_Map *small_bit, i_img_dim cords[6], 
                        char const* txt, size_t len, int smooth, int utf8 );
static void i_tt_dump_raster_map2( i_img* im, TT_Raster_Map* bit, i_img_dim xb, i_img_dim yb, const i_color *cl, int smooth );
static void i_tt_dump_raster_map_channel( i_img* im, TT_Raster_Map* bit, i_img_dim xb, i_img_dim yb, int channel, int smooth );
static  int
i_tt_rasterize( TT_Fonthandle *handle, TT_Raster_Map *bit, i_img_dim cords[6], 
                double points, char const* txt, size_t len, int smooth, int utf8 );
static undef_int i_tt_bbox_inst( TT_Fonthandle *handle, int inst ,const char *txt, size_t len, i_img_dim cords[6], int utf8 );


/* static globals needed */

static int  LTT_dpi    = 72; /* FIXME: this ought to be a part of the call interface */
static int  LTT_hinted = 1;  /* FIXME: this too */


/*
 * FreeType interface
 */

void
i_tt_start(void) {
  if (slot == -1)
    slot = im_context_slot_new(i_tt_uninit);
}


/*
=item init_tt()

Initializes the freetype font rendering engine (if needed)

=cut
*/

static i_tt_engine *
i_init_tt(void) {
  TT_Error  error;
  im_context_t ctx = im_get_context();
  TT_Byte palette[] = { 0, 64, 127, 191, 255 };
  i_tt_engine *result = im_context_slot_get(ctx, slot);

  i_clear_error();

  if (result == NULL) {
    result = mymalloc(sizeof(i_tt_engine));
    memset(result, 0, sizeof(*result));
    im_context_slot_set(ctx, slot, result);
    mm_log((1, "allocated FT1 state %p\n", result));
  }

  mm_log((1,"init_tt()\n"));

  if (result->initialized)
    return result;

  error = TT_Init_FreeType( &result->engine );
  if ( error ){
    mm_log((1,"Initialization of freetype failed, code = 0x%x\n",
	    (unsigned)error));
    i_tt_push_error(error);
    i_push_error(0, "Could not initialize freetype 1.x");
    return NULL;
  }

#ifdef FTXPOST
  error = TT_Init_Post_Extension( result->engine );
  if (error) {
    mm_log((1, "Initialization of Post extension failed = 0x%x\n",
	    (unsigned)error));
    
    i_tt_push_error(error);
    i_push_error(0, "Could not initialize FT 1.x POST extension");
    return NULL;
  }
#endif

  error = TT_Set_Raster_Gray_Palette(result->engine, palette);
  if (error) {
    mm_log((1, "Initialization of gray levels failed = 0x%x\n",
	    (unsigned)error));
    i_tt_push_error(error);
    i_push_error(0, "Could not initialize FT 1.x POST extension");
    return NULL;
  }

  mm_log((1, "initialized FT1 state %p\n", result));

  result->initialized = 1;

  return result;
}

static void
i_tt_uninit(void *p) {
  i_tt_engine *tteng = p;

  if (tteng->initialized) {
    mm_log((1, "finalizing FT1 state %p\n", tteng));
    TT_Done_FreeType(tteng->engine);
  }
  mm_log((1, "freeing FT1 state %p\n", tteng));
  myfree(tteng);
}

/* 
=item i_tt_get_instance(handle, points, smooth)

Finds a points+smooth instance or if one doesn't exist in the cache
allocates room and returns its cache entry

   fontname - path to the font to load
   handle   - handle to the font.
   points   - points of the requested font
   smooth   - boolean (True: antialias on, False: antialias is off)

=cut
*/

static
int
i_tt_get_instance( TT_Fonthandle *handle, i_img_dim points, int smooth ) {
  int i,idx;
  TT_Error error;
  
  mm_log((1,"i_tt_get_instance(handle %p, points %" i_DF ", smooth %d)\n",
          handle, i_DFc(points), smooth));
  
  if (smooth == -1) { /* Smooth doesn't matter for this search */
    for(i=0;i<TT_CHC;i++) {
      if (handle->instanceh[i].ptsize==points) {
        mm_log((1,"i_tt_get_instance: in cache - (non selective smoothing search) returning %d\n",i));
        return i;
      }
    }
    smooth=1; /* We will be adding a font - add it as smooth then */
  } else { /* Smooth doesn't matter for this search */
    for(i=0;i<TT_CHC;i++) {
      if (handle->instanceh[i].ptsize == points 
          && handle->instanceh[i].smooth == smooth) {
        mm_log((1,"i_tt_get_instance: in cache returning %d\n",i));
        return i;
      }
    }
  }
  
  /* Found the instance in the cache - return the cache index */
  
  for(idx=0;idx<TT_CHC;idx++) {
    if (!(handle->instanceh[idx].order)) break; /* find the lru item */
  }

  mm_log((1,"i_tt_get_instance: lru item is %d\n",idx));
  mm_log((1,"i_tt_get_instance: lru pointer %p\n",
          USTRCT(handle->instanceh[idx].instance) ));
  
  if ( USTRCT(handle->instanceh[idx].instance) ) {
    mm_log((1,"i_tt_get_instance: freeing lru item from cache %d\n",idx));

    /* Free cached glyphs */
    for(i=0;i<256;i++)
      if ( USTRCT(handle->instanceh[idx].glyphs[i].glyph) )
	TT_Done_Glyph( handle->instanceh[idx].glyphs[i].glyph );

    for(i=0;i<256;i++) {
      handle->instanceh[idx].glyphs[i].ch = TT_NOCHAR;
      USTRCT(handle->instanceh[idx].glyphs[i].glyph)=NULL;
    }

    /* Free instance if needed */
    TT_Done_Instance( handle->instanceh[idx].instance );
  }
  
  /* create and initialize instance */
  /* FIXME: probably a memory leak on fail */
  
  (void) (( error = TT_New_Instance( handle->face, &handle->instanceh[idx].instance ) ) || 
	  ( error = TT_Set_Instance_Resolutions( handle->instanceh[idx].instance, LTT_dpi, LTT_dpi ) ) ||
	  ( error = TT_Set_Instance_CharSize( handle->instanceh[idx].instance, points*64 ) ) );
  
  if ( error ) {
    mm_log((1, "Could not create and initialize instance: error %x.\n",
	    (unsigned)error ));
    return -1;
  }
  
  /* Now that the instance should the inplace we need to lower all of the
     ru counts and put `this' one with the highest entry */
  
  for(i=0;i<TT_CHC;i++) handle->instanceh[i].order--;

  handle->instanceh[idx].order=TT_CHC-1;
  handle->instanceh[idx].ptsize=points;
  handle->instanceh[idx].smooth=smooth;
  TT_Get_Instance_Metrics( handle->instanceh[idx].instance, &(handle->instanceh[idx].imetrics) );

  /* Zero the memory for the glyph storage so they are not thought as
     cached if they haven't been cached since this new font was loaded */

  for(i=0;i<256;i++) {
    handle->instanceh[idx].glyphs[i].ch = TT_NOCHAR;
    USTRCT(handle->instanceh[idx].glyphs[i].glyph)=NULL;
  }
  
  return idx;
}


/*
=item i_tt_new(fontname)

Creates a new font handle object, finds a character map and initialise the
the font handle's cache

   fontname - path to the font to load

=cut
*/

TT_Fonthandle*
i_tt_new(const char *fontname) {
  TT_Error error;
  TT_Fonthandle *handle;
  unsigned short i,n;
  unsigned short platform,encoding;
  i_tt_engine *tteng;

  if ((tteng = i_init_tt()) == NULL) {
    i_push_error(0, "Could not initialize FT1 engine");
    return NULL;
  }

  i_clear_error();
  
  mm_log((1,"i_tt_new(fontname '%s')\n",fontname));
  
  /* allocate memory for the structure */
  
  handle = mymalloc( sizeof(TT_Fonthandle) ); /* checked 5Nov05 tonyc */

  /* load the typeface */
  error = TT_Open_Face( tteng->engine, fontname, &handle->face );
  if ( error ) {
    if ( error == TT_Err_Could_Not_Open_File ) {
      mm_log((1, "Could not find/open %s.\n", fontname ));
    }
    else {
      mm_log((1, "Error while opening %s, error code = 0x%x.\n",fontname, 
              (unsigned)error )); 
    }
    i_tt_push_error(error);
    return NULL;
  }
  
  TT_Get_Face_Properties( handle->face, &(handle->properties) );

  /* First, look for a Unicode charmap */
  n = handle->properties.num_CharMaps;
  USTRCT( handle->char_map )=NULL; /* Invalidate character map */
  
  for ( i = 0; i < n; i++ ) {
    TT_Get_CharMap_ID( handle->face, i, &platform, &encoding );
    if ( (platform == 3 && encoding == 1 ) 
         || (platform == 0 && encoding == 0 ) ) {
      mm_log((2,"i_tt_new - found char map platform %u encoding %u\n", 
              platform, encoding));
      TT_Get_CharMap( handle->face, i, &(handle->char_map) );
      break;
    }
  }
  if (!USTRCT(handle->char_map) && n != 0) {
    /* just use the first one */
    TT_Get_CharMap( handle->face, 0, &(handle->char_map));
  }

  /* Zero the pointsizes - and ordering */
  
  for(i=0;i<TT_CHC;i++) {
    USTRCT(handle->instanceh[i].instance)=NULL;
    handle->instanceh[i].order=i;
    handle->instanceh[i].ptsize=0;
    handle->instanceh[i].smooth=-1;
  }

#ifdef FTXPOST
  handle->loaded_names = 0;
#endif

  mm_log((1,"i_tt_new <- %p\n",handle));
  return handle;
}



/*
 * raster map management
 */

/* 
=item i_tt_init_raster_map(bit, width, height, smooth)

Allocates internal memory for the bitmap as needed by the parameters (internal)
		 
   bit    - bitmap to allocate into
   width  - width of the bitmap
   height - height of the bitmap
   smooth - boolean (True: antialias on, False: antialias is off)

=cut
*/

static
void
i_tt_init_raster_map( TT_Raster_Map* bit, i_img_dim width, i_img_dim height, int smooth ) {

  mm_log((1,"i_tt_init_raster_map( bit %p, width %" i_DF ", height %" i_DF
	  ", smooth %d)\n", bit, i_DFc(width), i_DFc(height), smooth));
  
  bit->rows  = height;
  bit->width = ( width + 3 ) & -4;
  bit->flow  = TT_Flow_Down;
  
  if ( smooth ) {
    bit->cols  = bit->width;
    bit->size  = bit->rows * bit->width;
  } else {
    bit->cols  = ( bit->width + 7 ) / 8;    /* convert to # of bytes     */
    bit->size  = bit->rows * bit->cols;     /* number of bytes in buffer */
  }

  /* rows can be 0 for some glyphs, for example ' ' */
  if (bit->rows && bit->size / bit->rows != bit->cols) {
    i_fatal(0, "Integer overflow calculating bitmap size (%d, %d)\n",
            bit->width, bit->rows);
  }
  
  mm_log((1,"i_tt_init_raster_map: bit->width %d, bit->cols %d, bit->rows %d, bit->size %ld)\n", bit->width, bit->cols, bit->rows, bit->size ));

  bit->bitmap = (void *) mymalloc( bit->size ); /* checked 6Nov05 tonyc */
  if ( !bit->bitmap ) i_fatal(0,"Not enough memory to allocate bitmap (%d)!\n",bit->size );
}


/*
=item i_tt_clear_raster_map(bit)

Frees the bitmap data and sets pointer to NULL (internal)
		 
   bit - bitmap to free

=cut
*/

static
void
i_tt_done_raster_map( TT_Raster_Map *bit ) {
  myfree( bit->bitmap );
  bit->bitmap = NULL;
}


/*
=item i_tt_clear_raster_map(bit)

Clears the specified bitmap (internal)
		 
   bit - bitmap to zero

=cut
*/


static
void
i_tt_clear_raster_map( TT_Raster_Map*  bit ) {
  memset( bit->bitmap, 0, bit->size );
}


/* 
=item i_tt_blit_or(dst, src, x_off, y_off)

function that blits one raster map into another (internal)
		 
   dst   - destination bitmap
   src   - source bitmap
   x_off - x offset into the destination bitmap
   y_off - y offset into the destination bitmap

=cut
*/

static
void
i_tt_blit_or( TT_Raster_Map *dst, TT_Raster_Map *src,i_img_dim x_off, i_img_dim y_off ) {
  i_img_dim  x,  y;
  i_img_dim  x1, x2, y1, y2;
  unsigned char *s, *d;
  
  x1 = x_off < 0 ? -x_off : 0;
  y1 = y_off < 0 ? -y_off : 0;
  
  x2 = (int)dst->cols - x_off;
  if ( x2 > src->cols ) x2 = src->cols;
  
  y2 = (int)dst->rows - y_off;
  if ( y2 > src->rows ) y2 = src->rows;

  if ( x1 >= x2 ) return;

  /* do the real work now */

  for ( y = y1; y < y2; ++y ) {
    s = ( (unsigned char*)src->bitmap ) + y * src->cols + x1;
    d = ( (unsigned char*)dst->bitmap ) + ( y + y_off ) * dst->cols + x1 + x_off;
    
    for ( x = x1; x < x2; ++x ) {
      if (*s > *d)
	*d = *s;
      d++;
      s++;
    }
  }
}

/* useful for debugging */
#if 0

static void dump_raster_map(FILE *out, TT_Raster_Map *bit ) {
  int x, y;
  fprintf(out, "cols %d rows %d  flow %d\n", bit->cols, bit->rows, bit->flow);
  for (y = 0; y < bit->rows; ++y) {
    fprintf(out, "%2d:", y);
    for (x = 0; x < bit->cols; ++x) {
      if ((x & 7) == 0 && x) putc(' ', out);
      fprintf(out, "%02x", ((unsigned char *)bit->bitmap)[y*bit->cols+x]);
    }
    putc('\n', out);
  }
}

#endif

/* 
=item i_tt_get_glyph(handle, inst, j) 

Function to see if a glyph exists and if so cache it (internal)
		 
   handle - pointer to font handle
   inst   - font instance
   j      - charcode of glyph

=cut
*/

static
int
i_tt_get_glyph( TT_Fonthandle *handle, int inst, unsigned long j) {
  unsigned short load_flags, code;
  TT_Error error;

  mm_log((1, "i_tt_get_glyph(handle %p, inst %d, j %lu (%c))\n",
          handle,inst,j, (int)((j >= ' ' && j <= '~') ? j : '.')));
  
  /*mm_log((1, "handle->instanceh[inst].glyphs[j]=0x%08X\n",handle->instanceh[inst].glyphs[j] ));*/

  if ( TT_VALID(handle->instanceh[inst].glyphs[TT_HASH(j)].glyph)
       && handle->instanceh[inst].glyphs[TT_HASH(j)].ch == j) {
    mm_log((1,"i_tt_get_glyph: %lu in cache\n",j));
    return 1;
  }

  if ( TT_VALID(handle->instanceh[inst].glyphs[TT_HASH(j)].glyph) ) {
    /* clean up the entry */
    TT_Done_Glyph( handle->instanceh[inst].glyphs[TT_HASH(j)].glyph );
    USTRCT( handle->instanceh[inst].glyphs[TT_HASH(j)].glyph ) = NULL;
    handle->instanceh[inst].glyphs[TT_HASH(j)].ch = TT_NOCHAR;
  }
  
  /* Ok - it wasn't cached - try to get it in */
  load_flags = TTLOAD_SCALE_GLYPH;
  if ( LTT_hinted ) load_flags |= TTLOAD_HINT_GLYPH;
  
  if ( !TT_VALID(handle->char_map) ) {
    code = (j - ' ' + 1) < 0 ? 0 : (j - ' ' + 1);
    if ( code >= handle->properties.num_Glyphs ) code = 0;
  } else code = TT_Char_Index( handle->char_map, j );
  
  if ( (error = TT_New_Glyph( handle->face, &handle->instanceh[inst].glyphs[TT_HASH(j)].glyph)) ) {
    mm_log((1, "Cannot allocate and load glyph: error %#x.\n", (unsigned)error ));
    i_push_error(error, "TT_New_Glyph()");
    return 0;
  }
  if ( (error = TT_Load_Glyph( handle->instanceh[inst].instance, handle->instanceh[inst].glyphs[TT_HASH(j)].glyph, code, load_flags)) ) {
    mm_log((1, "Cannot allocate and load glyph: error %#x.\n", (unsigned)error ));
    /* Don't leak */
    TT_Done_Glyph( handle->instanceh[inst].glyphs[TT_HASH(j)].glyph );
    USTRCT( handle->instanceh[inst].glyphs[TT_HASH(j)].glyph ) = NULL;
    i_push_error(error, "TT_Load_Glyph()");
    return 0;
  }

  /* At this point the glyph should be allocated and loaded */
  handle->instanceh[inst].glyphs[TT_HASH(j)].ch = j;

  /* Next get the glyph metrics */
  error = TT_Get_Glyph_Metrics( handle->instanceh[inst].glyphs[TT_HASH(j)].glyph, 
                                &handle->instanceh[inst].gmetrics[TT_HASH(j)] );
  if (error) {
    mm_log((1, "TT_Get_Glyph_Metrics: error %#x.\n", (unsigned)error ));
    TT_Done_Glyph( handle->instanceh[inst].glyphs[TT_HASH(j)].glyph );
    USTRCT( handle->instanceh[inst].glyphs[TT_HASH(j)].glyph ) = NULL;
    handle->instanceh[inst].glyphs[TT_HASH(j)].ch = TT_NOCHAR;
    i_push_error(error, "TT_Get_Glyph_Metrics()");
    return 0;
  }

  return 1;
}

/*
=item i_tt_has_chars(handle, text, len, utf8, out)

Check if the given characters are defined by the font.  Note that len
is the number of bytes, not the number of characters (when utf8 is
non-zero).

Returns the number of characters that were checked.

=cut
*/

size_t
i_tt_has_chars(TT_Fonthandle *handle, char const *text, size_t len, int utf8,
               char *out) {
  size_t count = 0;
  mm_log((1, "i_tt_has_chars(handle %p, text %p, len %ld, utf8 %d)\n", 
          handle, text, (long)len, utf8));

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
    
    if (TT_VALID(handle->char_map)) {
      index = TT_Char_Index(handle->char_map, c);
    }
    else {
      index = (c - ' ' + 1) < 0 ? 0 : (c - ' ' + 1);
      if (index >= handle->properties.num_Glyphs)
        index = 0;
    }
    *out++ = index != 0;
    ++count;
  }

  return count;
}

/* 
=item i_tt_destroy(handle)

Clears the data taken by a font including all cached data such as
pixmaps and glyphs
		 
   handle - pointer to font handle

=cut
*/

void
i_tt_destroy( TT_Fonthandle *handle) {
  TT_Close_Face( handle->face );
  myfree( handle );
  
  /* FIXME: Should these be freed automatically by the library? 

  TT_Done_Instance( instance );
  void
    i_tt_done_glyphs( void ) {
    int  i;

    if ( !glyphs ) return;
    
    for ( i = 0; i < 256; ++i ) TT_Done_Glyph( glyphs[i] );
    free( glyphs );
    
    glyphs = NULL;
  }
  */
}


/*
 * FreeType Rendering functions
 */


/* 
=item i_tt_render_glyph(handle, gmetrics, bit, smallbit, x_off, y_off, smooth)

Renders a single glyph into the bit rastermap (internal)

   handle   - pointer to font handle
   gmetrics - the metrics for the glyph to be rendered
   bit      - large bitmap that is the destination for the text
   smallbit - small bitmap that is used only if smooth is true
   x_off    - x offset of glyph
   y_off    - y offset of glyph
   smooth   - boolean (True: antialias on, False: antialias is off)

=cut
*/

static
void
i_tt_render_glyph( TT_Glyph glyph, TT_Glyph_Metrics* gmetrics, TT_Raster_Map *bit, TT_Raster_Map *small_bit, i_img_dim x_off, i_img_dim y_off, int smooth ) {
  
  mm_log((1,"i_tt_render_glyph(glyph %p, gmetrics %p, bit %p, small_bit %p, x_off %" i_DF ", y_off %" i_DF ", smooth %d)\n",
	  USTRCT(glyph), gmetrics, bit, small_bit, i_DFc(x_off),
	  i_DFc(y_off), smooth));
  
  if ( !smooth ) TT_Get_Glyph_Bitmap( glyph, bit, x_off * 64, y_off * 64);
  else {
    TT_F26Dot6 xmin, ymin;

    xmin =  gmetrics->bbox.xMin & -64;
    ymin =  gmetrics->bbox.yMin & -64;
    
    i_tt_clear_raster_map( small_bit );
    TT_Get_Glyph_Pixmap( glyph, small_bit, -xmin, -ymin );
    i_tt_blit_or( bit, small_bit, xmin/64 + x_off, -ymin/64 - y_off );
  }
}


/*
=item i_tt_render_all_glyphs(handle, inst, bit, small_bit, cords, txt, len, smooth)

calls i_tt_render_glyph to render each glyph into the bit rastermap (internal)

   handle   - pointer to font handle
   inst     - font instance
   bit      - large bitmap that is the destination for the text
   smallbit - small bitmap that is used only if smooth is true
   txt      - string to render
   len      - length of the string to render
   smooth   - boolean (True: antialias on, False: antialias is off)

=cut
*/

static
int
i_tt_render_all_glyphs( TT_Fonthandle *handle, int inst, TT_Raster_Map *bit,
                        TT_Raster_Map *small_bit, i_img_dim cords[6], 
                        char const* txt, size_t len, int smooth, int utf8 ) {
  unsigned long j;
  TT_F26Dot6 x,y;
  
  mm_log((1,"i_tt_render_all_glyphs( handle %p, inst %d, bit %p, small_bit %p, txt '%.*s', len %ld, smooth %d, utf8 %d)\n",
	  handle, inst, bit, small_bit, (int)len, txt, (long)len, smooth, utf8));
  
  /* 
     y=-( handle->properties.horizontal->Descender * handle->instanceh[inst].imetrics.y_ppem )/(handle->properties.header->Units_Per_EM);
  */

  x=-cords[0]; /* FIXME: If you font is antialiased this should be expanded by one to allow for aa expansion and the allocation too - do before passing here */
  y=-cords[4];
  
  while (len) {
    if (utf8) {
      j = i_utf8_advance(&txt, &len);
      if (j == ~0UL) {
        i_push_error(0, "invalid UTF8 character");
        return 0;
      }
    }
    else {
      j = (unsigned char)*txt++;
      --len;
    }
    if ( !i_tt_get_glyph(handle,inst,j) ) 
      continue;
    i_tt_render_glyph( handle->instanceh[inst].glyphs[TT_HASH(j)].glyph, 
                       &handle->instanceh[inst].gmetrics[TT_HASH(j)], bit, 
                       small_bit, x, y, smooth );
    x += handle->instanceh[inst].gmetrics[TT_HASH(j)].advance / 64;
  }

  return 1;
}


/*
 * Functions to render rasters (single channel images) onto images
 */

/* 
=item i_tt_dump_raster_map2(im, bit, xb, yb, cl, smooth)

Function to dump a raster onto an image in color used by i_tt_text() (internal).

   im     - image to dump raster on
   bit    - bitmap that contains the text to be dumped to im
   xb, yb - coordinates, left edge and baseline
   cl     - color to use for text
   smooth - boolean (True: antialias on, False: antialias is off)

=cut
*/

static
void
i_tt_dump_raster_map2( i_img* im, TT_Raster_Map* bit, i_img_dim xb, i_img_dim yb, const i_color *cl, int smooth ) {
  unsigned char *bmap;
  i_img_dim x, y;
  mm_log((1,"i_tt_dump_raster_map2(im %p, bit %p, xb %" i_DF ", yb %" i_DF ", cl %p)\n",
	  im, bit, i_DFc(xb), i_DFc(yb), cl));
  
  bmap = bit->bitmap;

  if ( smooth ) {

    i_render r;
    i_render_init(&r, im, bit->cols);
    for(y=0;y<bit->rows;y++) {
      i_render_color(&r, xb, yb+y, bit->cols, bmap + y*bit->cols, cl);
    }
    i_render_done(&r);
  } else {
    unsigned char *bmp = mymalloc(bit->width);
    i_render r;

    i_render_init(&r, im, bit->width);

    for(y=0;y<bit->rows;y++) {
      unsigned mask = 0x80;
      unsigned char *p = bmap + y * bit->cols;
      unsigned char *pout = bmp;

      for(x = 0; x < bit->width; x++) {
	*pout++ = (*p & mask) ? 0xFF : 0;
	mask >>= 1;
	if (!mask) {
	  mask = 0x80;
	  ++p;
	}
      }

      i_render_color(&r, xb, yb+y, bit->cols, bmp, cl);
    }

    i_render_done(&r);
    myfree(bmp);
  }
}


/*
=item i_tt_dump_raster_map_channel(im, bit, xb, yb, channel, smooth)

Function to dump a raster onto a single channel image in color (internal)

   im      - image to dump raster on
   bit     - bitmap that contains the text to be dumped to im
   xb, yb  - coordinates, left edge and baseline
   channel - channel to copy to
   smooth  - boolean (True: antialias on, False: antialias is off)

=cut
*/

static
void
i_tt_dump_raster_map_channel( i_img* im, TT_Raster_Map*  bit, i_img_dim xb, i_img_dim yb, int channel, int smooth ) {
  unsigned char *bmap;
  i_color val;
  int c;
  i_img_dim x,y;
  int old_mask = im->ch_mask;
  im->ch_mask = 1 << channel;

  mm_log((1,"i_tt_dump_raster_channel(im %p, bit %p, xb %" i_DF ", yb %" i_DF ", channel %d)\n",
	  im, bit, i_DFc(xb), i_DFc(yb), channel));
  
  bmap = bit->bitmap;
  
  if ( smooth ) {
    for(y=0;y<bit->rows;y++) for(x=0;x<bit->width;x++) {
      c = bmap[y*(bit->cols)+x];
      val.channel[channel] = c;
      i_ppix(im,x+xb,y+yb,&val);
    }
  } else {
    for(y=0;y<bit->rows;y++) {
      unsigned mask = 0x80;
      unsigned char *p = bmap + y * bit->cols;

      for(x=0;x<bit->width;x++) {
	val.channel[channel] = (*p & mask) ? 255 : 0;
	i_ppix(im,x+xb,y+yb,&val);
	
	mask >>= 1;
	if (!mask) {
	  ++p;
	  mask = 0x80;
	}
      }
    }
  }
  im->ch_mask = old_mask;
}


/* 
=item i_tt_rasterize(handle, bit, cords, points, txt, len, smooth) 

interface for generating single channel raster of text (internal)

   handle - pointer to font handle
   bit    - the bitmap that is allocated, rendered into and NOT freed
   cords  - the bounding box (modified in place)
   points - font size to use
   txt    - string to render
   len    - length of the string to render
   smooth - boolean (True: antialias on, False: antialias is off)

=cut
*/

static
int
i_tt_rasterize( TT_Fonthandle *handle, TT_Raster_Map *bit, i_img_dim cords[6], double points, char const* txt, size_t len, int smooth, int utf8 ) {
  int inst;
  i_img_dim width, height;
  TT_Raster_Map small_bit;
  
  /* find or install an instance */
  if ( (inst=i_tt_get_instance(handle,points,smooth)) < 0) { 
    mm_log((1,"i_tt_rasterize: get instance failed\n"));
    return 0;
  }
  
  /* calculate bounding box */
  if (!i_tt_bbox_inst( handle, inst, txt, len, cords, utf8 ))
    return 0;
    
  
  width  = cords[2]-cords[0];
  height = cords[5]-cords[4];
  
  mm_log((1,"i_tt_rasterize: width=%" i_DF ", height=%" i_DF "\n",
	  i_DFc(width), i_DFc(height) )); 
  
  i_tt_init_raster_map ( bit, width, height, smooth );
  i_tt_clear_raster_map( bit );
  if ( smooth ) i_tt_init_raster_map( &small_bit, handle->instanceh[inst].imetrics.x_ppem + 32, height, smooth );
  
  if (!i_tt_render_all_glyphs( handle, inst, bit, &small_bit, cords, txt, len, 
                               smooth, utf8 )) {
    if ( smooth ) 
      i_tt_done_raster_map( &small_bit );
    return 0;
  }

  if ( smooth ) i_tt_done_raster_map( &small_bit );
  return 1;
}



/* 
 * Exported text rendering interfaces
 */


/*
=item i_tt_cp(handle, im, xb, yb, channel, points, txt, len, smooth, utf8)

Interface to text rendering into a single channel in an image

   handle  - pointer to font handle
   im      - image to render text on to
   xb, yb  - coordinates, left edge and baseline
   channel - channel to render into
   points  - font size to use
   txt     - string to render
   len     - length of the string to render
   smooth  - boolean (True: antialias on, False: antialias is off)

=cut
*/

undef_int
i_tt_cp( TT_Fonthandle *handle, i_img *im, i_img_dim xb, i_img_dim yb, int channel, double points, char const* txt, size_t len, int smooth, int utf8, int align ) {

  i_img_dim cords[BOUNDING_BOX_COUNT];
  i_img_dim ascent, st_offset, y;
  TT_Raster_Map bit;
  
  i_clear_error();
  if (! i_tt_rasterize( handle, &bit, cords, points, txt, len, smooth, utf8 ) ) return 0;
  
  ascent=cords[BBOX_ASCENT];
  st_offset=cords[BBOX_NEG_WIDTH];
  y = align ? yb-ascent : yb;

  i_tt_dump_raster_map_channel( im, &bit, xb-st_offset , y, channel, smooth );
  i_tt_done_raster_map( &bit );

  return 1;
}


/* 
=item i_tt_text(handle, im, xb, yb, cl, points, txt, len, smooth, utf8) 

Interface to text rendering in a single color onto an image

   handle  - pointer to font handle
   im      - image to render text on to
   xb, yb  - coordinates, left edge and baseline
   cl      - color to use for text
   points  - font size to use
   txt     - string to render
   len     - length of the string to render
   smooth  - boolean (True: antialias on, False: antialias is off)

=cut
*/

undef_int
i_tt_text( TT_Fonthandle *handle, i_img *im, i_img_dim xb, i_img_dim yb, const i_color *cl, double points, char const* txt, size_t len, int smooth, int utf8, int align) {
  i_img_dim cords[BOUNDING_BOX_COUNT];
  i_img_dim ascent, st_offset, y;
  TT_Raster_Map bit;

  i_clear_error();
  
  if (! i_tt_rasterize( handle, &bit, cords, points, txt, len, smooth, utf8 ) ) return 0;
  
  ascent=cords[BBOX_ASCENT];
  st_offset=cords[BBOX_NEG_WIDTH];
  y = align ? yb-ascent : yb;

  i_tt_dump_raster_map2( im, &bit, xb+st_offset, y, cl, smooth ); 
  i_tt_done_raster_map( &bit );

  return 1;
}


/*
=item i_tt_bbox_inst(handle, inst, txt, len, cords, utf8) 

Function to get texts bounding boxes given the instance of the font (internal)

   handle - pointer to font handle
   inst   -  font instance
   txt    -  string to measure
   len    -  length of the string to render
   cords  - the bounding box (modified in place)

=cut
*/

static
undef_int
i_tt_bbox_inst( TT_Fonthandle *handle, int inst ,const char *txt, size_t len, i_img_dim cords[BOUNDING_BOX_COUNT], int utf8 ) {
  int upm, casc, cdesc, first;
  
  int start    = 0;
  i_img_dim width    = 0;
  int gdescent = 0;
  int gascent  = 0;
  int descent  = 0;
  int ascent   = 0;
  int rightb   = 0;

  unsigned long j;

  mm_log((1,"i_tt_box_inst(handle %p,inst %d,txt '%.*s', len %ld, utf8 %d)\n",
	  handle, inst, (int)len, txt, (long)len, utf8));

  upm     = handle->properties.header->Units_Per_EM;
  gascent  = ( handle->properties.horizontal->Ascender  * handle->instanceh[inst].imetrics.y_ppem + upm - 1) / upm;
  gdescent = ( handle->properties.horizontal->Descender * handle->instanceh[inst].imetrics.y_ppem - upm + 1) / upm;
  
  width   = 0;
  start   = 0;
  
  mm_log((1, "i_tt_box_inst: gascent=%d gdescent=%d\n", gascent, gdescent));

  first=1;
  while (len) {
    if (utf8) {
      j = i_utf8_advance(&txt, &len);
      if (j == ~0UL) {
        i_push_error(0, "invalid UTF8 character");
        return 0;
      }
    }
    else {
      j = (unsigned char)*txt++;
      --len;
    }
    if ( i_tt_get_glyph(handle,inst,j) ) {
      TT_Glyph_Metrics *gm = handle->instanceh[inst].gmetrics + TT_HASH(j);
      width += gm->advance   / 64;
      casc   = (gm->bbox.yMax+63) / 64;
      cdesc  = (gm->bbox.yMin-63) / 64;

      mm_log((1, "i_tt_box_inst: glyph='%c' casc=%d cdesc=%d\n", 
              (int)((j >= ' ' && j <= '~') ? j : '.'), casc, cdesc));

      if (first) {
	start    = gm->bbox.xMin / 64;
	ascent   = (gm->bbox.yMax+63) / 64;
	descent  = (gm->bbox.yMin-63) / 64;
	first = 0;
      }
      if (!len) { /* if at end of string */
	/* the right-side bearing - in case the right-side of a 
	   character goes past the right of the advance width,
	   as is common for italic fonts
	*/
	rightb = gm->advance - gm->bearingX 
	  - (gm->bbox.xMax - gm->bbox.xMin);
	/* fprintf(stderr, "font info last: %d %d %d %d\n", 
	   gm->bbox.xMax, gm->bbox.xMin, gm->advance, rightb); */
      }

      ascent  = (ascent  >  casc ?  ascent : casc );
      descent = (descent < cdesc ? descent : cdesc);
    }
  }
  
  cords[BBOX_NEG_WIDTH]=start;
  cords[BBOX_GLOBAL_DESCENT]=gdescent;
  cords[BBOX_POS_WIDTH]=width;
  if (rightb < 0)
    cords[BBOX_POS_WIDTH] -= rightb / 64;
  cords[BBOX_GLOBAL_ASCENT]=gascent;
  cords[BBOX_DESCENT]=descent;
  cords[BBOX_ASCENT]=ascent;
  cords[BBOX_ADVANCE_WIDTH] = width;
  cords[BBOX_RIGHT_BEARING] = rightb / 64;

  return BBOX_RIGHT_BEARING + 1;
}


/*
=item i_tt_bbox(handle, points, txt, len, cords, utf8)

Interface to get a strings bounding box

   handle - pointer to font handle
   points - font size to use
   txt    - string to render
   len    - length of the string to render
   cords  - the bounding box (modified in place)

=cut
*/

undef_int
i_tt_bbox( TT_Fonthandle *handle, double points,const char *txt,size_t len,i_img_dim cords[6], int utf8) {
  int inst;

  i_clear_error();
  mm_log((1,"i_tt_box(handle %p,points %f,txt '%.*s', len %ld, utf8 %d)\n",
	  handle, points, (int)len, txt, (long)len, utf8));

  if ( (inst=i_tt_get_instance(handle,points,-1)) < 0) {
    i_push_errorf(0, "i_tt_get_instance(%g)", points);
    mm_log((1,"i_tt_text: get instance failed\n"));
    return 0;
  }

  return i_tt_bbox_inst(handle, inst, txt, len, cords, utf8);
}

/*
=item i_tt_face_name(handle, name_buf, name_buf_size)

Retrieve's the font's postscript name.

This is complicated by the need to handle encodings and so on.

=cut
 */
size_t
i_tt_face_name(TT_Fonthandle *handle, char *name_buf, size_t name_buf_size) {
  TT_Face_Properties props;
  int name_count;
  int i;
  TT_UShort platform_id, encoding_id, lang_id, name_id;
  TT_UShort name_len;
  TT_String *name;
  int want_index = -1; /* an acceptable but not perfect name */
  int score = 0;

  i_clear_error();
  
  TT_Get_Face_Properties(handle->face, &props);
  name_count = props.num_Names;
  for (i = 0; i < name_count; ++i) {
    TT_Get_Name_ID(handle->face, i, &platform_id, &encoding_id, &lang_id, 
                   &name_id);

    TT_Get_Name_String(handle->face, i, &name, &name_len);

    if (platform_id != TT_PLATFORM_APPLE_UNICODE && name_len
        && name_id == TT_NAME_ID_PS_NAME) {
      int might_want_index = -1;
      int might_score = 0;
      if ((platform_id == TT_PLATFORM_MACINTOSH && encoding_id == TT_MAC_ID_ROMAN)
          ||
          (platform_id == TT_PLATFORM_MICROSOFT && encoding_id == TT_MS_LANGID_ENGLISH_UNITED_STATES)) {
        /* exactly what we want */
        want_index = i;
        break;
      }
      
      if (platform_id == TT_PLATFORM_MICROSOFT
          && (encoding_id & 0xFF) == TT_MS_LANGID_ENGLISH_GENERAL) {
        /* any english is good */
        might_want_index = i;
        might_score = 9;
      }
      /* there might be something in between */
      else {
        /* anything non-unicode is better than nothing */
        might_want_index = i;
        might_score = 1;
      }
      if (might_score > score) {
        score = might_score;
        want_index = might_want_index;
      }
    }
  }

  if (want_index != -1) {
    TT_Get_Name_String(handle->face, want_index, &name, &name_len);
    
    strncpy(name_buf, name, name_buf_size);
    name_buf[name_buf_size-1] = '\0';

    return strlen(name) + 1;
  }
  else {
    i_push_error(0, "no face name present");
    return 0;
  }
}

void i_tt_dump_names(TT_Fonthandle *handle) {
  TT_Face_Properties props;
  int name_count;
  int i;
  TT_UShort platform_id, encoding_id, lang_id, name_id;
  TT_UShort name_len;
  TT_String *name;
  
  TT_Get_Face_Properties(handle->face, &props);
  name_count = props.num_Names;
  for (i = 0; i < name_count; ++i) {
    TT_Get_Name_ID(handle->face, i, &platform_id, &encoding_id, &lang_id, 
                   &name_id);
    TT_Get_Name_String(handle->face, i, &name, &name_len);

    printf("# %d: plat %d enc %d lang %d name %d value ", i, platform_id,
           encoding_id, lang_id, name_id);
    if (platform_id == TT_PLATFORM_APPLE_UNICODE) {
      printf("(unicode)\n");
    }
    else {
      printf("'%s'\n", name);
    }
  }
  fflush(stdout);
}

size_t
i_tt_glyph_name(TT_Fonthandle *handle, unsigned long ch, char *name_buf, 
                 size_t name_buf_size) {
#ifdef FTXPOST
  TT_Error rc;
  TT_String *psname;
  TT_UShort index;

  i_clear_error();

  if (!handle->loaded_names) {
    TT_Post post;
    mm_log((1, "Loading PS Names"));
    handle->load_cond = TT_Load_PS_Names(handle->face, &post);
    ++handle->loaded_names;
  }

  if (handle->load_cond) {
    i_push_errorf(handle->load_cond, "error loading names (%#x)",
		  (unsigned)handle->load_cond);
    return 0;
  }
  
  index = TT_Char_Index(handle->char_map, ch);
  if (!index) {
    i_push_error(0, "no such character");
    return 0;
  }

  rc = TT_Get_PS_Name(handle->face, index, &psname);

  if (rc) {
    i_push_error(rc, "error getting name");
    return 0;
  }

  strncpy(name_buf, psname, name_buf_size);
  name_buf[name_buf_size-1] = '\0';

  return strlen(psname) + 1;
#else
  mm_log((1, "FTXPOST extension not enabled\n"));
  i_clear_error();
  i_push_error(0, "Use of FTXPOST extension disabled");

  return 0;
#endif
}

/*
=item i_tt_push_error(code)

Push an error message and code onto the Imager error stack.

=cut
*/
static void
i_tt_push_error(TT_Error rc) {
#ifdef FTXERR18
  TT_String const *msg = TT_ErrToString18(rc);

  i_push_error(rc, msg);
#else
  i_push_errorf(rc, "Error code 0x%04x", (unsigned)rc);
#endif
}


/*
=back

=head1 AUTHOR

Arnar M. Hrafnkelsson <addi@umich.edu>

=head1 SEE ALSO

Imager(3)

=cut
*/
