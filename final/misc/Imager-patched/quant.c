/* quant.c - provides general image quantization
   currently only used by gif.c, but maybe we'll support producing 
   8-bit (or bigger indexed) png files at some point
*/
#include "imager.h"
#include "imageri.h"

static void makemap_webmap(i_quantize *);
static void makemap_addi(i_quantize *, i_img **imgs, int count);
static void makemap_mediancut(i_quantize *, i_img **imgs, int count);
static void makemap_mono(i_quantize *);
static void makemap_gray(i_quantize *, int step);

static int makemap_palette(i_quantize *, i_img **imgs, int count);

static
void
setcol(i_color *cl,unsigned char r,unsigned char g,unsigned char b,unsigned char a) {
  cl->rgba.r=r;
  cl->rgba.g=g;
  cl->rgba.b=b;
  cl->rgba.a=a;
}



/* make a colour map overwrites mc_existing/mc_count in quant Note
   that i_makemap will be called once for each image if mc_perimage is
   set and the format support multiple colour maps per image.

   This means we don't need any special processing at this level to
   handle multiple colour maps.
*/

/*
=item i_quant_makemap(C<quant>, C<imgs>, C<count>)

=category Image quantization

Analyzes the C<count> images in C<imgs> according to the rules in
C<quant> to build a color map (optimal or not depending on
C<< quant->make_colors >>).

=cut
*/

void
i_quant_makemap(i_quantize *quant, i_img **imgs, int count) {

  if (quant->translate == pt_giflib) {
    /* giflib does it's own color table generation */
    /* previously we used giflib's quantizer, but it didn't handle multiple
       images, which made it hard to build a global color map
       We've implemented our own median cut code so we can ignore 
       the giflib version */
    makemap_mediancut(quant, imgs, count);
    return;
  }

  switch (quant->make_colors & mc_mask) {
  case mc_none:
    /* use user's specified map */
    break;
  case mc_web_map:
    makemap_webmap(quant);
    break;

  case mc_median_cut:
    makemap_mediancut(quant, imgs, count);
    break;

  case mc_mono:
    makemap_mono(quant);
    break;

  case mc_gray:
    makemap_gray(quant, 1);
    break;

  case mc_gray4:
    makemap_gray(quant, 85);
    break;

  case mc_gray16:
    makemap_gray(quant, 17);
    break;

  case mc_addi:
  default:
    makemap_addi(quant, imgs, count);
    break;
  }
}

static void translate_closest(i_quantize *, i_img *, i_palidx *);
static void translate_errdiff(i_quantize *, i_img *, i_palidx *);
static void translate_addi(i_quantize *, i_img *, i_palidx *);

/*
=item i_quant_translate(C<quant>, C<img>)

=category Image quantization

Quantize the image given the palette in C<quant>.

On success returns a pointer to a memory block of C<< img->xsize *
img->ysize >> C<i_palidx> entries.

On failure returns NULL.

You should call myfree() on the returned block when you're done with
it.

This function will fail if the supplied palette contains no colors.

=cut
*/
i_palidx *
i_quant_translate(i_quantize *quant, i_img *img) {
  i_palidx *result;
  size_t bytes;

  mm_log((1, "quant_translate(quant %p, img %p)\n", quant, img));

  /* there must be at least one color in the paletted (though even that
     isn't very useful */
  if (quant->mc_count == 0) {
    i_push_error(0, "no colors available for translation");
    return NULL;
  }

  bytes = img->xsize * img->ysize;
  if (bytes / img->ysize != img->xsize) {
    i_push_error(0, "integer overflow calculating memory allocation");
    return NULL;
  }
  result = mymalloc(bytes);

  switch (quant->translate) {
  case pt_closest:
  case pt_giflib:
    translate_closest(quant, img, result);
    break;
    
  case pt_errdiff:
    translate_errdiff(quant, img, result);
    break;
    
  case pt_perturb:
  default:
    translate_addi(quant, img, result);
    break;
  }
  
  return result;
}

static void translate_closest(i_quantize *quant, i_img *img, i_palidx *out) {
  quant->perturb = 0;
  translate_addi(quant, img, out);
}

#define PWR2(x) ((x)*(x))

typedef int (*cmpfunc)(const void*, const void*);

typedef struct {
  unsigned char r,g,b;
  char fixed;
  char used;
  int dr,dg,db;
  int cdist;
  int mcount;
} cvec;

typedef struct {
  int cnt;
  int vec[256];
} hashbox;

typedef struct {
  int boxnum;
  int pixcnt;
  int cand;
  int pdc;
} pbox;

static void prescan(i_img **im,int count, int cnum, cvec *clr, i_sample_t *line);
static void reorder(pbox prescan[512]);
static int pboxcmp(const pbox *a,const pbox *b);
static void boxcenter(int box,cvec *cv);
static float frandn(void);
static void boxrand(int box,cvec *cv);
static void bbox(int box,int *r0,int *r1,int *g0,int *g1,int *b0,int *b1);
static void cr_hashindex(cvec clr[256],int cnum,hashbox hb[512]);
static int mindist(int boxnum,cvec *cv);
static int maxdist(int boxnum,cvec *cv);

/* Some of the simpler functions are kept here to aid the compiler -
   maybe some of them will be inlined. */

static int
pixbox(i_color *ic) { return ((ic->channel[0] & 224)<<1)+ ((ic->channel[1]&224)>>2) + ((ic->channel[2] &224) >> 5); }

static int
pixbox_ch(i_sample_t *chans) { return ((chans[0] & 224)<<1)+ ((chans[1]&224)>>2) + ((chans[2] &224) >> 5); }

static unsigned char
g_sat(int in) {
  if (in>255) { return 255; }
  else if (in>0) return in;
  return 0;
}

static
float
frand(void) {
  return rand()/(RAND_MAX+1.0);
}

#ifdef NOTEF
static
int
eucl_d(cvec* cv,i_color *cl) { return PWR2(cv->r-cl->channel[0])+PWR2(cv->g-cl->channel[1])+PWR2(cv->b-cl->channel[2]); }
#endif

static
int
eucl_d_ch(cvec* cv,i_sample_t *chans) { 
  return PWR2(cv->r - chans[0]) + PWR2(cv->g - chans[1]) 
    + PWR2(cv->b - chans[2]);
}

static int
ceucl_d(i_color *c1, i_color *c2) {
return PWR2(c1->channel[0]-c2->channel[0])
  +PWR2(c1->channel[1]-c2->channel[1])
  +PWR2(c1->channel[2]-c2->channel[2]);
}

static const int
gray_samples[] = { 0, 0, 0 };

/* 

This quantization algorithm and implementation routines are by Arnar
M. Hrafnkelson. In case any new ideas are here they are mine since
this was written from scratch.

The algorithm uses local means in the following way:

   For each point in the colormap we find which image points
   have that point as it's closest point. We calculate the mean
   of those points and in the next iteration it will be the new
   entry in the colormap.
   
In order to speed this process up (i.e. nearest neighbor problem) We
divied the r,g,b space up in equally large 512 boxes.  The boxes are
numbered from 0 to 511. Their numbering is so that for a given vector
it is known that it belongs to the box who is formed by concatenating the
3 most significant bits from each component of the RGB triplet.

For each box we find the list of points from the colormap who might be
closest to any given point within the box.  The exact solution
involves finding the Voronoi map (or the dual the Delauny
triangulation) and has many issues including numerical stability.

So we use this approximation:

1. Find which point has the shortest maximum distance to the box.
2. Find all points that have a shorter minimum distance than that to the box

This is a very simple task and is not computationally heavy if one
takes into account that the minimum distances from a pixel to a box is
always found by checking if it's inside the box or is closest to some
side or a corner. Finding the maximum distance is also either a side
or a corner.

This approach results 2-3 times more than the actual points needed but
is still a good gain over the complete space.  Usually when one has a
256 Colorcolor map a search over 30 is often obtained.

A bit of an enhancement to this approach is to keep a seperate list
for each side of the cube, but this will require even more memory. 

             Arnar M. Hrafnkelsson (addi@umich.edu);

*/
/*
  Extracted from gifquant.c, removed dependencies on gif_lib, 
  and added support for multiple images.
  starting from 1nov2000 by TonyC <tony@develop-help.com>.

*/

