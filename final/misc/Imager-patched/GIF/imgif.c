#include "imgif.h"
#include <gif_lib.h>
#ifdef _MSC_VER
#include <io.h>
#else
#include <unistd.h>
#endif
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

/*
=head1 NAME

imgif.c - read and write gif files for Imager

=head1 SYNOPSIS

  i_img *img;
  i_img *imgs[count];
  int fd;
  int *colour_table,
  int colours;
  int max_colours; // number of bits per colour
  int pixdev;  // how much noise to add 
  i_color fixed[N]; // fixed palette entries 
  int fixedlen; // number of fixed colours 
  int success; // non-zero on success
  char *data; // a GIF file in memory
  int length; // how big data is 
  int reader(char *, char *, int, int);
  int writer(char *, char *, int);
  char *userdata; // user's data, whatever it is
  i_quantize quant;
  i_gif_opts opts;

  img = i_readgif(fd, &colour_table, &colours);
  success = i_writegif(img, fd, max_colours, pixdev, fixedlen, fixed);
  success = i_writegifmc(img, fd, max_colours);
  img = i_readgif_scalar(data, length, &colour_table, &colours);
  img = i_readgif_callback(cb, userdata, &colour_table, &colours);
  success = i_writegif_gen(&quant, fd, imgs, count, &opts);
  success = i_writegif_callback(&quant, writer, userdata, maxlength, 
                                imgs, count, &opts);

=head1 DESCRIPTION

This source file provides the C level interface to reading and writing
GIF files for Imager.

This has been tested with giflib 3 and 4, though you lose the callback
functionality with giflib3.

=head1 REFERENCE

=over

=cut
*/

#if defined(GIFLIB_MAJOR) && GIFLIB_MAJOR >= 5
#define POST_SET_VERSION
#define myDGifOpen(userPtr, readFunc, Error) DGifOpen((userPtr), (readFunc), (Error))
#define myEGifOpen(userPtr, readFunc, Error) EGifOpen((userPtr), (readFunc), (Error))
#define myGifError(gif) ((gif)->Error)
#define MakeMapObject GifMakeMapObject
#define FreeMapObject GifFreeMapObject
#define gif_mutex_lock(mutex)
#define gif_mutex_unlock(mutex)
#else
#define PRE_SET_VERSION
static GifFileType *
myDGifOpen(void *userPtr, InputFunc readFunc, int *error) {
  GifFileType *result = DGifOpen(userPtr, readFunc);
  if (!result)
    *error = GifLastError();

  return result;
}
static GifFileType *
myEGifOpen(void *userPtr, OutputFunc outputFunc, int *error) {
  GifFileType *result = EGifOpen(userPtr, outputFunc);
  if (!result)
    *error = GifLastError();

  return result;
}
#define myGifError(gif) GifLastError()
#define gif_mutex_lock(mutex) i_mutex_lock(mutex)
#define gif_mutex_unlock(mutex) i_mutex_unlock(mutex)

#endif

static char const *gif_error_msg(int code);
static void gif_push_error(int code);

/* Make some variables global, so we could access them faster: */

static const int
  InterlacedOffset[] = { 0, 4, 2, 1 }, /* The way Interlaced image should. */
  InterlacedJumps[] = { 8, 8, 4, 2 };    /* be read - offsets and jumps... */

#if !defined(GIFLIB_MAJOR) || GIFLIB_MAJOR < 5
static i_mutex_t mutex;
#endif

void
i_init_gif(void) {
#if !defined(GIFLIB_MAJOR) || GIFLIB_MAJOR < 5
  mutex = i_mutex_new();
#endif
}

static
void
i_colortable_copy(int **colour_table, int *colours, ColorMapObject *colourmap) {
  GifColorType *mapentry;
  int q;
  int colourmapsize = colourmap->ColorCount;

  if(colours) *colours = colourmapsize;
  if(!colour_table) return;
  
  *colour_table = mymalloc(sizeof(int) * colourmapsize * 3);
  memset(*colour_table, 0, sizeof(int) * colourmapsize * 3);

  for(q=0; q<colourmapsize; q++) {
    mapentry = &colourmap->Colors[q];
    (*colour_table)[q*3 + 0] = mapentry->Red;
    (*colour_table)[q*3 + 1] = mapentry->Green;
    (*colour_table)[q*3 + 2] = mapentry->Blue;
  }
}

#ifdef GIF_LIB_VERSION

static const
char gif_version_str[] = GIF_LIB_VERSION;

double
i_giflib_version(void) {
  const char *p = gif_version_str;

  while (*p && (*p < '0' || *p > '9'))
    ++p;

  if (!*p)
    return 0;

  return strtod(p, NULL);
}

#else

double
i_giflib_version(void) {
  return GIFLIB_MAJOR + GIFLIB_MINOR * 0.1;
}

#endif

/*
=item i_readgif_low(GifFileType *GifFile, int **colour_table, int *colours)

Internal.  Low-level function for reading a GIF file.  The caller must
create the appropriate GifFileType object and pass it in.

=cut
*/

