#define IMAGER_NO_CONTEXT
#include "imageri.h"
#include <stdlib.h>

#define OVERLAPPED(start1, end1, start2, end2) \
  (im_max((start1), (start2)) <= im_min((end1), (end2)))

/*
=head1 NAME

hlines.c - implements a "class" for managing sets of horizontal line segments

=head1 SYNOPSIS

  i_int_hlines hlines;
  // just for the specified range of y
  i_int_init_hlines(&hlines, start_y, count_y, start_x, width_x);
  // to cover a whole image
  i_int_init_hlines_img(&hlines, img);
  // add a hline segment, merging into existing
  i_int_hlines_add(&hlines, y, x, width);

  // work over the lines
  for (y = hlines.start; y < hlines.limit; ++y) {
    i_int_hline_entry *entry = hlines.entries[i];
    if (entry) {
      for (i = 0; i < entry->count; ++i) {
        i_int_hline_seg *seg = entry->segs+i;
        // do something on line y for seg->minx to x_limit
      }
    }
  }

  // free it all up
  i_int_hlines_destroy(&hlines);

=head1 DESCRIPTION

Provides a class to manage sets of horizontal line segments.  The
intent is that when drawing shapes where the algorithm used might
cause overlaps we can use this class to resolve the overlaps.

Note that segment lists are intended to remain small, if we end up
with a need for longer lists we should use different structure for the
segment lists.

=over

=item i_int_init_hlines

i_int_init_hlines(&hlines, start_y, count_y, start_x, width_x)

Initializes the structure based on drawing an object within the given
range.  Any x or y values outside the given ranges will be ignored.

=cut

*/

void
i_int_init_hlines(
		  i_int_hlines *hlines, 
		  i_img_dim start_y, 
		  i_img_dim count_y,
		  i_img_dim start_x, 
		  i_img_dim width_x
		  )
{
  size_t bytes = count_y * sizeof(i_int_hline_entry *);

  if (bytes / count_y != sizeof(i_int_hline_entry *)) {
    dIMCTX;
    im_fatal(aIMCTX, 3, "integer overflow calculating memory allocation\n");
  }

  hlines->start_y = start_y;
  hlines->limit_y = start_y + count_y;
  hlines->start_x = start_x;
  hlines->limit_x = start_x + width_x;
  hlines->entries = mymalloc(bytes);
  memset(hlines->entries, 0, bytes);
}

/*
=item i_int_init_hlines_img

i_int_init_hlines_img(img);

Initialize a hlines object as if we could potentially draw anywhere on
the image.

=cut
*/

void
i_int_init_hlines_img(i_int_hlines *hlines, i_img *img)
{
  i_int_init_hlines(hlines, 0, img->ysize, 0, img->xsize);
}

/*
=item i_int_hlines_add

i_int_hlines_add(hlines, y, x, width)

Add to the list, merging with existing entries.

=cut
*/

void
i_int_hlines_add(i_int_hlines *hlines, i_img_dim y, i_img_dim x, i_img_dim width) {
  i_img_dim x_limit = x + width;

  if (width < 0) {
    dIMCTX;
    im_fatal(aIMCTX, 3, "negative width %d passed to i_int_hlines_add\n", width);
  }

  /* just return if out of range */
  if (y < hlines->start_y || y >= hlines->limit_y)
    return;
  
  if (x >= hlines->limit_x || x_limit < hlines->start_x)
    return;

  /* adjust x to our range */
  if (x < hlines->start_x)
    x = hlines->start_x;
  if (x_limit > hlines->limit_x)
    x_limit = hlines->limit_x;

  if (x == x_limit)
    return;

  if (hlines->entries[y - hlines->start_y]) {
    i_int_hline_entry *entry = hlines->entries[y - hlines->start_y];
    i_img_dim i, found = -1;
    
    for (i = 0; i < entry->count; ++i) {
      i_int_hline_seg *seg = entry->segs + i;
      if (OVERLAPPED(x, x_limit, seg->minx, seg->x_limit)) {
	found = i;
	break;
      }
    }
    if (found >= 0) {
      /* ok, we found an overlapping segment, any other overlapping
	 segments need to be merged into the one we found */
      i_int_hline_seg *merge_seg = entry->segs + found;

      /* merge in the segment we found */
      x = im_min(x, merge_seg->minx);
      x_limit = im_max(x_limit, merge_seg->x_limit);

      /* look for other overlapping segments */
      /* this could be a for(), but I'm using continue */
      i = found + 1;
      while (i < entry->count) {
	i_int_hline_seg *seg = entry->segs + i;
	if (OVERLAPPED(x, x_limit, seg->minx, seg->x_limit)) {
	  /* merge this into the current working segment, then
	     delete it by moving the last segment (if this isn't it)
	     into it's place */
	  x = im_min(x, seg->minx);
	  x_limit = im_max(x_limit, seg->x_limit);
	  if (i < entry->count-1) {
	    *seg = entry->segs[entry->count-1];
	    --entry->count;
	    continue;
	  }
	  else {
	    --entry->count;
	    break;
	  }
	}
	++i;
      }

      /* store it back */
      merge_seg->minx = x;
      merge_seg->x_limit = x_limit;
    }
    else {
      i_int_hline_seg *seg;
      /* add a new segment */
      if (entry->count == entry->alloc) {
	/* expand it */
	size_t alloc = entry->alloc * 3 / 2;
	entry = myrealloc(entry, sizeof(i_int_hline_entry) +
			   sizeof(i_int_hline_seg) * (alloc - 1));
	entry->alloc = alloc;
	hlines->entries[y - hlines->start_y] = entry;
      }
      seg = entry->segs + entry->count++;
      seg->minx = x;
      seg->x_limit = x_limit;
    }
  }
  else {
    /* make a new one - start with space for 10 */
    i_int_hline_entry *entry = mymalloc(sizeof(i_int_hline_entry) + 
					sizeof(i_int_hline_seg) * 9);
    entry->alloc = 10;
    entry->count = 1;
    entry->segs[0].minx = x;
    entry->segs[0].x_limit = x_limit;
    hlines->entries[y - hlines->start_y] = entry;
  }
}