static void
makemap_addi(i_quantize *quant, i_img **imgs, int count) {
  cvec *clr;
  int cnum, i, bst_idx=0, ld, cd, iter, currhb, img_num;
  i_img_dim x, y;
  i_sample_t *val;
  float dlt, accerr;
  hashbox *hb;
  i_mempool mp;
  i_img_dim maxwidth = 0;
  i_sample_t *line;
  const int *sample_indices;

  mm_log((1, "makemap_addi(quant %p { mc_count=%d, mc_colors=%p }, imgs %p, count %d)\n", 
          quant, quant->mc_count, quant->mc_colors, imgs, count));

  if (makemap_palette(quant, imgs, count))
    return;
         
  i_mempool_init(&mp);

  clr = i_mempool_alloc(&mp, sizeof(cvec) * quant->mc_size);
  hb = i_mempool_alloc(&mp, sizeof(hashbox) * 512);
  for (i=0; i < quant->mc_count; ++i) {
    clr[i].r = quant->mc_colors[i].rgb.r;
    clr[i].g = quant->mc_colors[i].rgb.g;
    clr[i].b = quant->mc_colors[i].rgb.b;
    clr[i].fixed = 1;
    clr[i].mcount = 0;
  }
  /* mymalloc doesn't clear memory, so I think we need this */
  for (; i < quant->mc_size; ++i) {
    /*clr[i].r = clr[i].g = clr[i].b = 0;*/
    clr[i].dr = 0;
    clr[i].dg = 0;
    clr[i].db = 0;
    clr[i].fixed = 0;
    clr[i].mcount = 0;
  }
  cnum = quant->mc_size;
  dlt = 1;

  for (img_num = 0; img_num < count; ++img_num) {
    if (imgs[img_num]->xsize > maxwidth)
      maxwidth = imgs[img_num]->xsize;
  }
  line = i_mempool_alloc(&mp, 3 * maxwidth * sizeof(*line));

  prescan(imgs, count, cnum, clr, line);
  cr_hashindex(clr, cnum, hb);

  for(iter=0;iter<3;iter++) {
    accerr=0.0;
    
    for (img_num = 0; img_num < count; ++img_num) {
      i_img *im = imgs[img_num];
      sample_indices = im->channels >= 3 ? NULL : gray_samples;
      for(y=0;y<im->ysize;y++) {
        i_gsamp(im, 0, im->xsize, y, line, sample_indices, 3);
        val = line;
        for(x=0;x<im->xsize;x++) {
          ld=196608;
          /*i_gpix(im,x,y,&val);*/
          currhb=pixbox_ch(val);
          /*      printf("box = %d \n",currhb); */
          for(i=0;i<hb[currhb].cnt;i++) { 
            /*	printf("comparing: pix (%d,%d,%d) vec (%d,%d,%d)\n",val.channel[0],val.channel[1],val.channel[2],clr[hb[currhb].vec[i]].r,clr[hb[currhb].vec[i]].g,clr[hb[currhb].vec[i]].b); */
            
            cd=eucl_d_ch(&clr[hb[currhb].vec[i]],val);
            if (cd<ld) {
              ld=cd;     /* shortest distance yet */
              bst_idx=hb[currhb].vec[i]; /* index of closest vector  yet */
            }
          }
          
          clr[bst_idx].mcount++;
          accerr+=(ld);
          clr[bst_idx].dr+=val[0];
          clr[bst_idx].dg+=val[1];
          clr[bst_idx].db+=val[2];
          
          val += 3; /* next 3 samples (next pixel) */
        }
      }
    }
    
    for(i=0;i<cnum;i++) 
      if (clr[i].mcount) { 
        clr[i].dr/=clr[i].mcount; 
        clr[i].dg/=clr[i].mcount; 
        clr[i].db/=clr[i].mcount; 
      }
      
    /*    for(i=0;i<cnum;i++) printf("vec(%d)=(%d,%d,%d) dest=(%d,%d,%d) matchcount=%d\n",
          i,clr[i].r,clr[i].g,clr[i].b,clr[i].dr,clr[i].dg,clr[i].db,clr[i].mcount); */
    
    /*    printf("total error: %.2f\n",sqrt(accerr)); */
    
    for(i=0;i<cnum;i++) {
      if (clr[i].fixed) continue; /* skip reserved colors */
      
      if (clr[i].mcount) {
        clr[i].used = 1;
        clr[i].r=clr[i].r*(1-dlt)+dlt*clr[i].dr;
        clr[i].g=clr[i].g*(1-dlt)+dlt*clr[i].dg;
        clr[i].b=clr[i].b*(1-dlt)+dlt*clr[i].db;
      } else {
        /* let's try something else */
        clr[i].used = 0;
        clr[i].r=rand();
        clr[i].g=rand();
        clr[i].b=rand();
      }
      
      clr[i].dr=0;
      clr[i].dg=0;
      clr[i].db=0;
      clr[i].mcount=0;
    }
    cr_hashindex(clr,cnum,hb);
  }


#ifdef NOTEF
  for(i=0;i<cnum;i++) { 
    cd=eucl_d(&clr[i],&val);
    if (cd<ld) {
      ld=cd;
      bst_idx=i;
    }
  }
#endif

  /* if defined, we only include colours with an mcount or that were
     supplied in the fixed palette, giving us a smaller output palette */
#define ONLY_USE_USED
#ifdef ONLY_USE_USED
  /* transfer the colors back */
  quant->mc_count = 0;
  for (i = 0; i < cnum; ++i) {
    if (clr[i].fixed || clr[i].used) {
      /*printf("Adding %d (%d,%d,%d)\n", i, clr[i].r, clr[i].g, clr[i].b);*/
      quant->mc_colors[quant->mc_count].rgb.r = clr[i].r;
      quant->mc_colors[quant->mc_count].rgb.g = clr[i].g;
      quant->mc_colors[quant->mc_count].rgb.b = clr[i].b;
      ++quant->mc_count;
    }
  }
#else
  /* transfer the colors back */
  for (i = 0; i < cnum; ++i) {
    quant->mc_colors[i].rgb.r = clr[i].r;
    quant->mc_colors[i].rgb.g = clr[i].g;
    quant->mc_colors[i].rgb.b = clr[i].b;
  }
  quant->mc_count = cnum;
#endif

#if 0
  mm_log((1, "makemap_addi returns - quant.mc_count = %d\n", quant->mc_count));
  for (i = 0; i < quant->mc_count; ++i)
    mm_log((5, "  map entry %d: (%d, %d, %d)\n", i, clr[i].r, clr[i].g, clr[i].b));
#endif

  i_mempool_destroy(&mp);

  mm_log((1, "makemap_addi() - %d colors\n", quant->mc_count));
}

typedef struct {
  i_sample_t rgb[3];
  int count;
} quant_color_entry;

#define MEDIAN_CUT_COLORS 32768

#define MED_CUT_INDEX(c) ((((c).rgb.r & 0xF8) << 7) | \
        (((c).rgb.g & 0xF8) << 2) | (((c).rgb.b & 0xF8) >> 3))

#define MED_CUT_GRAY_INDEX(c) ((((c).rgb.r & 0xF8) << 7) | \
        (((c).rgb.r & 0xF8) << 2) | (((c).rgb.r & 0xF8) >> 3))

/* scale these to cover the whole range */
#define MED_CUT_RED(index) ((((index) & 0x7C00) >> 10) * 255 / 31)
#define MED_CUT_GREEN(index) ((((index) & 0x3E0) >> 5) * 255 / 31)
#define MED_CUT_BLUE(index) (((index) & 0x1F) * 255 / 31)

typedef struct {
  i_sample_t min[3]; /* minimum for each channel */
  i_sample_t max[3]; /* maximum for each channel */
  i_sample_t width[3]; /* width for each channel */
  int start, size;   /* beginning and size of the partition */
  i_img_dim pixels; /* number of pixels represented by this partition */
} medcut_partition;