i_img *
i_readgif_low(GifFileType *GifFile, int **colour_table, int *colours) {
  i_img *im;
  int i, j, Size, Row, Col, Width, Height, ExtCode, Count, x;
  int cmapcnt = 0, ImageNum = 0;
  ColorMapObject *ColorMap;
 
  GifRecordType RecordType;
  GifByteType *Extension;
  
  GifRowType GifRow;
  GifColorType *ColorMapEntry;
  i_color col;

  mm_log((1,"i_readgif_low(GifFile %p, colour_table %p, colours %p)\n", GifFile, colour_table, colours));

  /* it's possible that the caller has called us with *colour_table being
     non-NULL, but we check that to see if we need to free an allocated
     colour table on error.
  */
  if (colour_table) *colour_table = NULL;

  ColorMap = (GifFile->Image.ColorMap ? GifFile->Image.ColorMap : GifFile->SColorMap);

  if (ColorMap) {
    i_colortable_copy(colour_table, colours, ColorMap);
    cmapcnt++;
  }
  
  if (!i_int_check_image_file_limits(GifFile->SWidth, GifFile->SHeight, 3, sizeof(i_sample_t))) {
    if (colour_table && *colour_table) {
      myfree(*colour_table);
      *colour_table = NULL;
    }
    DGifCloseFile(GifFile);
    mm_log((1, "i_readgif: image size exceeds limits\n"));
    return NULL;
  }

  im = i_img_8_new(GifFile->SWidth, GifFile->SHeight, 3);
  if (!im) {
    if (colour_table && *colour_table) {
      myfree(*colour_table);
      *colour_table = NULL;
    }
    DGifCloseFile(GifFile);
    return NULL;
  }

  Size = GifFile->SWidth * sizeof(GifPixelType); 
  
  GifRow = mymalloc(Size);

  for (i = 0; i < GifFile->SWidth; i++) GifRow[i] = GifFile->SBackGroundColor;
  
  /* Scan the content of the GIF file and load the image(s) in: */
  do {
    if (DGifGetRecordType(GifFile, &RecordType) == GIF_ERROR) {
      gif_push_error(myGifError(GifFile));
      i_push_error(0, "Unable to get record type");
      if (colour_table && *colour_table) {
	myfree(*colour_table);
	*colour_table = NULL;
      }
      myfree(GifRow);
      i_img_destroy(im);
      DGifCloseFile(GifFile);
      return NULL;
    }
    
    switch (RecordType) {
    case IMAGE_DESC_RECORD_TYPE:
      if (DGifGetImageDesc(GifFile) == GIF_ERROR) {
	gif_push_error(myGifError(GifFile));
	i_push_error(0, "Unable to get image descriptor");
	if (colour_table && *colour_table) {
	  myfree(*colour_table);
	  *colour_table = NULL;
	}
	myfree(GifRow);
	i_img_destroy(im);
	DGifCloseFile(GifFile);
	return NULL;
      }

      if (( ColorMap = (GifFile->Image.ColorMap ? GifFile->Image.ColorMap : GifFile->SColorMap) )) {
	mm_log((1, "Adding local colormap\n"));
	if ( cmapcnt == 0) {
	  i_colortable_copy(colour_table, colours, ColorMap);
	  cmapcnt++;
	}
      } else {
	/* No colormap and we are about to read in the image - abandon for now */
	mm_log((1, "Going in with no colormap\n"));
	i_push_error(0, "Image does not have a local or a global color map");
	/* we can't have allocated a colour table here */
	myfree(GifRow);
	i_img_destroy(im);
	DGifCloseFile(GifFile);
	return NULL;
      }
      
      Row = GifFile->Image.Top; /* Image Position relative to Screen. */
      Col = GifFile->Image.Left;
      Width = GifFile->Image.Width;
      Height = GifFile->Image.Height;
      ImageNum++;
      mm_log((1,"i_readgif_low: Image %d at (%d, %d) [%dx%d]: \n",ImageNum, Col, Row, Width, Height));

      if (GifFile->Image.Left + GifFile->Image.Width > GifFile->SWidth ||
	  GifFile->Image.Top + GifFile->Image.Height > GifFile->SHeight) {
	i_push_errorf(0, "Image %d is not confined to screen dimension, aborted.\n",ImageNum);
	if (colour_table && *colour_table) {
	  myfree(*colour_table);
	  *colour_table = NULL;
	}
	myfree(GifRow);
	i_img_destroy(im);
	DGifCloseFile(GifFile);
	return NULL;
      }
      if (GifFile->Image.Interlace) {

	for (Count = i = 0; i < 4; i++) for (j = Row + InterlacedOffset[i]; j < Row + Height; j += InterlacedJumps[i]) {
	  Count++;
	  if (DGifGetLine(GifFile, GifRow, Width) == GIF_ERROR) {
	    gif_push_error(myGifError(GifFile));
	    i_push_error(0, "Reading GIF line");
	    if (colour_table && *colour_table) {
	      myfree(*colour_table);
	      *colour_table = NULL;
	    }
	    myfree(GifRow);
	    i_img_destroy(im);
	    DGifCloseFile(GifFile);
	    return NULL;
	  }
	  
	  for (x = 0; x < Width; x++) {
	    ColorMapEntry = &ColorMap->Colors[GifRow[x]];
	    col.rgb.r = ColorMapEntry->Red;
	    col.rgb.g = ColorMapEntry->Green;
	    col.rgb.b = ColorMapEntry->Blue;
	    i_ppix(im,Col+x,j,&col);
	  }
	  
	}
      }
      else {
	for (i = 0; i < Height; i++) {
	  if (DGifGetLine(GifFile, GifRow, Width) == GIF_ERROR) {
	    gif_push_error(myGifError(GifFile));
	    i_push_error(0, "Reading GIF line");
	    if (colour_table && *colour_table) {
	      myfree(*colour_table);
	      *colour_table = NULL;
	    }
	    myfree(GifRow);
	    i_img_destroy(im);
	    DGifCloseFile(GifFile);
	    return NULL;
	  }

	  for (x = 0; x < Width; x++) {
	    ColorMapEntry = &ColorMap->Colors[GifRow[x]];
	    col.rgb.r = ColorMapEntry->Red;
	    col.rgb.g = ColorMapEntry->Green;
	    col.rgb.b = ColorMapEntry->Blue;
	    i_ppix(im, Col+x, Row, &col);
	  }
	  Row++;
	}
      }
      break;
    case EXTENSION_RECORD_TYPE:
      /* Skip any extension blocks in file: */
      if (DGifGetExtension(GifFile, &ExtCode, &Extension) == GIF_ERROR) {
	gif_push_error(myGifError(GifFile));
	i_push_error(0, "Reading extension record");
	if (colour_table && *colour_table) {
	  myfree(*colour_table);
	  *colour_table = NULL;
	}
	myfree(GifRow);
	i_img_destroy(im);
	DGifCloseFile(GifFile);
	return NULL;
      }
      while (Extension != NULL) {
	if (DGifGetExtensionNext(GifFile, &Extension) == GIF_ERROR) {
	  gif_push_error(myGifError(GifFile));
	  i_push_error(0, "reading next block of extension");
	  if (colour_table && *colour_table) {
	    myfree(*colour_table);
	    *colour_table = NULL;
	  }
	  myfree(GifRow);
	  i_img_destroy(im);
	  DGifCloseFile(GifFile);
	  return NULL;
	}
      }
      break;
    case TERMINATE_RECORD_TYPE:
      break;
    default:		    /* Should be traps by DGifGetRecordType. */
      break;
    }
  } while (RecordType != TERMINATE_RECORD_TYPE);
  
  myfree(GifRow);
  
  if (DGifCloseFile(GifFile) == GIF_ERROR) {
    gif_push_error(myGifError(GifFile));
    i_push_error(0, "Closing GIF file object");
    if (colour_table && *colour_table) {
      myfree(*colour_table);
      *colour_table = NULL;
    }
    i_img_destroy(im);
    return NULL;
  }

  i_tags_set(&im->tags, "i_format", "gif", -1);

  return im;
}

/*

Internal function called by i_readgif_multi_low() in error handling

*/
static void
free_images(i_img **imgs, int count) {
  int i;
  
  if (count) {
    for (i = 0; i < count; ++i)
      i_img_destroy(imgs[i]);
    myfree(imgs);
  }
}

/*
=item i_readgif_multi_low(GifFileType *gf, int *count, int page)

Reads one of more gif images from the given GIF file.

Returns a pointer to an array of i_img *, and puts the count into 
*count.

If page is not -1 then the given image _only_ is returned from the
file, where the first image is 0, the second 1 and so on.

Unlike the normal i_readgif*() functions the images are paletted
images rather than a combined RGB image.

This functions sets tags on the images returned:

=over

=item gif_left

the offset of the image from the left of the "screen" ("Image Left
Position")

=item gif_top

the offset of the image from the top of the "screen" ("Image Top Position")

=item gif_interlace

non-zero if the image was interlaced ("Interlace Flag")

=item gif_screen_width

=item gif_screen_height

the size of the logical screen ("Logical Screen Width", 
"Logical Screen Height")

=item gif_local_map

Non-zero if this image had a local color map.

=item gif_background

The index in the global colormap of the logical screen's background
color.  This is only set if the current image uses the global
colormap.

=item gif_trans_index

The index of the color in the colormap used for transparency.  If the
image has a transparency then it is returned as a 4 channel image with
the alpha set to zero in this palette entry. ("Transparent Color Index")

=item gif_delay

The delay until the next frame is displayed, in 1/100 of a second. 
("Delay Time").

=item gif_user_input

whether or not a user input is expected before continuing (view dependent) 
("User Input Flag").

=item gif_disposal

how the next frame is displayed ("Disposal Method")

=item gif_loop

the number of loops from the Netscape Loop extension.  This may be zero.

=item gif_comment

the first block of the first gif comment before each image.

=back

Where applicable, the ("name") is the name of that field from the GIF89 
standard.

=cut
*/