/*
=item i_int_hlines_destroy

i_int_hlines_destroy(&hlines)

Releases all memory associated with the structure.

=cut
*/

void
i_int_hlines_destroy(i_int_hlines *hlines) {
  size_t entry_count = hlines->limit_y - hlines->start_y;
  size_t i;
  
  for (i = 0; i < entry_count; ++i) {
    if (hlines->entries[i])
      myfree(hlines->entries[i]);
  }
  myfree(hlines->entries);
}

/*
=item i_int_hlines_fill_color

i_int_hlines_fill(im, hlines, color)

Fill the areas given by hlines with color.

=cut
*/

void
i_int_hlines_fill_color(i_img *im, i_int_hlines *hlines, const i_color *col) {
  i_img_dim y, i, x;

  for (y = hlines->start_y; y < hlines->limit_y; ++y) {
    i_int_hline_entry *entry = hlines->entries[y - hlines->start_y];
    if (entry) {
      for (i = 0; i < entry->count; ++i) {
	i_int_hline_seg *seg = entry->segs + i;
	for (x = seg->minx; x < seg->x_limit; ++x) {
	  i_ppix(im, x, y, col);
	}
      }
    }
  }
}

/*
=item i_int_hlines_fill_fill

i_int_hlines_fill_fill(im, hlines, fill)

=cut
*/
void
i_int_hlines_fill_fill(i_img *im, i_int_hlines *hlines, i_fill_t *fill) {
  i_render r;
  i_img_dim y, i;

  i_render_init(&r, im, im->xsize);

  for (y = hlines->start_y; y < hlines->limit_y; ++y) {
    i_int_hline_entry *entry = hlines->entries[y - hlines->start_y];
    if (entry) {
      for (i = 0; i < entry->count; ++i) {
	i_int_hline_seg *seg = entry->segs + i;
	i_img_dim width = seg->x_limit-seg->minx;
	
	i_render_fill(&r, seg->minx, y, width, NULL, fill);
      }
    }
  }
  i_render_done(&r);
  
#if 1
#else
  if (im->bits == i_8_bits && fill->fill_with_color) {
    i_color *line = mymalloc(sizeof(i_color) * im->xsize);
    i_color *work = NULL;
    if (fill->combine)
      work = mymalloc(sizeof(i_color) * im->xsize);
    for (y = hlines->start_y; y < hlines->limit_y; ++y) {
      i_int_hline_entry *entry = hlines->entries[y - hlines->start_y];
      if (entry) {
	for (i = 0; i < entry->count; ++i) {
	  i_int_hline_seg *seg = entry->segs + i;
	  i_img_dim width = seg->x_limit-seg->minx;

	  if (fill->combine) {
	    i_glin(im, seg->minx, seg->x_limit, y, line);
	    (fill->fill_with_color)(fill, seg->minx, y, width,
				    im->channels, work);
	    (fill->combine)(line, work, im->channels, width);
	  }
	  else {
	    (fill->fill_with_color)(fill, seg->minx, y, width, 
				    im->channels, line);
	  }
	  i_plin(im, seg->minx, seg->x_limit, y, line);
	}
      }
    }
  
    myfree(line);
    if (work)
      myfree(work);
  }
  else {
    i_fcolor *line = mymalloc(sizeof(i_fcolor) * im->xsize);
    i_fcolor *work = NULL;
    if (fill->combinef)
      work = mymalloc(sizeof(i_fcolor) * im->xsize);
    for (y = hlines->start_y; y < hlines->limit_y; ++y) {
      i_int_hline_entry *entry = hlines->entries[y - hlines->start_y];
      if (entry) {
	for (i = 0; i < entry->count; ++i) {
	  i_int_hline_seg *seg = entry->segs + i;
	  i_img_dim width = seg->x_limit-seg->minx;

	  if (fill->combinef) {
	    i_glinf(im, seg->minx, seg->x_limit, y, line);
	    (fill->fill_with_fcolor)(fill, seg->minx, y, width, 
				     im->channels, work);
	    (fill->combinef)(line, work, im->channels, width);
	  }
	  else {
	    (fill->fill_with_fcolor)(fill, seg->minx, y, width, 
				     im->channels, line);
	  }
	  i_plinf(im, seg->minx, seg->x_limit, y, line);
	}
      }
    }
  
    myfree(line);
    if (work)
      myfree(work);
  }
#endif
}

/*
=back

=head1 AUTHOR

Tony Cook <tonyc@cpan.org>

=head1 REVISION

$Revision$

=cut
*/