/*
=item calc_part(part, colors)

Calculates the new color limits for the given partition.

Giflib assumes that the limits for the non-split channels stay the
same, but this strikes me as incorrect, especially if the colors tend
to be color ramps.

Of course this could be optimized by not recalculating the channel we
just sorted on, but it's not worth the effort right now.

=cut
*/
static void calc_part(medcut_partition *part, quant_color_entry *colors) {
  int i, ch;
  
  for (ch = 0; ch < 3; ++ch) {
    part->min[ch] = 255;
    part->max[ch] = 0;
  }
  for (i = part->start; i < part->start + part->size; ++i) {
    for (ch = 0; ch < 3; ++ch) {
      if (part->min[ch] > colors[i].rgb[ch])
        part->min[ch] = colors[i].rgb[ch];
      if (part->max[ch] < colors[i].rgb[ch])
        part->max[ch] = colors[i].rgb[ch];
    }
  }
  for (ch = 0; ch < 3; ++ch) {
    part->width[ch] = part->max[ch] - part->min[ch];
  }
}

/* simple functions to sort by each channel - we could use a global, but 
   that would be bad */

static int
color_sort_red(void const *left, void const *right) {
  return ((quant_color_entry *)left)->rgb[0] - ((quant_color_entry *)right)->rgb[0];
}

static int
color_sort_green(void const *left, void const *right) {
  return ((quant_color_entry *)left)->rgb[1] - ((quant_color_entry *)right)->rgb[1];
}

static int
color_sort_blue(void const *left, void const *right) {
  return ((quant_color_entry *)left)->rgb[2] - ((quant_color_entry *)right)->rgb[2];
}

static int (*sorters[])(void const *, void const *) =
{
  color_sort_red,
  color_sort_green,
  color_sort_blue,
};

static void
makemap_mediancut(i_quantize *quant, i_img **imgs, int count) {
  quant_color_entry *colors;
  i_mempool mp;
  int imgn, i, ch;
  i_img_dim x, y, max_width;
  i_color *line;
  int color_count;
  i_img_dim total_pixels;
  medcut_partition *parts;
  int part_num;
  int in, out;
  /* number of channels we search for the best channel to partition
     this isn't terribly efficient, but it should work */
  int chan_count; 

  mm_log((1, "makemap_mediancut(quant %p { mc_count=%d, mc_colors=%p }, imgs %p, count %d)\n", 
          quant, quant->mc_count, quant->mc_colors, imgs, count));

  if (makemap_palette(quant, imgs, count))
    return;

  i_mempool_init(&mp);

  colors = i_mempool_alloc(&mp, sizeof(*colors) * MEDIAN_CUT_COLORS);
  for (i = 0; i < MEDIAN_CUT_COLORS; ++i) {
    colors[i].rgb[0] = MED_CUT_RED(i);
    colors[i].rgb[1] = MED_CUT_GREEN(i);
    colors[i].rgb[2] = MED_CUT_BLUE(i);
    colors[i].count = 0;
  }

  max_width = -1;
  for (imgn = 0; imgn < count; ++imgn) {
    if (imgs[imgn]->xsize > max_width)
      max_width = imgs[imgn]->xsize;
  }
  line = i_mempool_alloc(&mp, sizeof(i_color) * max_width);

  /* build the stats */
  total_pixels = 0;
  chan_count = 1; /* assume we just have grayscale */
  for (imgn = 0; imgn < count; ++imgn) {
    total_pixels += imgs[imgn]->xsize * imgs[imgn]->ysize;
    for (y = 0; y < imgs[imgn]->ysize; ++y) {
      i_glin(imgs[imgn], 0, imgs[imgn]->xsize, y, line);
      if (imgs[imgn]->channels > 2) {
        chan_count = 3;
        for (x = 0; x < imgs[imgn]->xsize; ++x) {
          ++colors[MED_CUT_INDEX(line[x])].count;
        }
      }
      else {
        /* a gray-scale image, just use the first channel */
        for (x = 0; x < imgs[imgn]->xsize; ++x) {
          ++colors[MED_CUT_GRAY_INDEX(line[x])].count;
        }
      }
    }
  }

  /* eliminate the empty colors */
  out = 0;
  for (in = 0; in < MEDIAN_CUT_COLORS; ++in) {
    if (colors[in].count) {
      colors[out++] = colors[in];
    }
  }
  /*printf("out %d\n", out);

  for (i = 0; i < out; ++i) {
    if (colors[i].count) {
      printf("%d: (%d,%d,%d) -> %d\n", i, colors[i].rgb[0], colors[i].rgb[1], 
             colors[i].rgb[2], colors[i].count);
    }
    }*/

  if (out < quant->mc_size) {
    /* just copy them into the color table */
    for (i = 0; i < out; ++i) {
      for (ch = 0; ch < 3; ++ch) {
        quant->mc_colors[i].channel[ch] = colors[i].rgb[ch];
      }
    }
    quant->mc_count = out;
  }
  else {
    /* build the starting partition */
    parts = i_mempool_alloc(&mp, sizeof(*parts) * quant->mc_size);
    parts[0].start = 0;
    parts[0].size = out;
    parts[0].pixels = total_pixels;
    calc_part(parts, colors);
    color_count = 1;
    
    while (color_count < quant->mc_size) {
      /* initialized to avoid compiler warnings */
      int max_index = 0, max_ch = 0; /* index/channel with biggest spread */
      int max_size;
      medcut_partition *workpart;
      int cum_total;
      int half;
      
      /* find the partition with the most biggest span with more than 
         one color */
      max_size = -1;
      for (i = 0; i < color_count; ++i) {
        for (ch = 0; ch < chan_count; ++ch) {
          if (parts[i].width[ch] > max_size 
              && parts[i].size > 1) {
            max_index = i;
            max_ch = ch;
            max_size = parts[i].width[ch];
          }
        }
      }
      
      /* nothing else we can split */
      if (max_size == -1)
        break;
      
      workpart = parts+max_index;
      /*printf("splitting partition %d (pixels %ld, start %d, size %d)\n", max_index, workpart->pixels, workpart->start, workpart->size);*/
      qsort(colors + workpart->start, workpart->size, sizeof(*colors),
            sorters[max_ch]);
      
      /* find the median or something like it we need to make sure both
         sides of the split have at least one color in them, so we don't
         test at the first or last entry */
      i = workpart->start;
      cum_total = colors[i].count;
      ++i;
      half = workpart->pixels / 2;
      while (i < workpart->start + workpart->size - 1
             && cum_total < half) {
        cum_total += colors[i++].count;
      }
      /*printf("Split at %d to make %d (half %ld, cumtotal %ld)\n", i, color_count, half, cum_total);*/
      
      /* found the spot to split */
      parts[color_count].start = i;
      parts[color_count].size = workpart->start + workpart->size - i;
      workpart->size = i - workpart->start;
      parts[color_count].pixels = workpart->pixels - cum_total;
      workpart->pixels = cum_total;
      
      /* recalculate the limits */
      calc_part(workpart, colors);
      calc_part(parts+color_count, colors);
      ++color_count;
    }
    
    /* fill in the color table - since we could still have partitions
       that have more than one color, we need to average the colors */
    for (part_num = 0; part_num < color_count; ++part_num) {
      long sums[3];
      medcut_partition *workpart;
      
      workpart = parts+part_num;
      for (ch = 0; ch < 3; ++ch)
        sums[ch] = 0;
      
      for (i = workpart->start; i < workpart->start + workpart->size; ++i) {
        for (ch = 0; ch < 3; ++ch) {
          sums[ch] += colors[i].rgb[ch] * colors[i].count;
        }
      }
      for (ch = 0; ch < 3; ++ch) {
        quant->mc_colors[part_num].channel[ch] = sums[ch] / workpart->pixels;
      }
    }
    quant->mc_count = color_count;
  }
  /*printf("out %d colors\n", quant->mc_count);*/
  i_mempool_destroy(&mp);

  mm_log((1, "makemap_mediancut() - %d colors\n", quant->mc_count));
}