i_img **
i_readgif_multi_low(GifFileType *GifFile, int *count, int page) {
  i_img *img;
  int i, j, Size, Width, Height, ExtCode, Count;
  int ImageNum = 0, ColorMapSize = 0;
  ColorMapObject *ColorMap;
 
  GifRecordType RecordType;
  GifByteType *Extension;
  
  GifRowType GifRow;
  int got_gce = 0;
  int trans_index = 0; /* transparent index if we see a GCE */
  int gif_delay = 0; /* delay from a GCE */
  int user_input = 0; /* user input flag from a GCE */
  int disposal = 0; /* disposal method from a GCE */
  int got_ns_loop = 0;
  int ns_loop = 0;
  char *comment = NULL; /* a comment */
  i_img **results = NULL;
  int result_alloc = 0;
  int channels;
  int image_colors = 0;
  i_color black; /* used to expand the palette if needed */

  for (i = 0; i < MAXCHANNELS; ++i)
    black.channel[i] = 0;
  
  *count = 0;

  mm_log((1,"i_readgif_multi_low(GifFile %p, , count %p)\n", GifFile, count));

  Size = GifFile->SWidth * sizeof(GifPixelType);
  
  GifRow = (GifRowType) mymalloc(Size);

  /* Scan the content of the GIF file and load the image(s) in: */
  do {
    if (DGifGetRecordType(GifFile, &RecordType) == GIF_ERROR) {
      gif_push_error(myGifError(GifFile));
      i_push_error(0, "Unable to get record type");
      free_images(results, *count);
      DGifCloseFile(GifFile);
      myfree(GifRow);
      if (comment)
	myfree(comment);
      return NULL;
    }
    
    switch (RecordType) {
    case IMAGE_DESC_RECORD_TYPE:
      if (DGifGetImageDesc(GifFile) == GIF_ERROR) {
	gif_push_error(myGifError(GifFile));
	i_push_error(0, "Unable to get image descriptor");
        free_images(results, *count);
	DGifCloseFile(GifFile);
	myfree(GifRow);
	if (comment)
	  myfree(comment);
	return NULL;
      }

      Width = GifFile->Image.Width;
      Height = GifFile->Image.Height;
      if (page == -1 || page == ImageNum) {
	if (( ColorMap = (GifFile->Image.ColorMap ? GifFile->Image.ColorMap : GifFile->SColorMap) )) {
	  mm_log((1, "Adding local colormap\n"));
	  ColorMapSize = ColorMap->ColorCount;
	} else {
	  /* No colormap and we are about to read in the image - 
	     abandon for now */
	  mm_log((1, "Going in with no colormap\n"));
	  i_push_error(0, "Image does not have a local or a global color map");
	  free_images(results, *count);
	  DGifCloseFile(GifFile);
	  myfree(GifRow);
	  if (comment)
	    myfree(comment);
	  return NULL;
	}
	
	channels = 3;
	if (got_gce && trans_index >= 0)
	  channels = 4;
	if (!i_int_check_image_file_limits(Width, Height, channels, sizeof(i_sample_t))) {
	  free_images(results, *count);
	  mm_log((1, "i_readgif: image size exceeds limits\n"));
	  DGifCloseFile(GifFile);
	  myfree(GifRow);
	  if (comment)
	    myfree(comment);
	  return NULL;
	}
	img = i_img_pal_new(Width, Height, channels, 256);
	if (!img) {
	  free_images(results, *count);
	  DGifCloseFile(GifFile);
	  if (comment)
	    myfree(comment);
	  myfree(GifRow);
	  return NULL;
	}
	/* populate the palette of the new image */
	mm_log((1, "ColorMapSize %d\n", ColorMapSize));
	for (i = 0; i < ColorMapSize; ++i) {
	  i_color col;
	  col.rgba.r = ColorMap->Colors[i].Red;
	  col.rgba.g = ColorMap->Colors[i].Green;
	  col.rgba.b = ColorMap->Colors[i].Blue;
	  if (channels == 4 && trans_index == i)
	    col.rgba.a = 0;
	  else
	    col.rgba.a = 255;
	  
	  i_addcolors(img, &col, 1);
	}
	image_colors = ColorMapSize;
	++*count;
	if (*count > result_alloc) {
	  if (result_alloc == 0) {
	    result_alloc = 5;
	    results = mymalloc(result_alloc * sizeof(i_img *));
	  }
	  else {
	    /* myrealloc never fails (it just dies if it can't allocate) */
	    result_alloc *= 2;
	    results = myrealloc(results, result_alloc * sizeof(i_img *));
	  }
	}
	results[*count-1] = img;
	i_tags_set(&img->tags, "i_format", "gif", -1);
	i_tags_setn(&img->tags, "gif_left", GifFile->Image.Left);
	/**(char *)0 = 1;*/
	i_tags_setn(&img->tags, "gif_top",  GifFile->Image.Top);
	i_tags_setn(&img->tags, "gif_interlace", GifFile->Image.Interlace);
	i_tags_setn(&img->tags, "gif_screen_width", GifFile->SWidth);
	i_tags_setn(&img->tags, "gif_screen_height", GifFile->SHeight);
	i_tags_setn(&img->tags, "gif_colormap_size", ColorMapSize);
	if (GifFile->SColorMap && !GifFile->Image.ColorMap) {
	  i_tags_setn(&img->tags, "gif_background",
		      GifFile->SBackGroundColor);
	}
	if (GifFile->Image.ColorMap) {
	  i_tags_setn(&img->tags, "gif_localmap", 1);
	}
	if (got_gce) {
	  if (trans_index >= 0) {
	    i_color trans;
	    i_tags_setn(&img->tags, "gif_trans_index", trans_index);
	    i_getcolors(img, trans_index, &trans, 1);
	    i_tags_set_color(&img->tags, "gif_trans_color", 0, &trans);
	  }
	  i_tags_setn(&img->tags, "gif_delay", gif_delay);
	  i_tags_setn(&img->tags, "gif_user_input", user_input);
	  i_tags_setn(&img->tags, "gif_disposal", disposal);
	}
	got_gce = 0;
	if (got_ns_loop)
	  i_tags_setn(&img->tags, "gif_loop", ns_loop);
	if (comment) {
	  i_tags_set(&img->tags, "gif_comment", comment, strlen(comment));
	  myfree(comment);
	  comment = NULL;
	}
	
	mm_log((1,"i_readgif_multi_low: Image %d at (%d, %d) [%dx%d]: \n",
		ImageNum, GifFile->Image.Left, GifFile->Image.Top, Width, Height));
	
	if (GifFile->Image.Left + GifFile->Image.Width > GifFile->SWidth ||
	    GifFile->Image.Top + GifFile->Image.Height > GifFile->SHeight) {
	  i_push_errorf(0, "Image %d is not confined to screen dimension, aborted.\n",ImageNum);
	  free_images(results, *count);        
	  DGifCloseFile(GifFile);
	  myfree(GifRow);
	  if (comment)
	    myfree(comment);
	  return(0);
	}
	
	if (GifFile->Image.Interlace) {
	  for (Count = i = 0; i < 4; i++) {
	    for (j = InterlacedOffset[i]; j < Height; 
		 j += InterlacedJumps[i]) {
	      Count++;
	      if (DGifGetLine(GifFile, GifRow, Width) == GIF_ERROR) {
		gif_push_error(myGifError(GifFile));
		i_push_error(0, "Reading GIF line");
		free_images(results, *count);
		DGifCloseFile(GifFile);
		myfree(GifRow);
		if (comment)
		  myfree(comment);
		return NULL;
	      }

	      /* range check the scanline if needed */
	      if (image_colors != 256) {
		int x;
		for (x = 0; x < Width; ++x) {
		  while (GifRow[x] >= image_colors) {
		    /* expand the palette since a palette index is too big */
		    i_addcolors(img, &black, 1);
		    ++image_colors;
		  }
		}
	      }

	      i_ppal(img, 0, Width, j, GifRow);
	    }
	  }
	}
	else {
	  for (i = 0; i < Height; i++) {
	    if (DGifGetLine(GifFile, GifRow, Width) == GIF_ERROR) {
	      gif_push_error(myGifError(GifFile));
	      i_push_error(0, "Reading GIF line");
	      free_images(results, *count);
	      DGifCloseFile(GifFile);
	      myfree(GifRow);
	      if (comment)
		myfree(comment);
	      return NULL;
	    }
	    
	    /* range check the scanline if needed */
	    if (image_colors != 256) {
	      int x;
	      for (x = 0; x < Width; ++x) {
		while (GifRow[x] >= image_colors) {
		  /* expand the palette since a palette index is too big */
		  i_addcolors(img, &black, 1);
		  ++image_colors;
		}
	      }
	    }

	    i_ppal(img, 0, Width, i, GifRow);
	  }
	}

	/* must be only one image wanted and that was it */
	if (page != -1) {
	  myfree(GifRow);
	  DGifCloseFile(GifFile);
	  if (comment)
	    myfree(comment);
	  return results;
	}
      }
      else {
	/* skip the image */
	/* whether interlaced or not, it has the same number of lines */
	/* giflib does't have an interface to skip the image data */
	for (i = 0; i < Height; i++) {
	  if (DGifGetLine(GifFile, GifRow, Width) == GIF_ERROR) {
	    gif_push_error(myGifError(GifFile));
	    i_push_error(0, "Reading GIF line");
	    free_images(results, *count);
	    myfree(GifRow);
	    DGifCloseFile(GifFile);
	    if (comment) 
	      myfree(comment);
	    return NULL;
	  }
	}

	/* kill the comment so we get the right comment for the page */
	if (comment) {
	  myfree(comment);
	  comment = NULL;
	}
      }
      ImageNum++;
      break;
    case EXTENSION_RECORD_TYPE:
      /* Skip any extension blocks in file: */
      if (DGifGetExtension(GifFile, &ExtCode, &Extension) == GIF_ERROR) {
	gif_push_error(myGifError(GifFile));
	i_push_error(0, "Reading extension record");
        free_images(results, *count);
	myfree(GifRow);
	DGifCloseFile(GifFile);
	if (comment)
	  myfree(comment);
	return NULL;
      }
      /* possibly this should be an error, but "be liberal in what you accept" */
      if (!Extension)
	break;
      if (ExtCode == 0xF9) {
        got_gce = 1;
        if (Extension[1] & 1)
          trans_index = Extension[4];
        else
          trans_index = -1;
        gif_delay = Extension[2] + 256 * Extension[3];
        user_input = (Extension[1] & 2) != 0;
        disposal = (Extension[1] >> 2) & 7;
      }
      if (ExtCode == 0xFF && *Extension == 11) {
        if (memcmp(Extension+1, "NETSCAPE2.0", 11) == 0) {
          if (DGifGetExtensionNext(GifFile, &Extension) == GIF_ERROR) {
            gif_push_error(myGifError(GifFile));
            i_push_error(0, "reading loop extension");
            free_images(results, *count);
	    myfree(GifRow);
	    DGifCloseFile(GifFile);
	    if (comment)
	      myfree(comment);
            return NULL;
          }
          if (Extension && *Extension == 3) {
            got_ns_loop = 1;
            ns_loop = Extension[2] + 256 * Extension[3];
          }
        }
      }
      else if (ExtCode == 0xFE) {
        /* while it's possible for a GIF file to contain more than one
           comment, I'm only implementing a single comment per image, 
           with the comment saved into the following image.
           If someone wants more than that they can implement it.
           I also don't handle comments that take more than one block.
        */
        if (!comment) {
          comment = mymalloc(*Extension+1);
          memcpy(comment, Extension+1, *Extension);
          comment[*Extension] = '\0';
        }
      }
      while (Extension != NULL) {
	if (DGifGetExtensionNext(GifFile, &Extension) == GIF_ERROR) {
	  gif_push_error(myGifError(GifFile));
	  i_push_error(0, "reading next block of extension");
          free_images(results, *count);
	  myfree(GifRow);
	  DGifCloseFile(GifFile);
	  if (comment)
	    myfree(comment);
	  return NULL;
	}
      }
      break;
    case TERMINATE_RECORD_TYPE:
      break;
    default:		    /* Should be trapped by DGifGetRecordType. */
      break;
    }
  } while (RecordType != TERMINATE_RECORD_TYPE);

  if (comment) {
    if (*count) {
      i_tags_set(&(results[*count-1]->tags), "gif_comment", comment, 
                 strlen(comment));
    }
    myfree(comment);
  }
  
  myfree(GifRow);
  
  if (DGifCloseFile(GifFile) == GIF_ERROR) {
    gif_push_error(myGifError(GifFile));
    i_push_error(0, "Closing GIF file object");
    free_images(results, *count);
    return NULL;
  }

  if (ImageNum && page != -1) {
    /* there were images, but the page selected wasn't found */
    i_push_errorf(0, "page %d not found (%d total)", page, ImageNum);
    free_images(results, *count);
    return NULL;
  }

  return results;
}