static void
makemap_mono(i_quantize *quant) {
  quant->mc_colors[0].rgba.r = 0;
  quant->mc_colors[0].rgba.g = 0;
  quant->mc_colors[0].rgba.b = 0;
  quant->mc_colors[0].rgba.a = 255;
  quant->mc_colors[1].rgba.r = 255;
  quant->mc_colors[1].rgba.g = 255;
  quant->mc_colors[1].rgba.b = 255;
  quant->mc_colors[1].rgba.a = 255;
  quant->mc_count = 2;
}

static void
makemap_gray(i_quantize *quant, int step) {
  int gray = 0;
  int i = 0;

  while (gray < 256) {
    setcol(quant->mc_colors+i, gray, gray, gray, 255);
    ++i;
    gray += step;
  }
  quant->mc_count = i;
}

static void
makemap_webmap(i_quantize *quant) {
  int r, g, b;

  int i = 0;
  for (r = 0; r < 256; r+=0x33)
    for (g = 0; g < 256; g+=0x33)
      for (b = 0; b < 256; b += 0x33)
	setcol(quant->mc_colors+i++, r, g, b, 255);
  quant->mc_count = i;
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
=item makemap_palette(quant, imgs, count)

Tests if all the given images are paletted and have a common palette,
if they do it builds that palette.

A possible improvement might be to eliminate unused colors in the
images palettes.

=cut
*/

static int
makemap_palette(i_quantize *quant, i_img **imgs, int count) {
  int size = quant->mc_count;
  int i;
  int imgn;
  char used[256];
  int col_count;

  mm_log((1, "makemap_palette(quant %p { mc_count=%d, mc_colors=%p }, imgs %p, count %d)\n", 
          quant, quant->mc_count, quant->mc_colors, imgs, count));
  /* we try to build a common palette here, if we can manage that, then
     that's the palette we use */
  for (imgn = 0; imgn < count; ++imgn) {
    int eliminate_unused;
    if (imgs[imgn]->type != i_palette_type) {
      mm_log((1, "makemap_palette() -> 0 (non-palette image)\n"));
      return 0;
    }

    if (!i_tags_get_int(&imgs[imgn]->tags, "gif_eliminate_unused", 0, 
                        &eliminate_unused)) {
      eliminate_unused = 1;
    }

    if (eliminate_unused) {
      i_palidx *line = mymalloc(sizeof(i_palidx) * imgs[imgn]->xsize);
      i_img_dim x, y;
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
        if (in_palette(&c, quant, size) < 0) {
          if (size < quant->mc_size) {
            quant->mc_colors[size++] = c;
          }
          else {
	    mm_log((1, "makemap_palette() -> 0 (too many colors)\n"));
            return 0;
          }
        }
      }
    }
  }

  mm_log((1, "makemap_palette() -> 1 (%d total colors)\n", size));
  quant->mc_count = size;

  return 1;
}

#define pboxjump 32

/* Define one of the following 4 symbols to choose a colour search method
   The idea is to try these out, including benchmarking, to see which
   is fastest in a good spread of circumstances.
   I'd expect IM_CFLINSEARCH to be fastest for very small palettes, and
   IM_CFHASHBOX for large images with large palettes.

   Some other possibilities include:
    - search over entries sorted by luminance

   Initially I was planning on testing using the macros and then
   integrating the code directly into each function, but this means if
   we find a bug at a late stage we will need to update N copies of
   the same code.  Also, keeping the code in the macros means that the
   code in the translation functions is much more to the point,
   there's no distracting colour search code to remove attention from
   what makes _this_ translation function different.  It may be
   advisable to move the setup code into functions at some point, but
   it should be possible to do this fairly transparently.

   If IM_CF_COPTS is defined then CFLAGS must have an appropriate 
   definition.

   Each option needs to define 4 macros:
    CF_VARS - variables to define in the function
    CF_SETUP - code to setup for the colour search, eg. allocating and
      initializing lookup tables
    CF_FIND - code that looks for the color in val and puts the best 
      matching index in bst_idx
    CF_CLEANUP - code to clean up, eg. releasing memory
*/
#ifndef IM_CF_COPTS
/*#define IM_CFLINSEARCH*/
#define IM_CFHASHBOX
/*#define IM_CFSORTCHAN*/
/*#define IM_CFRAND2DIST*/
#endif

/* return true if the color map contains only grays */
static int
is_gray_map(const i_quantize *quant) {
  int i;

  for (i = 0; i < quant->mc_count; ++i) {
    if (quant->mc_colors[i].rgb.r != quant->mc_colors[i].rgb.g
	|| quant->mc_colors[i].rgb.r != quant->mc_colors[i].rgb.b) {
      mm_log((1, "  not a gray map\n"));
      return 0;
    }
  }

  mm_log((1, "  is a gray map\n"));
  return 1;
}

#ifdef IM_CFHASHBOX

/* The original version I wrote for this used the sort.
   If this is defined then we use a sort to extract the indices for 
   the hashbox */
#define HB_SORT

/* assume i is available */
#define CF_VARS hashbox *hb = mymalloc(sizeof(hashbox) * 512); \
               int currhb;  \
               long ld, cd

#ifdef HB_SORT

static long *gdists; /* qsort is annoying */
/* int might be smaller than long, so we need to do a real compare 
   rather than a subtraction*/
static int distcomp(void const *a, void const *b) {
  long ra = gdists[*(int const *)a];
  long rb = gdists[*(int const *)b];
  if (ra < rb)
    return -1;
  else if (ra > rb)
    return 1;
  else
    return 0;
}

#endif

/* for each hashbox build a list of colours that are in the hb or is closer
   than other colours
   This is pretty involved.  The original gifquant generated the hashbox
   as part of it's normal processing, but since the map generation is now 
   separated from the translation we need to do this on the spot.
   Any optimizations, even if they don't produce perfect results would be
   welcome.
 */
static void hbsetup(i_quantize *quant, hashbox *hb) {
  long *dists, mind, maxd;
  int cr, cb, cg, hbnum, i;
  i_color cenc;
#ifdef HB_SORT
  int *indices = mymalloc(quant->mc_count * sizeof(int)); 
#endif

  dists = mymalloc(quant->mc_count * sizeof(long)); 
  for (cr = 0; cr < 8; ++cr) { 
    for (cg = 0; cg < 8; ++cg) { 
      for (cb = 0; cb < 8; ++cb) { 
        /* centre of the hashbox */ 
        cenc.channel[0] = cr*pboxjump+pboxjump/2; 
        cenc.channel[1] = cg*pboxjump+pboxjump/2; 
        cenc.channel[2] = cb*pboxjump+pboxjump/2; 
        hbnum = pixbox(&cenc); 
        hb[hbnum].cnt = 0; 
        /* order indices in the order of distance from the hashbox */ 
        for (i = 0; i < quant->mc_count; ++i) { 
#ifdef HB_SORT
          indices[i] = i; 
#endif
          dists[i] = ceucl_d(&cenc, quant->mc_colors+i); 
        } 
#ifdef HB_SORT
	/* it should be possible to do this without a sort 
	   but so far I'm too lazy */
        gdists = dists; 
        qsort(indices, quant->mc_count, sizeof(int), distcomp); 
        /* any colors that can match are within mind+diagonal size of 
	   a hashbox */ 
        mind = dists[indices[0]]; 
        i = 0; 
	maxd = (sqrt(mind)+pboxjump)*(sqrt(mind)+pboxjump);
        while (i < quant->mc_count && dists[indices[i]] < maxd) { 
          hb[hbnum].vec[hb[hbnum].cnt++] = indices[i++]; 
        } 
#else
	/* work out the minimum */
	mind = 256*256*3;
	for (i = 0; i < quant->mc_count; ++i) {
	  if (dists[i] < mind) mind = dists[i];
	}
	/* transfer any colours that might be closest to a colour in 
	   this hashbox */
	maxd = (sqrt(mind)+pboxjump)*(sqrt(mind)+pboxjump);
	for (i = 0; i < quant->mc_count; ++i) {
	  if (dists[i] < maxd)
	    hb[hbnum].vec[hb[hbnum].cnt++] = i;
	}
#endif
      } 
    } 
  }
#ifdef HB_SORT
  myfree(indices); 
#endif
  myfree(dists) ;
}
#define CF_SETUP hbsetup(quant, hb)

#define CF_FIND \
  currhb = pixbox(&val); \
  ld = 196608; \
  for (i = 0; i < hb[currhb].cnt; ++i) { \
    cd = ceucl_d(quant->mc_colors+hb[currhb].vec[i], &val); \
    if (cd < ld) { ld = cd; bst_idx = hb[currhb].vec[i]; } \
  }

#define CF_CLEANUP myfree(hb)
  
#endif

#ifdef IM_CFLINSEARCH
/* as simple as it gets */
#define CF_VARS long ld, cd
#define CF_SETUP /* none needed */
#define CF_FIND \
   ld = 196608; \
   for (i = 0; i < quant->mc_count; ++i) { \
     cd = ceucl_d(quant->mc_colors+i, &val); \
     if (cd < ld) { ld = cd; bst_idx = i; } \
   }
#define CF_CLEANUP
#endif

#ifdef IM_CFSORTCHAN
static int gsortchan;
static i_quantize *gquant;
static int chansort(void const *a, void const *b) {
  return gquant->mc_colors[*(int const *)a].channel[gsortchan] -
    gquant->mc_colors[*(int const *)b].channel[gsortchan];
}
#define CF_VARS int *indices, sortchan, diff; \
                long ld, cd; \
                int vindex[256] /* where to find value i of chan */

static void chansetup(i_img *img, i_quantize *quant, int *csortchan, 
		      int *vindex, int **cindices) {
  int *indices, sortchan, chan, i, chval;
  int chanmins[MAXCHANNELS], chanmaxs[MAXCHANNELS], maxrange;

  /* find the channel with the maximum range */ 
  /* the maximum stddev would probably be better */
  for (chan = 0; chan < img->channels; ++chan) { 
    chanmins[chan] = 256; chanmaxs[chan] = 0; 
    for (i = 0; i < quant->mc_count; ++i) { 
      if (quant->mc_colors[i].channel[chan] < chanmins[chan]) 
	chanmins[chan] = quant->mc_colors[i].channel[chan]; 
      if (quant->mc_colors[i].channel[chan] > chanmaxs[chan]) 
	chanmaxs[chan] = quant->mc_colors[i].channel[chan]; 
    } 
  } 
  maxrange = -1; 
  for (chan = 0; chan < img->channels; ++chan) { 
    if (chanmaxs[chan]-chanmins[chan] > maxrange) { 
      maxrange = chanmaxs[chan]-chanmins[chan]; 
      sortchan = chan; 
    } 
  } 
  indices = mymalloc(quant->mc_count * sizeof(int)) ;
  for (i = 0; i < quant->mc_count; ++i) { 
    indices[i] = i; 
  } 
  gsortchan = sortchan; 
  gquant = quant; 
  qsort(indices, quant->mc_count, sizeof(int), chansort) ;
  /* now a lookup table to find entries faster */ 
  for (chval=0, i=0; i < quant->mc_count; ++i) { 
    while (chval < 256 && 
	   chval < quant->mc_colors[indices[i]].channel[sortchan]) { 
      vindex[chval++] = i; 
    } 
  } 
  while (chval < 256) { 
    vindex[chval++] = quant->mc_count-1; 
  }
  *csortchan = sortchan;
  *cindices = indices;
}

#define CF_SETUP \
  chansetup(img, quant, &sortchan, vindex, &indices)

int chanfind(i_color val, i_quantize *quant, int *indices, int *vindex, 
	     int sortchan) {
  int i, bst_idx, diff, maxdiff;
  long ld, cd;

  i = vindex[val.channel[sortchan]];
  bst_idx = indices[i];
  ld = 196608;
  diff = 0;
  maxdiff = quant->mc_count;
  while (diff < maxdiff) {
    if (i+diff < quant->mc_count) {
      cd = ceucl_d(&val, quant->mc_colors+indices[i+diff]); 
      if (cd < ld) {
	bst_idx = indices[i+diff];
	ld = cd;
	maxdiff = sqrt(ld);
      }
    }
    if (i-diff >= 0) {
      cd = ceucl_d(&val, quant->mc_colors+indices[i-diff]); 
      if (cd < ld) {
	bst_idx = indices[i-diff];
	ld = cd;
	maxdiff = sqrt(ld);
      }
    }
    ++diff;
  }

  return bst_idx;
}

#define CF_FIND \
  bst_idx = chanfind(val, quant, indices, vindex, sortchan)
  

#define CF_CLEANUP myfree(indices)

#endif

#ifdef IM_CFRAND2DIST

/* This is based on a method described by Addi in the #imager channel 
   on the 28/2/2001.  I was about 1am Sydney time at the time, so I 
   wasn't at my most cogent.  Well, that's my excuse :)

<TonyC> what I have at the moment is: hashboxes, with optimum hash box
filling; simple linear search; and a lookup in the widest channel
(currently the channel with the maximum range)
<Addi> There is one more way that might be simple to implement.
<Addi> You want to hear?
<TonyC> what's that?
<purl> somebody said that was not true
<Addi> For each of the colors in the palette start by creating a
sorted list of the form:
<Addi> [distance, color]
<Addi> Where they are sorted by distance.
<TonyC> distance to where?
<Addi> Where the elements in the lists are the distances and colors of
the other colors in the palette
<TonyC> ok
<Addi> So if you are at color 0
<Addi> ok - now to search for the closest color when you are creating
the final image is done like this:
<Addi> a) pick a random color from the palette
<Addi> b) calculate the distance to it
<Addi> c) only check the vectors that are within double the distance
in the list of the color you picked from the palette.
<Addi> Does that seem logical?
<Addi> Lets imagine that we only have grayscale to make an example:
<Addi> Our palette has 1 4 10 20 as colors.
<Addi> And we want to quantize the color 11
<Addi> lets say we picked 10 randomly
<Addi> the double distance is 2
<Addi> since abs(10-11)*2 is 2
<Addi> And the list at vector 10 is this:
<Addi> [0, 10], [6 4], [9, 1], [10, 20]
<Addi> so we look at the first one (but not the second one since 6 is
at a greater distance than 2.
<Addi> Any of that make sense?
<TonyC> yes, though are you suggesting another random jump to one of
the colours with the possible choices? or an exhaustive search?
<Addi> TonyC: It's possible to come up with a recursive/iterative 
enhancement but this is the 'basic' version.
<Addi> Which would do an iterative search.
<Addi> You can come up with conditions where it pays to switch to a new one.
<Addi> And the 'random' start can be switched over to a small tree.
<Addi> So you would have a little index at the start.
<Addi> to get you into the general direction
<Addi> Perhaps just an 8 split.
<Addi> that is - split each dimension in half.
<TonyC> yep
<TonyC> I get the idea
<Addi> But this would seem to be a good approach in our case since we 
usually have few codevectors.
<Addi> So we only need 256*256 entries in a table.
<Addi> We could even only index some of them that were deemed as good 
candidates.
<TonyC> I was considering adding paletted output support for PNG and 
TIFF at some point, which support 16-bit palettes
<Addi> ohh.
<Addi> 'darn' ;)


*/


typedef struct i_dists {
  int index;
  long dist;
} i_dists;

#define CF_VARS \
    i_dists *dists;

static int dists_sort(void const *a, void const *b) {
  return ((i_dists *)a)->dist - ((i_dists *)b)->dist;
}

static void rand2dist_setup(i_quantize *quant, i_dists **cdists) {
  i_dists *dists = 
    mymalloc(sizeof(i_dists)*quant->mc_count*quant->mc_count);
  int i, j;
  long cd;
  for (i = 0; i < quant->mc_count; ++i) {
    i_dists *ldists = dists + quant->mc_count * i;
    i_color val = quant->mc_colors[i];
    for (j = 0; j < quant->mc_count; ++j) {
      ldists[j].index = j;
      ldists[j].dist = ceucl_d(&val, quant->mc_colors+j);
    }
    qsort(ldists, quant->mc_count, sizeof(i_dists), dists_sort);
  }
  *cdists = dists;
}