static int io_glue_read_cb(GifFileType *gft, GifByteType *buf, int length);

/*
=item i_readgif_multi_wiol(ig, int *count)

=cut
*/

i_img **
i_readgif_multi_wiol(io_glue *ig, int *count) {
  GifFileType *GifFile;
  int gif_error;
  i_img **result;

  gif_mutex_lock(mutex);

  i_clear_error();
  
  if ((GifFile = myDGifOpen((void *)ig, io_glue_read_cb, &gif_error )) == NULL) {
    gif_push_error(gif_error);
    i_push_error(0, "Cannot create giflib callback object");
    mm_log((1,"i_readgif_multi_wiol: Unable to open callback datasource.\n"));
    gif_mutex_unlock(mutex);
    return NULL;
  }
    
  result = i_readgif_multi_low(GifFile, count, -1);

  gif_mutex_unlock(mutex);

  return result;
}

static int
io_glue_read_cb(GifFileType *gft, GifByteType *buf, int length) {
  io_glue *ig = (io_glue *)gft->UserData;

  return i_io_read(ig, buf, length);
}

i_img *
i_readgif_wiol(io_glue *ig, int **color_table, int *colors) {
  GifFileType *GifFile;
  int gif_error;
  i_img *result;

  gif_mutex_lock(mutex);

  i_clear_error();

  if ((GifFile = myDGifOpen((void *)ig, io_glue_read_cb, &gif_error )) == NULL) {
    gif_push_error(gif_error);
    i_push_error(0, "Cannot create giflib callback object");
    mm_log((1,"i_readgif_wiol: Unable to open callback datasource.\n"));
    gif_mutex_unlock(mutex);
    return NULL;
  }
    
  result = i_readgif_low(GifFile, color_table, colors);

  gif_mutex_unlock(mutex);

  return result;
}

/*
=item i_readgif_single_low(GifFile, page)

Lower level function to read a single image from a GIF.

page must be non-negative.

=cut
*/
static i_img *
i_readgif_single_low(GifFileType *GifFile, int page) {
  int count = 0;
  i_img **imgs;

  imgs = i_readgif_multi_low(GifFile, &count, page);

  if (imgs && count) {
    i_img *result = imgs[0];

    myfree(imgs);
    return result;
  }
  else {
    /* i_readgif_multi_low() handles the errors appropriately */
    return NULL;
  }
}

/*
=item i_readgif_single_wiol(ig, page)

Read a single page from a GIF image file, where the page is indexed
from 0.

Returns NULL if the page isn't found.

=cut
*/

i_img *
i_readgif_single_wiol(io_glue *ig, int page) {
  GifFileType *GifFile;
  int gif_error;
  i_img *result;

  i_clear_error();
  if (page < 0) {
    i_push_error(0, "page must be non-negative");
    return NULL;
  }

  gif_mutex_lock(mutex);

  if ((GifFile = myDGifOpen((void *)ig, io_glue_read_cb, &gif_error )) == NULL) {
    gif_push_error(gif_error);
    i_push_error(0, "Cannot create giflib callback object");
    mm_log((1,"i_readgif_wiol: Unable to open callback datasource.\n"));
    gif_mutex_unlock(mutex);
    return NULL;
  }
    
  result = i_readgif_single_low(GifFile, page);

  gif_mutex_unlock(mutex);

  return result;
}