#define CF_SETUP \
		bst_idx = rand() % quant->mc_count; \
		rand2dist_setup(quant, &dists)

static int rand2dist_find(i_color val, i_quantize *quant, i_dists *dists, int index) {
  i_dists *cdists;
  long cd, ld;
  long maxld;
  int i;
  int bst_idx;

  cdists = dists + index * quant->mc_count;
  ld = 3 * 256 * 256;
  maxld = 8 * ceucl_d(&val, quant->mc_colors+index);
  for (i = 0; i < quant->mc_count && cdists[i].dist <= maxld; ++i) {
    cd = ceucl_d(&val, quant->mc_colors+cdists[i].index);
    if (cd < ld) {
      bst_idx = cdists[i].index;
      ld = cd;
    }
  }
  return bst_idx;
}

#define CF_FIND bst_idx = rand2dist_find(val, quant, dists, bst_idx)

#define CF_CLEANUP myfree(dists)


#endif

static void translate_addi(i_quantize *quant, i_img *img, i_palidx *out) {
  i_img_dim x, y, k;
  int i, bst_idx = 0;
  i_color val;
  int pixdev = quant->perturb;
  CF_VARS;

  CF_SETUP;

  if (img->channels >= 3) {
    if (pixdev) {
      k=0;
      for(y=0;y<img->ysize;y++) for(x=0;x<img->xsize;x++) {
        i_gpix(img,x,y,&val);
        val.channel[0]=g_sat(val.channel[0]+(int)(pixdev*frandn()));
        val.channel[1]=g_sat(val.channel[1]+(int)(pixdev*frandn()));
        val.channel[2]=g_sat(val.channel[2]+(int)(pixdev*frandn()));
        CF_FIND;
        out[k++]=bst_idx;
      }
    } else {
      k=0;
      for(y=0;y<img->ysize;y++) for(x=0;x<img->xsize;x++) {
        i_gpix(img,x,y,&val);
        CF_FIND;
        out[k++]=bst_idx;
      }
    }
  }
  else {
    if (pixdev) {
      k=0;
      for(y=0;y<img->ysize;y++) for(x=0;x<img->xsize;x++) {
        i_gpix(img,x,y,&val);
        val.channel[1] = val.channel[2] =
          val.channel[0]=g_sat(val.channel[0]+(int)(pixdev*frandn()));
        CF_FIND;
        out[k++]=bst_idx;
      }
    } else {
      k=0;
      for(y=0;y<img->ysize;y++) for(x=0;x<img->xsize;x++) {
        i_gpix(img,x,y,&val);
        val.channel[1] = val.channel[2] = val.channel[0];
        CF_FIND;
        out[k++]=bst_idx;
      }
    }
  }
  CF_CLEANUP;
}

static int floyd_map[] =
{
  0, 0, 7,
  3, 5, 1
};

static int jarvis_map[] =
{
  0, 0, 0, 7, 5,
  3, 5, 7, 5, 3,
  1, 3, 5, 3, 1
};

static int stucki_map[] =
{
  0, 0, 0, 8, 4,
  2, 4, 8, 4, 2,
  1, 2, 4, 2, 1
};

struct errdiff_map {
  int *map;
  int width, height, orig;
};

static struct errdiff_map maps[] =
{
  { floyd_map, 3, 2, 1 },
  { jarvis_map, 5, 3, 2 },
  { stucki_map, 5, 3, 2 },
};

typedef struct errdiff_tag {
  int r, g, b;
} errdiff_t;

/* perform an error diffusion dither */
static
void
translate_errdiff(i_quantize *quant, i_img *img, i_palidx *out) {
  int *map;
  int mapw, maph, mapo;
  int i;
  errdiff_t *err;
  i_img_dim errw;
  int difftotal;
  i_img_dim x, y, dx, dy;
  int bst_idx = 0;
  int is_gray = is_gray_map(quant);
  CF_VARS;

  if ((quant->errdiff & ed_mask) == ed_custom) {
    map = quant->ed_map;
    mapw = quant->ed_width;
    maph = quant->ed_height;
    mapo = quant->ed_orig;
  }
  else {
    int index = quant->errdiff & ed_mask;
    if (index >= ed_custom) index = ed_floyd;
    map = maps[index].map;
    mapw = maps[index].width;
    maph = maps[index].height;
    mapo = maps[index].orig;
  }
  
  errw = img->xsize+mapw;
  err = mymalloc(sizeof(*err) * maph * errw);
  /*errp = err+mapo;*/
  memset(err, 0, sizeof(*err) * maph * errw);
  
  difftotal = 0;
  for (i = 0; i < maph * mapw; ++i)
    difftotal += map[i];
  /*printf("map:\n");
 for (dy = 0; dy < maph; ++dy) {
   for (dx = 0; dx < mapw; ++dx) {
     printf("%2d", map[dx+dy*mapw]);
   }
   putchar('\n');
   }*/

  CF_SETUP;

  for (y = 0; y < img->ysize; ++y) {
    for (x = 0; x < img->xsize; ++x) {
      i_color val;
      errdiff_t perr;
      i_gpix(img, x, y, &val);
      if (img->channels < 3) {
        val.channel[1] = val.channel[2] = val.channel[0];
      }
      else if (is_gray) {
	int gray = 0.5 + color_to_grey(&val);
	val.channel[0] = val.channel[1] = val.channel[2] = gray;
      }
      perr = err[x+mapo];
      perr.r = perr.r < 0 ? -((-perr.r)/difftotal) : perr.r/difftotal;
      perr.g = perr.g < 0 ? -((-perr.g)/difftotal) : perr.g/difftotal;
      perr.b = perr.b < 0 ? -((-perr.b)/difftotal) : perr.b/difftotal;
      /*printf("x %3d y %3d in(%3d, %3d, %3d) di(%4d,%4d,%4d)\n", x, y, val.channel[0], val.channel[1], val.channel[2], perr.r, perr.g, perr.b);*/
      val.channel[0] = g_sat(val.channel[0]-perr.r);
      val.channel[1] = g_sat(val.channel[1]-perr.g);
      val.channel[2] = g_sat(val.channel[2]-perr.b);
      CF_FIND;
      /* save error */
      perr.r = quant->mc_colors[bst_idx].channel[0] - val.channel[0];
      perr.g = quant->mc_colors[bst_idx].channel[1] - val.channel[1];
      perr.b = quant->mc_colors[bst_idx].channel[2] - val.channel[2];
      /*printf("           out(%3d, %3d, %3d) er(%4d, %4d, %4d)\n", quant->mc_colors[bst_idx].channel[0], quant->mc_colors[bst_idx].channel[1], quant->mc_colors[bst_idx].channel[2], perr.r, perr.g, perr.b);*/
      for (dx = 0; dx < mapw; ++dx) {
	for (dy = 0; dy < maph; ++dy) {
	  err[x+dx+dy*errw].r += perr.r * map[dx+mapw*dy];
	  err[x+dx+dy*errw].g += perr.g * map[dx+mapw*dy];
	  err[x+dx+dy*errw].b += perr.b * map[dx+mapw*dy];
	}
      }
      *out++ = bst_idx;
    }
    /* shift up the error matrix */
    for (dy = 0; dy < maph-1; ++dy) {
      memcpy(err+dy*errw, err+(dy+1)*errw, sizeof(*err)*errw);
    }
    memset(err+(maph-1)*errw, 0, sizeof(*err)*errw);
  }
  CF_CLEANUP;
  myfree(err);
}
/* Prescan finds the boxes in the image that have the highest number of colors 
   and that result is used as the initial value for the vectores */