/*
=item do_write(GifFileType *gf, i_gif_opts *opts, i_img *img, i_palidx *data)

Internal.  Low level image write function.  Writes in interlace if
that was requested in the GIF options.

Returns non-zero on success.

=cut
*/
static undef_int 
do_write(GifFileType *gf, int interlace, i_img *img, i_palidx *data) {
  if (interlace) {
    int i, j;
    for (i = 0; i < 4; ++i) {
      for (j = InterlacedOffset[i]; j < img->ysize; j += InterlacedJumps[i]) {
	if (EGifPutLine(gf, data+j*img->xsize, img->xsize) == GIF_ERROR) {
	  gif_push_error(myGifError(gf));
	  i_push_error(0, "Could not save image data:");
	  mm_log((1, "Error in EGifPutLine\n"));
	  EGifCloseFile(gf);
	  return 0;
	}
      }
    }
  }
  else {
    int y;
    for (y = 0; y < img->ysize; ++y) {
      if (EGifPutLine(gf, data, img->xsize) == GIF_ERROR) {
	gif_push_error(myGifError(gf));
	i_push_error(0, "Could not save image data:");
	mm_log((1, "Error in EGifPutLine\n"));
	EGifCloseFile(gf);
	return 0;
      }
      data += img->xsize;
    }
  }

  return 1;
}

/*
=item do_gce(GifFileType *gf, int index, i_gif_opts *opts, int want_trans, int trans_index)

Internal. Writes the GIF graphics control extension, if necessary.

Returns non-zero on success.

=cut
*/

static int
do_gce(GifFileType *gf, i_img *img, int want_trans, int trans_index)
{
  unsigned char gce[4] = {0};
  int want_gce = 0;
  int delay;
  int user_input;
  int disposal_method;

  if (want_trans) {
    gce[0] |= 1;
    gce[3] = trans_index;
    ++want_gce;
  }
  if (i_tags_get_int(&img->tags, "gif_delay", 0, &delay)) {
    gce[1] = delay % 256;
    gce[2] = delay / 256;
    ++want_gce;
  }
  if (i_tags_get_int(&img->tags, "gif_user_input", 0, &user_input) 
      && user_input) {
    gce[0] |= 2;
    ++want_gce;
  }
  if (i_tags_get_int(&img->tags, "gif_disposal", 0, &disposal_method)) {
    gce[0] |= (disposal_method & 3) << 2;
    ++want_gce;
  }
  if (want_gce) {
    if (EGifPutExtension(gf, 0xF9, sizeof(gce), gce) == GIF_ERROR) {
      gif_push_error(myGifError(gf));
      i_push_error(0, "Could not save GCE");
    }
  }
  return 1;
}

/*
=item do_comments(gf, img)

Write any comments in the image.

=cut
*/

static int
do_comments(GifFileType *gf, i_img *img) {
  int pos = -1;

  while (i_tags_find(&img->tags, "gif_comment", pos+1, &pos)) {
    if (img->tags.tags[pos].data) {
      if (EGifPutComment(gf, img->tags.tags[pos].data) == GIF_ERROR) {
        return 0;
      }
    }
    else {
      char buf[50];
#ifdef IMAGER_SNPRINTF
      snprintf(buf, sizeof(buf), "%d", img->tags.tags[pos].idata);
#else
      sprintf(buf, "%d", img->tags.tags[pos].idata);
#endif
      if (EGifPutComment(gf, buf) == GIF_ERROR) {
        return 0;
      }
    }
  }

  return 1;
}

/*
=item do_ns_loop(GifFileType *gf, i_gif_opts *opts)

Internal.  Add the Netscape2.0 loop extension block, if requested.

Giflib/libungif prior to 4.1.1 didn't support writing application
extension blocks, so we don't attempt to write them for older versions.

Giflib/libungif prior to 4.1.3 used the wrong write mechanism when
writing extension blocks so that they could only be written to files.

=cut
*/

static int
do_ns_loop(GifFileType *gf, i_img *img)
{
  /* EGifPutExtension() doesn't appear to handle application 
     extension blocks in any way
     Since giflib wraps the fd with a FILE * (and puts that in its
     private data), we can't do an end-run and write the data 
     directly to the fd.
     There's no open interface that takes a FILE * either, so we 
     can't workaround it that way either.
     If giflib's callback interface wasn't broken by default, I'd 
     force file writes to use callbacks, but it is broken by default.
  */
  /* yes this was another attempt at supporting the loop extension */
  int loop_count;
  if (i_tags_get_int(&img->tags, "gif_loop", 0, &loop_count)) {
    unsigned char nsle[12] = "NETSCAPE2.0";
    unsigned char subblock[3];

    subblock[0] = 1;
    subblock[1] = loop_count % 256;
    subblock[2] = loop_count / 256;

#if defined(GIFLIB_MAJOR) && GIFLIB_MAJOR >= 5
    if (EGifPutExtensionLeader(gf, APPLICATION_EXT_FUNC_CODE) == GIF_ERROR
	|| EGifPutExtensionBlock(gf, 11, nsle) == GIF_ERROR
	|| EGifPutExtensionBlock(gf, 3, subblock) == GIF_ERROR
	|| EGifPutExtensionTrailer(gf) == GIF_ERROR) {
      gif_push_error(myGifError(gf));
      i_push_error(0, "writing loop extension");
      return 0;
    }
	
#else
    if (EGifPutExtensionFirst(gf, APPLICATION_EXT_FUNC_CODE, 11, nsle) == GIF_ERROR) {
      gif_push_error(myGifError(gf));
      i_push_error(0, "writing loop extension");
      return 0;
    }
    if (EGifPutExtensionLast(gf, APPLICATION_EXT_FUNC_CODE, 3, subblock) == GIF_ERROR) {
      gif_push_error(myGifError(gf));
      i_push_error(0, "writing loop extension sub-block");
      return 0;
    }
#endif
  }

  return 1;
}

/*
=item make_gif_map(i_quantize *quant, int want_trans)

Create a giflib color map object from an Imager color map.

=cut
*/

static ColorMapObject *
make_gif_map(i_quantize *quant, i_img *img, int want_trans) {
  GifColorType colors[256];
  int i;
  int size = quant->mc_count;
  int map_size;
  ColorMapObject *map;
  i_color trans;

  for (i = 0; i < quant->mc_count; ++i) {
    colors[i].Red = quant->mc_colors[i].rgb.r;
    colors[i].Green = quant->mc_colors[i].rgb.g;
    colors[i].Blue = quant->mc_colors[i].rgb.b;
  }
  if (want_trans) {
    if (!i_tags_get_color(&img->tags, "gif_trans_color", 0, &trans))
      trans.rgb.r = trans.rgb.g = trans.rgb.b = 0;
    colors[size].Red = trans.rgb.r;
    colors[size].Green = trans.rgb.g;
    colors[size].Blue = trans.rgb.b;
    ++size;
  }
  map_size = 1;
  while (map_size < size)
    map_size <<= 1;
  /* giflib spews for 1 colour maps, reasonable, I suppose */
  if (map_size == 1)
    map_size = 2;
  while (i < map_size) {
    colors[i].Red = colors[i].Green = colors[i].Blue = 0;
    ++i;
  }
  
  map = MakeMapObject(map_size, colors);
  mm_log((1, "XXX map is at %p and colors at %p\n", map, map->Colors));
  if (!map) {
    i_push_error(0, "Could not create color map object");
    return NULL;
  }
#if defined GIFLIB_MAJOR && GIFLIB_MAJOR >= 5
  map->SortFlag = 0;
#endif
  return map;
}

/*
=item need_version_89a(i_quantize *quant, i_img *imgs, int count)

Return true if the file we're creating on these images needs a GIF89a
header.

=cut
*/