static void prescan(i_img **imgs,int count, int cnum, cvec *clr, i_sample_t *line) {
  int i,k,j;
  i_img_dim x,y;
  i_sample_t *val;
  const int *chans;

  pbox prebox[512];
  for(i=0;i<512;i++) {
    prebox[i].boxnum=i;
    prebox[i].pixcnt=0;
    prebox[i].cand=1;
  }

  /* process each image */
  for (i = 0; i < count; ++i) {
    i_img *im = imgs[i];
    chans = im->channels >= 3 ? NULL : gray_samples;
    for(y=0;y<im->ysize;y++) {
      i_gsamp(im, 0, im->xsize, y, line, chans, 3);
      val = line;
      for(x=0;x<im->xsize;x++) {
        prebox[pixbox_ch(val)].pixcnt++;
      }
    }
  }

  for(i=0;i<512;i++) prebox[i].pdc=prebox[i].pixcnt;
  qsort(prebox,512,sizeof(pbox),(cmpfunc)pboxcmp);

  for(i=0;i<cnum;i++) {
    /*      printf("Color %d\n",i); 
	    for(k=0;k<10;k++) { printf("box=%03d %04d %d %04d \n",prebox[k].boxnum,prebox[k].pixcnt,prebox[k].cand,prebox[k].pdc); } 
	    printf("\n\n"); */
    reorder(prebox);
  }
  
  /*    for(k=0;k<cnum;k++) { printf("box=%03d %04d %d %04d \n",prebox[k].boxnum,prebox[k].pixcnt,prebox[k].cand,prebox[k].pdc); } */
  
  k=0;
  j=1;
  i=0;
  while(i<cnum) {
    /*    printf("prebox[%d].cand=%d\n",k,prebox[k].cand); */
    if (clr[i].fixed) { i++; continue; } /* reserved go to next */
    if (j>=prebox[k].cand) { k++; j=1; } else {
      if (prebox[k].cand == 2) boxcenter(prebox[k].boxnum,&(clr[i]));
      else boxrand(prebox[k].boxnum,&(clr[i]));
      /*      printf("(%d,%d) %d %d -> (%d,%d,%d)\n",k,j,prebox[k].boxnum,prebox[k].pixcnt,clr[i].r,clr[i].g,clr[i].b); */
      j++;
      i++;
    }
  }
}
  

static void reorder(pbox prescan[512]) {
  int nidx;
  pbox c;

  nidx=0;
  c=prescan[0];
  
  c.cand++;
  c.pdc=c.pixcnt/(c.cand*c.cand); 
  /*  c.pdc=c.pixcnt/c.cand; */
  while(c.pdc < prescan[nidx+1].pdc && nidx < 511) {
    prescan[nidx]=prescan[nidx+1];
    nidx++;
  }
  prescan[nidx]=c;
}

static int
pboxcmp(const pbox *a,const pbox *b) {
  if (a->pixcnt > b->pixcnt) return -1;
  if (a->pixcnt < b->pixcnt) return 1;
  return 0;
}

static void
boxcenter(int box,cvec *cv) {
  cv->r=15+((box&448)>>1);
  cv->g=15+((box&56)<<2);
  cv->b=15+((box&7)<<5);
}

static void
bbox(int box,int *r0,int *r1,int *g0,int *g1,int *b0,int *b1) {
  *r0=(box&448)>>1;
  *r1=(*r0)|31;
  *g0=(box&56)<<2;
  *g1=(*g0)|31;
  *b0=(box&7)<<5;
  *b1=(*b0)|31;
}

static void
boxrand(int box,cvec *cv) {
  cv->r=6+(rand()%25)+((box&448)>>1);
  cv->g=6+(rand()%25)+((box&56)<<2);
  cv->b=6+(rand()%25)+((box&7)<<5);
}

static float
frandn(void) {

  float u1,u2,w;
  
  w=1;
  
  while (w >= 1 || w == 0) {
    u1 = 2 * frand() - 1;
    u2 = 2 * frand() - 1;
    w = u1*u1 + u2*u2;
  }
  
  w = sqrt((-2*log(w))/w);
  return u1*w;
}

/* Create hash index */
static
void
cr_hashindex(cvec clr[256],int cnum,hashbox hb[512]) {
  
  int bx,mind,cd,cumcnt,i;
/*  printf("indexing... \n");*/
  
  cumcnt=0;
  for(bx=0; bx<512; bx++) {
    mind=196608;
    for(i=0; i<cnum; i++) { 
      cd = maxdist(bx,&clr[i]);
      if (cd < mind) { mind=cd; } 
    }
    
    hb[bx].cnt=0;
    for(i=0;i<cnum;i++) if (mindist(bx,&clr[i])<mind) hb[bx].vec[hb[bx].cnt++]=i;
    /*printf("box %d -> approx -> %d\n",bx,hb[bx].cnt); */
    /*	statbox(bx,cnum,clr); */
    cumcnt+=hb[bx].cnt;
  }
  
/*  printf("Average search space: %d\n",cumcnt/512); */
}

static int
maxdist(int boxnum,cvec *cv) {
  int r0,r1,g0,g1,b0,b1;
  int r,g,b,mr,mg,mb;

  r=cv->r;
  g=cv->g;
  b=cv->b;
  
  bbox(boxnum,&r0,&r1,&g0,&g1,&b0,&b1);

  mr=i_max(abs(b-b0),abs(b-b1));
  mg=i_max(abs(g-g0),abs(g-g1));
  mb=i_max(abs(r-r0),abs(r-r1));
  
  return PWR2(mr)+PWR2(mg)+PWR2(mb);
}

static int
mindist(int boxnum,cvec *cv) {
  int r0,r1,g0,g1,b0,b1;
  int r,g,b,mr,mg,mb;

  r=cv->r;
  g=cv->g;
  b=cv->b;
  
  bbox(boxnum,&r0,&r1,&g0,&g1,&b0,&b1);

  /*  printf("box %d, (%d,%d,%d)-(%d,%d,%d) vec (%d,%d,%d) ",boxnum,r0,g0,b0,r1,g1,b1,r,g,b); */

  if (r0<=r && r<=r1 && g0<=g && g<=g1 && b0<=b && b<=b1) return 0;

  mr=i_min(abs(b-b0),abs(b-b1));
  mg=i_min(abs(g-g0),abs(g-g1));
  mb=i_min(abs(r-r0),abs(r-r1));
  
  mr=PWR2(mr);
  mg=PWR2(mg);
  mb=PWR2(mb);

  if (r0<=r && r<=r1 && g0<=g && g<=g1) return mb;
  if (r0<=r && r<=r1 && b0<=b && b<=b1) return mg;
  if (b0<=b && b<=b1 && g0<=g && g<=g1) return mr;

  if (r0<=r && r<=r1) return mg+mb;
  if (g0<=g && g<=g1) return mr+mb;
  if (b0<=b && b<=b1) return mg+mr;

  return mr+mg+mb;
}

static void transparent_threshold(i_quantize *, i_palidx *, i_img *, i_palidx);
static void transparent_errdiff(i_quantize *, i_palidx *, i_img *, i_palidx);
static void transparent_ordered(i_quantize *, i_palidx *, i_img *, i_palidx);

/*
=item i_quant_transparent(C<quant>, C<data>, C<img>, C<trans_index>)

=category Image quantization

Dither the alpha channel on C<img> into the palette indexes in
C<data>.  Pixels to be transparent are replaced with C<trans_pixel>.

The method used depends on the tr_* members of C<quant>.

=cut
*/

void 
i_quant_transparent(i_quantize *quant, i_palidx *data, i_img *img,
		       i_palidx trans_index)
{
  switch (quant->transp) {
  case tr_none:
    break;
    
  default:
    quant->tr_threshold = 128;
    /* fall through */
  case tr_threshold:
    transparent_threshold(quant, data, img, trans_index);
    break;
    
  case tr_errdiff:
    transparent_errdiff(quant, data, img, trans_index);
    break;

  case tr_ordered:
    transparent_ordered(quant, data, img, trans_index);
    break;
  }
}