static int
need_version_89a(i_quantize *quant, i_img **imgs, int count) {
  int need_89a = 0;
  int temp;
  int i;

  for (i = 0; i < count; ++i) {
    if (quant->transp != tr_none &&
	(imgs[i]->channels == 2 || imgs[i]->channels == 4)) {
      need_89a = 1;
      break;
    }
    if (i_tags_get_int(&imgs[i]->tags, "gif_delay", 0, &temp)) {
      need_89a = 1;
      break;
    }
    if (i_tags_get_int(&imgs[i]->tags, "gif_user_input", 0, &temp) && temp) {
      need_89a = 1; 
      break;
    }
    if (i_tags_get_int(&imgs[i]->tags, "gif_disposal", 0, &temp)) {
      need_89a = 1;
      break;
    }
    if (i_tags_get_int(&imgs[i]->tags, "gif_loop", 0, &temp)) {
      need_89a = 1;
      break;
    }
  }

  return need_89a;
}

static int 
in_palette(i_color *c, i_quantize *quant, int size) {
  int i;

  for (i = 0; i < size; ++i) {
    if (c->channel[0] == quant->mc_colors[i].channel[0]
        && c->channel[1] == quant->mc_colors[i].channel[1]
        && c->channel[2] == quant->mc_colors[i].channel[2]) {
      return i;
    }
  }

  return -1;
}

/*
=item has_common_palette(imgs, count, quant)

Tests if all the given images are paletted and their colors are in the
palette produced.

Previously this would build a consolidated palette from the source,
but that meant that if the caller supplied a static palette (or
specified a fixed palette like "webmap") then we wouldn't be
quantizing to the caller specified palette.

=cut
*/

static int
has_common_palette(i_img **imgs, int count, i_quantize *quant) {
  int i;
  int imgn;
  char used[256];
  int col_count;

  /* we try to build a common palette here, if we can manage that, then
     that's the palette we use */
  for (imgn = 0; imgn < count; ++imgn) {
    int eliminate_unused;
    if (imgs[imgn]->type != i_palette_type)
      return 0;

    if (!i_tags_get_int(&imgs[imgn]->tags, "gif_eliminate_unused", 0, 
                        &eliminate_unused)) {
      eliminate_unused = 1;
    }

    if (eliminate_unused) {
      i_palidx *line = mymalloc(sizeof(i_palidx) * imgs[imgn]->xsize);
      int x, y;
      memset(used, 0, sizeof(used));

      for (y = 0; y < imgs[imgn]->ysize; ++y) {
        i_gpal(imgs[imgn], 0, imgs[imgn]->xsize, y, line);
        for (x = 0; x < imgs[imgn]->xsize; ++x)
          used[line[x]] = 1;
      }

      myfree(line);
    }
    else {
      /* assume all are in use */
      memset(used, 1, sizeof(used));
    }

    col_count = i_colorcount(imgs[imgn]);
    for (i = 0; i < col_count; ++i) {
      i_color c;
      
      i_getcolors(imgs[imgn], i, &c, 1);
      if (used[i]) {
        if (in_palette(&c, quant, quant->mc_count) < 0) {
	  mm_log((1, "  color not found in palette, no palette shortcut\n"));
  
	  return 0;
        }
      }
    }
  }

  mm_log((1, "  all colors found in palette, palette shortcut\n"));

  return 1;
}

static i_palidx *
quant_paletted(i_quantize *quant, i_img *img) {
  i_palidx *data = mymalloc(sizeof(i_palidx) * img->xsize * img->ysize);
  i_palidx *p = data;
  i_palidx trans[256];
  int i;
  i_img_dim x, y;

  /* build a translation table */
  for (i = 0; i < i_colorcount(img); ++i) {
    i_color c;
    i_getcolors(img, i, &c, 1);
    trans[i] = in_palette(&c, quant, quant->mc_count);
  }

  for (y = 0; y < img->ysize; ++y) {
    i_gpal(img, 0, img->xsize, y, data+img->xsize * y);
    for (x = 0; x < img->xsize; ++x) {
      *p = trans[*p];
      ++p;
    }
  }

  return data;
}

/*
=item i_writegif_low(i_quantize *quant, GifFileType *gf, i_img **imgs, int count, i_gif_opts *opts)

Internal.  Low-level function that does the high-level GIF processing
:)

Returns non-zero on success.

=cut
*/