static void
transparent_threshold(i_quantize *quant, i_palidx *data, i_img *img,
		      i_palidx trans_index)
{
  i_img_dim x, y;
  i_sample_t *line = mymalloc(img->xsize * sizeof(i_sample_t));
  int trans_chan = img->channels > 2 ? 3 : 1;
  
  for (y = 0; y < img->ysize; ++y) {
    i_gsamp(img, 0, img->xsize, y, line, &trans_chan, 1);
    for (x = 0; x < img->xsize; ++x) {
      if (line[x] < quant->tr_threshold)
	data[y*img->xsize+x] = trans_index;
    }
  }
  myfree(line);
}

static void
transparent_errdiff(i_quantize *quant, i_palidx *data, i_img *img,
		    i_palidx trans_index)
{
  int *map;
  int index;
  int mapw, maph, mapo;
  int errw, *err, *errp;
  int difftotal, out, error;
  i_img_dim x, y, dx, dy;
  int i;
  i_sample_t *line;
  int trans_chan = img->channels > 2 ? 3 : 1;

  /* no custom map for transparency (yet) */
  index = quant->tr_errdiff & ed_mask;
  if (index >= ed_custom) index = ed_floyd;
  map = maps[index].map;
  mapw = maps[index].width;
  maph = maps[index].height;
  mapo = maps[index].orig;

  errw = img->xsize+mapw-1;
  err = mymalloc(sizeof(*err) * maph * errw);
  errp = err+mapo;
  memset(err, 0, sizeof(*err) * maph * errw);

  line = mymalloc(img->xsize * sizeof(i_sample_t));
  difftotal = 0;
  for (i = 0; i < maph * mapw; ++i)
    difftotal += map[i];
  for (y = 0; y < img->ysize; ++y) {
    i_gsamp(img, 0, img->xsize, y, line, &trans_chan, 1);
    for (x = 0; x < img->xsize; ++x) {
      line[x] = g_sat(line[x]-errp[x]/difftotal);
      if (line[x] < 128) {
	out = 0;
	data[y*img->xsize+x] = trans_index;
      }
      else {
	out = 255;
      }
      error = out - line[x];
      for (dx = 0; dx < mapw; ++dx) {
	for (dy = 0; dy < maph; ++dy) {
	  errp[x+dx-mapo+dy*errw] += error * map[dx+mapw*dy];
	}
      }
    }
    /* shift up the error matrix */
    for (dy = 0; dy < maph-1; ++dy)
      memcpy(err+dy*errw, err+(dy+1)*errw, sizeof(*err)*errw);
    memset(err+(maph-1)*errw, 0, sizeof(*err)*errw);
  }
  myfree(err);
  myfree(line);
}

/* builtin ordered dither maps */
static unsigned char 
orddith_maps[][64] =
{
  { /* random 
       this is purely random - it's pretty awful
     */
     48,  72, 196, 252, 180,  92, 108,  52,
    228, 176,  64,   8, 236,  40,  20, 164,
    120, 128,  84, 116,  24,  28, 172, 220,
     68,   0, 188, 124, 184, 224, 192, 104,
    132, 100, 240, 200, 152, 160, 244,  44,
     96, 204, 144,  16, 140,  56, 232, 216,
    208,   4,  76, 212, 136, 248,  80, 168,
    156,  88,  32, 112, 148,  12,  36,  60,
  },
  {
    /* dot8
       perl spot.perl '($x-3.5)*($x-3.5)+($y-3.5)*($y-3.5)'
     */
    240, 232, 200, 136, 140, 192, 228, 248,
    220, 148, 100,  76,  80, 104, 152, 212,
    180, 116,  56,  32,  36,  60, 120, 176,
    156,  64,  28,   0,   8,  44,  88, 160,
    128,  92,  24,  12,   4,  40,  68, 132,
    184,  96,  48,  20,  16,  52, 108, 188,
    216, 144, 112,  72,  84, 124, 164, 224,
    244, 236, 196, 168, 172, 204, 208, 252,
  },
  { /* dot4
       perl spot.perl \
       'min(dist(1.5, 1.5),dist(5.5,1.5),dist(1.5,5.5),dist(5.5,5.5))'  
    */
    196,  72, 104, 220, 200,  80, 112, 224,
     76,   4,  24, 136,  84,   8,  32, 144,
    108,  28,  52, 168, 116,  36,  56, 176,
    216, 140, 172, 244, 228, 148, 180, 248,
    204,  92, 124, 236, 192,  68,  96, 208,
     88,  12,  44, 156,  64,   0,  16, 128,
    120,  40,  60, 188, 100,  20,  48, 160,
    232, 152, 184, 252, 212, 132, 164, 240,
  },
  { /* hline 
       perl spot.perl '$y-3'
     */
    160, 164, 168, 172, 176, 180, 184, 188,
    128, 132, 136, 140, 144, 148, 152, 156,
     32,  36,  40,  44,  48,  52,  56,  60,
      0,   4,   8,  12,  16,  20,  24,  28,
     64,  68,  72,  76,  80,  84,  88,  92,
     96, 100, 104, 108, 112, 116, 120, 124,
    192, 196, 200, 204, 208, 212, 216, 220,
    224, 228, 232, 236, 240, 244, 248, 252,
  },
  { /* vline 
       perl spot.perl '$x-3'
     */
    180, 100,  40,  12,  44, 104, 184, 232,
    204, 148,  60,  16,  64, 128, 208, 224,
    212, 144,  76,   8,  80, 132, 216, 244,
    160, 112,  68,  20,  84, 108, 172, 236,
    176,  96,  72,  28,  88, 152, 188, 228,
    200, 124,  92,   0,  32, 116, 164, 240,
    168, 120,  36,  24,  48, 136, 192, 248,
    196, 140,  52,   4,  56, 156, 220, 252,
  },
  { /* slashline 
       perl spot.perl '$y+$x-7'  
    */
    248, 232, 224, 192, 140,  92,  52,  28,
    240, 220, 196, 144, 108,  60,  12,  64,
    216, 180, 148, 116,  76,  20,  80, 128,
    204, 152, 104,  44,  16,  72, 100, 160,
    164,  96,  68,  24,  56, 112, 168, 176,
    124,  40,   8,  36,  88, 136, 184, 212,
     84,   4,  32, 120, 156, 188, 228, 236,
      0,  48, 132, 172, 200, 208, 244, 252,
  },
  { /* backline 
       perl spot.perl '$y-$x'
     */
      0,  32, 116, 172, 184, 216, 236, 252,
     56,   8,  72, 132, 136, 200, 228, 240,
    100,  36,  12,  40,  92, 144, 204, 220,
    168, 120,  60,  16,  44,  96, 156, 176,
    180, 164, 112,  48,  28,  52, 128, 148,
    208, 192, 152,  88,  84,  20,  64, 104,
    232, 224, 196, 140, 108,  68,  24,  76,
    248, 244, 212, 188, 160, 124,  80,   4,
  },
  {
    /* tiny
       good for display, bad for print
       hand generated
    */
      0, 128,  32, 192,   8, 136,  40, 200,
    224,  64, 160, 112, 232,  72, 168, 120,
     48, 144,  16, 208,  56, 152,  24, 216,
    176,  96, 240,  80, 184, 104, 248,  88,
     12, 140,  44, 204,   4, 132,  36, 196,
    236,  76, 172, 124, 228,  68, 164, 116,
     60, 156,  28, 220,  52, 148,  20, 212,
    188, 108, 252,  92, 180, 100, 244,  84,
  },
};

static void
transparent_ordered(i_quantize *quant, i_palidx *data, i_img *img,
		    i_palidx trans_index)
{
  unsigned char *spot;
  i_img_dim x, y;
  i_sample_t *line;
  int trans_chan = img->channels > 2 ? 3 : 1;
  if (quant->tr_orddith == od_custom)
    spot = quant->tr_custom;
  else
    spot = orddith_maps[quant->tr_orddith];

  line = mymalloc(img->xsize * sizeof(i_sample_t));
  for (y = 0; y < img->ysize; ++y) {
    i_gsamp(img, 0, img->xsize, y, line, &trans_chan, 1);
    for (x = 0; x < img->xsize; ++x) {
      if (line[x] < spot[(x&7)+(y&7)*8])
	data[x+y*img->xsize] = trans_index;
    }
  }
  myfree(line);
}