static undef_int
i_writegif_low(i_quantize *quant, GifFileType *gf, i_img **imgs, int count) {
  unsigned char *result = NULL;
  int color_bits;
  ColorMapObject *map;
  int scrw = 0, scrh = 0;
  int imgn, orig_count, orig_size;
  int posx, posy;
  int trans_index = -1;
  int *localmaps;
  int anylocal;
  i_img **glob_imgs; /* images that will use the global color map */
  int glob_img_count;
  i_color *orig_colors = quant->mc_colors;
  i_color *glob_colors = NULL;
  int glob_color_count = 0;
  int glob_want_trans;
  int glob_paletted = 0; /* the global map was made from the image palettes */
  int colors_paletted = 0;
  int want_trans = 0;
  int interlace;
  int gif_background;

  mm_log((1, "i_writegif_low(quant %p, gf  %p, imgs %p, count %d)\n", 
	  quant, gf, imgs, count));
  
  /* *((char *)0) = 1; */ /* used to break into the debugger */
  
  if (count <= 0) {
    i_push_error(0, "No images provided to write");
    return 0; /* what are you smoking? */
  }

  /* sanity is nice */
  if (quant->mc_size > 256) 
    quant->mc_size = 256;
  if (quant->mc_count > quant->mc_size)
    quant->mc_count = quant->mc_size;

  if (!i_tags_get_int(&imgs[0]->tags, "gif_screen_width", 0, &scrw))
    scrw = 0;
  if (!i_tags_get_int(&imgs[0]->tags, "gif_screen_height", 0, &scrh))
    scrh = 0;

  anylocal = 0;
  localmaps = mymalloc(sizeof(int) * count);
  glob_imgs = mymalloc(sizeof(i_img *) * count);
  glob_img_count = 0;
  glob_want_trans = 0;
  for (imgn = 0; imgn < count; ++imgn) {
    i_img *im = imgs[imgn];
    if (im->xsize > 0xFFFF || im->ysize > 0xFFFF) {
      i_push_error(0, "image too large for GIF");
      return 0;
    }
    
    posx = posy = 0;
    i_tags_get_int(&im->tags, "gif_left", 0, &posx);
    if (posx < 0) posx = 0;
    i_tags_get_int(&im->tags, "gif_top", 0, &posy);
    if (posy < 0) posy = 0;
    if (im->xsize + posx > scrw)
      scrw = im->xsize + posx;
    if (im->ysize + posy > scrh)
      scrh = im->ysize + posy;
    if (!i_tags_get_int(&im->tags, "gif_local_map", 0, localmaps+imgn))
      localmaps[imgn] = 0;
    if (localmaps[imgn])
      anylocal = 1;
    else {
      if (im->channels == 4) {
        glob_want_trans = 1;
      }
      glob_imgs[glob_img_count++] = im;
    }
  }
  glob_want_trans = glob_want_trans && quant->transp != tr_none ;

  if (scrw > 0xFFFF || scrh > 0xFFFF) {
    i_push_error(0, "screen size too large for GIF");
    return 0;
  }

  orig_count = quant->mc_count;
  orig_size = quant->mc_size;

  if (glob_img_count) {
    /* this is ugly */
    glob_colors = mymalloc(sizeof(i_color) * quant->mc_size);
    quant->mc_colors = glob_colors;
    memcpy(glob_colors, orig_colors, sizeof(i_color) * quant->mc_count);
    /* we have some images that want to use the global map */
    if (glob_want_trans && quant->mc_count == 256) {
      mm_log((2, "  disabling transparency for global map - no space\n"));
      glob_want_trans = 0;
    }
    if (glob_want_trans && quant->mc_size == 256) {
      mm_log((2, "  reserving color for transparency\n"));
      --quant->mc_size;
    }

    i_quant_makemap(quant, glob_imgs, glob_img_count);
    glob_paletted = has_common_palette(glob_imgs, glob_img_count, quant);
    glob_color_count = quant->mc_count;
    quant->mc_colors = orig_colors;
  }

  /* use the global map if we have one, otherwise use the local map */
  gif_background = 0;
  if (glob_colors) {
    quant->mc_colors = glob_colors;
    quant->mc_count = glob_color_count;
    want_trans = glob_want_trans && imgs[0]->channels == 4;

    if (!i_tags_get_int(&imgs[0]->tags, "gif_background", 0, &gif_background))
      gif_background = 0;
    if (gif_background < 0)
      gif_background = 0;
    if (gif_background >= glob_color_count)
      gif_background = 0;
  }
  else {
    want_trans = quant->transp != tr_none && imgs[0]->channels == 4;
    i_quant_makemap(quant, imgs, 1);
    colors_paletted = has_common_palette(imgs, 1, quant);
  }

  if ((map = make_gif_map(quant, imgs[0], want_trans)) == NULL) {
    myfree(glob_colors);
    myfree(localmaps);
    myfree(glob_imgs);
    quant->mc_colors = orig_colors;
    EGifCloseFile(gf);
    mm_log((1, "Error in MakeMapObject"));
    return 0;
  }
  color_bits = 1;
  if (anylocal) {
    /* since we don't know how big some the local palettes could be
       we need to base the bits on the maximum number of colors */
    while (orig_size > (1 << color_bits))
      ++color_bits;
  }
  else {
    int count = quant->mc_count;
    if (want_trans)
      ++count;
    while (count > (1 << color_bits))
      ++color_bits;
  }
  
  if (EGifPutScreenDesc(gf, scrw, scrh, color_bits, 
                        gif_background, map) == GIF_ERROR) {
    myfree(glob_colors);
    myfree(localmaps);
    myfree(glob_imgs);
    quant->mc_colors = orig_colors;
    gif_push_error(myGifError(gf));
    i_push_error(0, "Could not save screen descriptor");
    FreeMapObject(map);
    myfree(result);
    EGifCloseFile(gf);
    mm_log((1, "Error in EGifPutScreenDesc."));
    return 0;
  }
  FreeMapObject(map);

  if (!i_tags_get_int(&imgs[0]->tags, "gif_left", 0, &posx))
    posx = 0;
  if (!i_tags_get_int(&imgs[0]->tags, "gif_top", 0, &posy))
    posy = 0;

  if (!localmaps[0]) {
    map = NULL;
    colors_paletted = glob_paletted;
  }
  else {
    /* if this image has a global map the colors in quant don't
       belong to this image, so build a palette */
    if (glob_colors) {
      /* generate the local map for this image */
      quant->mc_colors = orig_colors;
      quant->mc_size = orig_size;
      quant->mc_count = orig_count;
      want_trans = quant->transp != tr_none && imgs[0]->channels == 4;

      /* if the caller gives us too many colours we can't do transparency */
      if (want_trans && quant->mc_count == 256)
        want_trans = 0;
      /* if they want transparency but give us a big size, make it smaller
         to give room for a transparency colour */
      if (want_trans && quant->mc_size == 256)
        --quant->mc_size;
      i_quant_makemap(quant, imgs, 1);
      colors_paletted = has_common_palette(imgs, 1, quant);
      if ((map = make_gif_map(quant, imgs[0], want_trans)) == NULL) {
	myfree(glob_colors);
	myfree(localmaps);
	myfree(glob_imgs);
        EGifCloseFile(gf);
        quant->mc_colors = orig_colors;
        mm_log((1, "Error in MakeMapObject"));
        return 0;
      }
    }
    else {
      /* the map we wrote was the map for this image - don't set the local 
         map */
      map = NULL;
    }
  }

  if (colors_paletted)
    result = quant_paletted(quant, imgs[0]);
  else
    result = i_quant_translate(quant, imgs[0]);
  if (!result) {
    myfree(glob_colors);
    myfree(localmaps);
    myfree(glob_imgs);
    quant->mc_colors = orig_colors;
    EGifCloseFile(gf);
    return 0;
  }
  if (want_trans) {
    i_quant_transparent(quant, result, imgs[0], quant->mc_count);
    trans_index = quant->mc_count;
  }

  if (!do_ns_loop(gf, imgs[0])) {
    myfree(glob_colors);
    myfree(localmaps);
    myfree(glob_imgs);
    quant->mc_colors = orig_colors;
    return 0;
  }

  if (!do_gce(gf, imgs[0], want_trans, trans_index)) {
    myfree(glob_colors);
    myfree(localmaps);
    myfree(glob_imgs);
    quant->mc_colors = orig_colors;
    myfree(result);
    EGifCloseFile(gf);
    return 0;
  }

  if (!do_comments(gf, imgs[0])) {
    myfree(glob_colors);
    myfree(localmaps);
    myfree(glob_imgs);
    quant->mc_colors = orig_colors;
    myfree(result);
    EGifCloseFile(gf);
    return 0;
  }

  if (!i_tags_get_int(&imgs[0]->tags, "gif_interlace", 0, &interlace))
    interlace = 0;
  if (EGifPutImageDesc(gf, posx, posy, imgs[0]->xsize, imgs[0]->ysize, 
                       interlace, map) == GIF_ERROR) {
    myfree(glob_colors);
    myfree(localmaps);
    myfree(glob_imgs);
    quant->mc_colors = orig_colors;
    gif_push_error(myGifError(gf));
    i_push_error(0, "Could not save image descriptor");
    EGifCloseFile(gf);
    mm_log((1, "Error in EGifPutImageDesc."));
    return 0;
  }
  if (map)
    FreeMapObject(map);

  if (!do_write(gf, interlace, imgs[0], result)) {
    myfree(glob_colors);
    myfree(localmaps);
    myfree(glob_imgs);
    quant->mc_colors = orig_colors;
    EGifCloseFile(gf);
    myfree(result);
    return 0;
  }
  myfree(result);

  /* that first awful image is out of the way, do the rest */
  for (imgn = 1; imgn < count; ++imgn) {
    if (localmaps[imgn]) {
      quant->mc_colors = orig_colors;
      quant->mc_count = orig_count;
      quant->mc_size = orig_size;

      want_trans = quant->transp != tr_none 
	&& imgs[imgn]->channels == 4;
      /* if the caller gives us too many colours we can't do transparency */
      if (want_trans && quant->mc_count == 256)
	want_trans = 0;
      /* if they want transparency but give us a big size, make it smaller
	 to give room for a transparency colour */
      if (want_trans && quant->mc_size == 256)
	--quant->mc_size;

      if (has_common_palette(imgs+imgn, 1, quant)) {
        result = quant_paletted(quant, imgs[imgn]);
      }
      else {
        i_quant_makemap(quant, imgs+imgn, 1);
        result = i_quant_translate(quant, imgs[imgn]);
      }
      if (!result) {
	myfree(glob_colors);
	myfree(localmaps);
	myfree(glob_imgs);
        quant->mc_colors = orig_colors;
        EGifCloseFile(gf);
        mm_log((1, "error in i_quant_translate()"));
        return 0;
      }
      if (want_trans) {
        i_quant_transparent(quant, result, imgs[imgn], quant->mc_count);
        trans_index = quant->mc_count;
      }

      if ((map = make_gif_map(quant, imgs[imgn], want_trans)) == NULL) {
	myfree(glob_colors);
	myfree(localmaps);
	myfree(glob_imgs);
        quant->mc_colors = orig_colors;
        myfree(result);
        EGifCloseFile(gf);
        mm_log((1, "Error in MakeMapObject."));
        return 0;
      }
    }
    else {
      quant->mc_colors = glob_colors;
      quant->mc_count = glob_color_count;
      if (glob_paletted)
        result = quant_paletted(quant, imgs[imgn]);
      else
        result = i_quant_translate(quant, imgs[imgn]);
      want_trans = glob_want_trans && imgs[imgn]->channels == 4;
      if (want_trans) {
        i_quant_transparent(quant, result, imgs[imgn], quant->mc_count);
        trans_index = quant->mc_count;
      }
      map = NULL;
    }

    if (!do_gce(gf, imgs[imgn], want_trans, trans_index)) {
      myfree(glob_colors);
      myfree(localmaps);
      myfree(glob_imgs);
      quant->mc_colors = orig_colors;
      myfree(result);
      EGifCloseFile(gf);
      return 0;
    }

    if (!do_comments(gf, imgs[imgn])) {
      myfree(glob_colors);
      myfree(localmaps);
      myfree(glob_imgs);
      quant->mc_colors = orig_colors;
      myfree(result);
      EGifCloseFile(gf);
      return 0;
    }

    if (!i_tags_get_int(&imgs[imgn]->tags, "gif_left", 0, &posx))
      posx = 0;
    if (!i_tags_get_int(&imgs[imgn]->tags, "gif_top", 0, &posy))
      posy = 0;

    if (!i_tags_get_int(&imgs[imgn]->tags, "gif_interlace", 0, &interlace))
      interlace = 0;
    if (EGifPutImageDesc(gf, posx, posy, imgs[imgn]->xsize, 
                         imgs[imgn]->ysize, interlace, map) == GIF_ERROR) {
      myfree(glob_colors);
      myfree(localmaps);
      myfree(glob_imgs);
      quant->mc_colors = orig_colors;
      gif_push_error(myGifError(gf));
      i_push_error(0, "Could not save image descriptor");
      myfree(result);
      if (map)
        FreeMapObject(map);
      EGifCloseFile(gf);
      mm_log((1, "Error in EGifPutImageDesc."));
      return 0;
    }
    if (map)
      FreeMapObject(map);
    
    if (!do_write(gf, interlace, imgs[imgn], result)) {
      myfree(glob_colors);
      myfree(localmaps);
      myfree(glob_imgs);
      quant->mc_colors = orig_colors;
      EGifCloseFile(gf);
      myfree(result);
      return 0;
    }
    myfree(result);
  }

  if (EGifCloseFile(gf) == GIF_ERROR) {
    myfree(glob_colors);
    myfree(localmaps);
    myfree(glob_imgs);
    gif_push_error(myGifError(gf));
    i_push_error(0, "Could not close GIF file");
    mm_log((1, "Error in EGifCloseFile\n"));
    return 0;
  }
  if (glob_colors) {
    int i;
    for (i = 0; i < glob_color_count; ++i)
      orig_colors[i] = glob_colors[i];
  }

  myfree(glob_colors);
  myfree(localmaps);
  myfree(glob_imgs);
  quant->mc_colors = orig_colors;

  return 1;
}

static int
io_glue_write_cb(GifFileType *gft, const GifByteType *data, int length) {
  io_glue *ig = (io_glue *)gft->UserData;

  return i_io_write(ig, data, length);
}


/*
=item i_writegif_wiol(ig, quant, opts, imgs, count)

=cut
*/
undef_int
i_writegif_wiol(io_glue *ig, i_quantize *quant, i_img **imgs,
                int count) {
  GifFileType *GifFile;
  int gif_error;
  int result;

  gif_mutex_lock(mutex);

  i_clear_error();

#ifdef PRE_SET_VERSION
  EGifSetGifVersion(need_version_89a(quant, imgs, count) ? "89a" : "87a");
#endif
  
  if ((GifFile = myEGifOpen((void *)ig, io_glue_write_cb, &gif_error )) == NULL) {
    gif_push_error(gif_error);
    i_push_error(0, "Cannot create giflib callback object");
    mm_log((1,"i_writegif_wiol: Unable to open callback datasource.\n"));
    gif_mutex_unlock(mutex);
    return 0;
  }
  
#ifdef POST_SET_VERSION
  EGifSetGifVersion(GifFile, need_version_89a(quant, imgs, count));
#endif

  result = i_writegif_low(quant, GifFile, imgs, count);
  
  gif_mutex_unlock(mutex);

  if (i_io_close(ig))
    return 0;
  
  return result;
}

/*
=item gif_error_msg(int code)

Grabs the most recent giflib error code from GifLastError() and 
returns a string that describes that error.

Returns NULL for unknown error codes.

=cut
*/

static char const *
gif_error_msg(int code) {
#if defined(GIFLIB_MAJOR) && GIFLIB_MAJOR >= 5
  return GifErrorString(code);
#else
  switch (code) {
  case E_GIF_ERR_OPEN_FAILED: /* should not see this */
    return "Failed to open given file";
    
  case E_GIF_ERR_WRITE_FAILED:
    return "Write failed";

  case E_GIF_ERR_HAS_SCRN_DSCR: /* should not see this */
    return "Screen descriptor already passed to giflib";

  case E_GIF_ERR_HAS_IMAG_DSCR: /* should not see this */
    return "Image descriptor already passed to giflib";
    
  case E_GIF_ERR_NO_COLOR_MAP: /* should not see this */
    return "Neither global nor local color map set";

  case E_GIF_ERR_DATA_TOO_BIG: /* should not see this */
    return "Too much pixel data passed to giflib";

  case E_GIF_ERR_NOT_ENOUGH_MEM:
    return "Out of memory";
    
  case E_GIF_ERR_DISK_IS_FULL:
    return "Disk is full";
    
  case E_GIF_ERR_CLOSE_FAILED: /* should not see this */
    return "File close failed";
 
  case E_GIF_ERR_NOT_WRITEABLE: /* should not see this */
    return "File not writable";

  case D_GIF_ERR_OPEN_FAILED:
    return "Failed to open file";
    
  case D_GIF_ERR_READ_FAILED:
    return "Failed to read from file";

  case D_GIF_ERR_NOT_GIF_FILE:
    return "File is not a GIF file";

  case D_GIF_ERR_NO_SCRN_DSCR:
    return "No screen descriptor detected - invalid file";

  case D_GIF_ERR_NO_IMAG_DSCR:
    return "No image descriptor detected - invalid file";

  case D_GIF_ERR_NO_COLOR_MAP:
    return "No global or local color map found";

  case D_GIF_ERR_WRONG_RECORD:
    return "Wrong record type detected - invalid file?";

  case D_GIF_ERR_DATA_TOO_BIG:
    return "Data in file too big for image";

  case D_GIF_ERR_NOT_ENOUGH_MEM:
    return "Out of memory";

  case D_GIF_ERR_CLOSE_FAILED:
    return "Close failed";

  case D_GIF_ERR_NOT_READABLE:
    return "File not opened for read";

  case D_GIF_ERR_IMAGE_DEFECT:
    return "Defective image";

  case D_GIF_ERR_EOF_TOO_SOON:
    return "Unexpected EOF - invalid file";

  default:
    return NULL;
  }
#endif
}

/*
=item gif_push_error(code)

Utility function that takes the current GIF error code, converts it to
an error message and pushes it on the error stack.

=cut
*/

static void
gif_push_error(int code) {
  const char *msg = gif_error_msg(code);
  if (msg)
    i_push_error(code, msg);
  else
    i_push_errorf(code, "Unknown GIF error %d", code);
}

/*
=head1 AUTHOR

Arnar M. Hrafnkelsson, addi@umich.edu

Tony Cook <tonyc@cpan.org>

=head1 SEE ALSO

perl(1), Imager(3)

=cut

*/
