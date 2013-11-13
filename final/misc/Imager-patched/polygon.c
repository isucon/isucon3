#include "imager.h"
#include "draw.h"
#include "log.h"
#include "imrender.h"
#include "imageri.h"

#define IMTRUNC(x) ((int)((x)*16))

#define coarse(x) ((x)/16)
#define fine(x)   ((x)%16)

/*#define DEBUG_POLY*/
#ifdef DEBUG_POLY
#define POLY_DEB(x) x
#else
#define POLY_DEB(x)
#endif


typedef i_img_dim pcord;

typedef struct {
  int n;
  pcord x,y;
} p_point;

typedef struct {
  int n;
  pcord x1,y1;
  pcord x2,y2;
  pcord miny,maxy;
  pcord minx,maxx;
  int updown; /* -1 means down, 0 vertical, 1 up */
} p_line;

typedef struct {
  int n;
  double x;
} p_slice;

typedef struct {
  int *line;		/* temporary buffer for scanline */
  i_img_dim linelen;	/* length of scanline */
} ss_scanline;

static
int
p_compy(const p_point *p1, const p_point *p2) {
  if (p1->y > p2->y) return 1;
  if (p1->y < p2->y) return -1;
  return 0;
}

static
int
p_compx(const p_slice *p1, const p_slice *p2) {
  if (p1->x > p2->x) return 1;
  if (p1->x < p2->x) return -1;
  return 0;
}

/* Change this to int? and round right goddamn it! */

static
double
p_eval_aty(p_line *l, pcord y) {
  int t;
  t=l->y2-l->y1;
  if (t) return ( (y-l->y1)*l->x2 + (l->y2-y)*l->x1 )/t;
  return (l->x1+l->x2)/2.0;
}

static
double
p_eval_atx(p_line *l, pcord x) {
  int t;
  t = l->x2-l->x1;
  if (t) return ( (x-l->x1)*l->y2 + (l->x2-x)*l->y1 )/t;
  return (l->y1+l->y2)/2.0;
}

static
p_line *
line_set_new(const double *x, const double *y, int l) {
  int i;
  p_line *lset = mymalloc(sizeof(p_line) * l);

  for(i=0; i<l; i++) {
    lset[i].n=i;
    lset[i].x1 = IMTRUNC(x[i]);
    lset[i].y1 = IMTRUNC(y[i]);
    lset[i].x2 = IMTRUNC(x[(i+1)%l]);
    lset[i].y2 = IMTRUNC(y[(i+1)%l]);
    lset[i].miny=i_min(lset[i].y1,lset[i].y2);
    lset[i].maxy=i_max(lset[i].y1,lset[i].y2);
    lset[i].minx=i_min(lset[i].x1,lset[i].x2);
    lset[i].maxx=i_max(lset[i].x1,lset[i].x2);
  }
  return lset;
}

static
p_point *
point_set_new(const double *x, const double *y, int l) {
  int i;
  p_point *pset = mymalloc(sizeof(p_point) * l);
  
  for(i=0; i<l; i++) {
    pset[i].n=i;
    pset[i].x=IMTRUNC(x[i]);
    pset[i].y=IMTRUNC(y[i]);
  }
  return pset;
}

static
void
ss_scanline_reset(ss_scanline *ss) {
  memset(ss->line, 0, sizeof(int) * ss->linelen);
}

static
void
ss_scanline_init(ss_scanline *ss, i_img_dim linelen, int linepairs) {
  ss->line    = mymalloc( sizeof(int) * linelen );
  ss->linelen = linelen;
  ss_scanline_reset(ss);
}

static
void
ss_scanline_exorcise(ss_scanline *ss) {
  myfree(ss->line);
}
  
		     


/* returns the number of matches */

static
int
lines_in_interval(p_line *lset, int l, p_slice *tllist, pcord minc, pcord maxc) {
  int k;
  int count = 0;
  for(k=0; k<l; k++) {
    if (lset[k].maxy > minc && lset[k].miny < maxc) {
      if (lset[k].miny == lset[k].maxy) {
	POLY_DEB( printf(" HORIZONTAL - skipped\n") );
      } else {
	tllist[count].x=p_eval_aty(&lset[k],(minc+maxc)/2.0 );
	tllist[count].n=k;
	count++;
      }
    }
  }
  return count;
}

/* marks the up variable for all lines in a slice */

static
void
mark_updown_slices(p_line *lset, p_slice *tllist, int count) {
  p_line *l, *r;
  int k;
  for(k=0; k<count; k+=2) {
    l = lset + tllist[k].n;

    if (l->y1 == l->y2) {
      mm_log((1, "mark_updown_slices: horizontal line being marked: internal error!\n"));
      exit(3);
    }

    l->updown = (l->x1 == l->x2) ?
      0 :
      (l->x1 > l->x2)
      ? 
      (l->y1 > l->y2) ? -1 : 1
      : 
      (l->y1 > l->y2) ? 1 : -1;

    POLY_DEB( printf("marking left line %d as %s(%d)\n", l->n,
		     l->updown ?  l->updown == 1 ? "up" : "down" : "vert", l->updown, l->updown)
	      );

    if (k+1 >= count) {
      mm_log((1, "Invalid polygon spec, odd number of line crossings.\n"));
      return;
    }

    r = lset + tllist[k+1].n;
    if (r->y1 == r->y2) {
      mm_log((1, "mark_updown_slices: horizontal line being marked: internal error!\n"));
      exit(3);
    }

    r->updown = (r->x1 == r->x2) ?
      0 :
      (r->x1 > r->x2)
      ? 
      (r->y1 > r->y2) ? -1 : 1
      : 
      (r->y1 > r->y2) ? 1 : -1;
    
    POLY_DEB( printf("marking right line %d as %s(%d)\n", r->n,
		     r->updown ?  r->updown == 1 ? "up" : "down" : "vert", r->updown, r->updown)
	      );
  }
}



static
unsigned char
saturate(int in) {
  if (in>255) { return 255; }
  else if (in>0) return in;
  return 0;
}

typedef void (*scanline_flusher)(i_img *im, ss_scanline *ss, int y, void *ctx);

/* This function must be modified later to do proper blending */

static void
scanline_flush(i_img *im, ss_scanline *ss, int y, void *ctx) {
  int x, ch, tv;
  i_color t;
  i_color *val = (i_color *)ctx;
  POLY_DEB( printf("Flushing line %d\n", y) );
  for(x=0; x<im->xsize; x++) {
    tv = saturate(ss->line[x]);
    i_gpix(im, x, y, &t);
    for(ch=0; ch<im->channels; ch++) 
      t.channel[ch] = tv/255.0 * val->channel[ch] + (1.0-tv/255.0) * t.channel[ch];
    i_ppix(im, x, y, &t);
  }
}



static
int
trap_square(pcord xlen, pcord ylen, double xl, double yl) {
  POLY_DEB( printf("trap_square: %d %d %.2f %.2f\n", xlen, ylen, xl, yl) );
  return xlen*ylen-(xl*yl)/2.0;
}


/* 
   pixel_coverage calculates the 'left side' pixel coverage of a pixel that is
   within the min/max ranges.  The shape always corresponds to a square with some
   sort of a triangle cut from it (which can also yield a triangle).
*/


static
int 
pixel_coverage(p_line *line, pcord minx, pcord maxx, pcord  miny, pcord maxy) {
  double lycross, rycross;
  int l, r;

  POLY_DEB
    (
     printf("    pixel_coverage(..., minx %g, maxx%g, miny %g, maxy %g)\n", 
	    minx/16.0, maxx/16.0, miny/16.0, maxy/16.0)
     );

  if (!line->updown) {
    l = r = 0;
  } else {
    lycross = p_eval_atx(line, minx);
    rycross = p_eval_atx(line, maxx);
    l = lycross <= maxy && lycross >= miny; /* true if it enters through left side */
    r = rycross <= maxy && rycross >= miny; /* true if it enters through left side */
  }
  POLY_DEB(
 	   printf("    %4s(%+d): ", line->updown ?  line->updown == 1 ? "up" : "down" : "vert", line->updown);
	   printf(" (%2d,%2d) [%3d-%3d, %3d-%3d] lycross=%.2f rycross=%.2f", coarse(minx), coarse(miny), minx, maxx, miny, maxy, lycross, rycross);
	   printf(" l=%d r=%d\n", l, r)
	   );
  
  if (l && r) 
    return line->updown == 1 ? 
      (double)(maxx-minx) * (2.0*maxy-lycross-rycross)/2.0  /* up case */
      :
      (double)(maxx-minx) * (lycross+rycross-2*miny)/2.0;  /* down case */
  
  if (!l && !r) return (maxy-miny)*(maxx*2-p_eval_aty(line, miny)-p_eval_aty(line, maxy))/2.0;

  if (l && !r)
    return line->updown == 1 ?
      trap_square(maxx-minx, maxy-miny, p_eval_aty(line, miny)-minx, p_eval_atx(line, minx)-miny) : 
      trap_square(maxx-minx, maxy-miny, p_eval_aty(line, maxy)-minx, maxy-p_eval_atx(line, minx));
  

  if (!l && r) {
    int r = line->updown == 1 ?
      (maxx-p_eval_aty(line, maxy))*(maxy-p_eval_atx(line, maxx))/2.0 : 
      (maxx-p_eval_aty(line, miny))*(p_eval_atx(line, maxx)-miny)/2.0;
    return r;
  }

  return 0; /* silence compiler warning */
}





/* 
   handle the scanline slice in three steps 
   
   1.  Where only the left edge is inside a pixel
   2a. Where both left and right edge are inside a pixel
   2b. Where neither left or right edge are inside a pixel
   3.  Where only the right edge is inside a pixel
*/

static
void
render_slice_scanline(ss_scanline *ss, int y, p_line *l, p_line *r, pcord miny, pcord maxy) {
  
  pcord lminx, lmaxx;	/* left line min/max within y bounds in fine coords */
  pcord rminx, rmaxx;	/* right line min/max within y bounds in fine coords */
  i_img_dim cpix;	/* x-coordinate of current pixel */
  i_img_dim startpix;	/* temporary variable for "start of this interval" */
  i_img_dim stoppix;	/* temporary variable for "end of this interval" */

  /* Find the y bounds of scanline_slice */

  POLY_DEB
    (
     printf("render_slice_scanline(..., y=%d)\n");
     printf("  left  n=%d p1(%.2g, %.2g) p2(%.2g,%.2g) min(%.2g, %.2g) max(%.2g,%.2g) updown(%d)\n",
	    l->n, l->x1/16.0, l->y1/16.0, l->x2/16.0, l->y2/16.0, 
	    l->minx/16.0, l->miny/16.0, l->maxx/16.0, l->maxy/16.0,
	    l->updown);
     printf("  right n=%d p1(%.2g, %.2g) p2(%.2g,%.2g) min(%.2g, %.2g) max(%.2g,%.2g) updown(%d)\n",
	    r->n, r->x1/16.0, r->y1/16.0, r->x2/16.0, r->y2/16.0, 
	    r->minx/16.0, r->miny/16.0, r->maxx/16.0, r->maxy/16.0,
	    r->updown);
     );
  
  lminx = i_min( p_eval_aty(l, maxy), p_eval_aty(l, miny) );
  lmaxx = i_max( p_eval_aty(l, maxy), p_eval_aty(l, miny) );

  rminx = i_min( p_eval_aty(r, maxy), p_eval_aty(r, miny) );
  rmaxx = i_max( p_eval_aty(r, maxy), p_eval_aty(r, miny) );

  startpix = i_max( coarse(lminx), 0 );
  stoppix  = i_min( coarse(rmaxx-1), ss->linelen-1 );

  POLY_DEB(  printf("  miny=%g maxy=%g\n", miny/16.0, maxy/16.0)  );
  
  for(cpix=startpix; cpix<=stoppix; cpix++) {
    int lt = coarse(lmaxx-1) >= cpix;
    int rt = coarse(rminx) <= cpix;
    
    int A, B, C;
    
    POLY_DEB( printf("  (%d,%d) lt=%d rt=%d\n", cpix, y, lt, rt) );

    A = lt ? pixel_coverage(l, cpix*16, cpix*16+16, miny, maxy) : 0;
    B = lt ? 0 : 16*(maxy-miny);
    C = rt ? pixel_coverage(r, cpix*16, cpix*16+16, miny, maxy) : 0;

    POLY_DEB( printf("  A=%d B=%d C=%d\n", A, B, C) );

    ss->line[cpix] += A+B-C;

  }
  POLY_DEB( printf("end render_slice_scanline()\n") );
}

/* Antialiasing polygon algorithm 
   specs:
   1. only nice polygons - no crossovers
   2. 1/16 pixel resolution
   3. full antialiasing ( complete spectrum of blends )
   4. uses hardly any memory
   5. no subsampling phase
   

   Algorithm outline:
   1. Split into vertical intervals.
   2. handle each interval 

   For each interval we must: 
   1. find which lines are in it
   2. order the lines from in increasing x order.
      since we are assuming no crossovers it is sufficent
      to check a single point on each line.
*/

/*
  Definitions:
  
  1. Interval:  A vertical segment in which no lines cross nor end.
  2. Scanline:  A physical line, contains 16 subpixels in the horizontal direction
  3. Slice:     A start stop line pair.
  
 */


static void
i_poly_aa_low(i_img *im, int l, const double *x, const double *y, void *ctx, scanline_flusher flusher) {
  int i ,k;			/* Index variables */
  i_img_dim clc;		/* Lines inside current interval */
  /* initialize to avoid compiler warnings */
  pcord tempy = 0;
  i_img_dim cscl = 0;			/* Current scanline */

  ss_scanline templine;		/* scanline accumulator */
  p_point *pset;		/* List of points in polygon */
  p_line  *lset;		/* List of lines in polygon */
  p_slice *tllist;		/* List of slices */

  mm_log((1, "i_poly_aa(im %p, l %d, x %p, y %p, ctx %p, flusher %p)\n", im, l, x, y, ctx, flusher));

  for(i=0; i<l; i++) {
    mm_log((2, "(%.2f, %.2f)\n", x[i], y[i]));
  }


  POLY_DEB(
	   fflush(stdout);
	   setbuf(stdout, NULL);
	   );

  tllist   = mymalloc(sizeof(p_slice)*l);
  
  ss_scanline_init(&templine, im->xsize, l);

  pset     = point_set_new(x, y, l);
  lset     = line_set_new(x, y, l);


  qsort(pset, l, sizeof(p_point), (int(*)(const void *,const void *))p_compy);
  
  POLY_DEB(
	   for(i=0;i<l;i++) {
	     printf("%d [ %d ] (%d , %d) -> (%d , %d) yspan ( %d , %d )\n",
		    i, lset[i].n, lset[i].x1, lset[i].y1, lset[i].x2, lset[i].y2, lset[i].miny, lset[i].maxy);
	   }
	   printf("MAIN LOOP\n\n");
	   );
  

  /* loop on intervals */
  for(i=0; i<l-1; i++) {
    i_img_dim startscan = i_max( coarse(pset[i].y), 0);
    i_img_dim stopscan = i_min( coarse(pset[i+1].y+15), im->ysize);
    pcord miny, maxy;	/* y bounds in fine coordinates */

    POLY_DEB( pcord cc = (pset[i].y + pset[i+1].y)/2 );

    POLY_DEB(
	     printf("current slice is %d: %d to %d ( cpoint %d ) scanlines %d to %d\n", 
		    i, pset[i].y, pset[i+1].y, cc, startscan, stopscan)
	     );
    
    if (pset[i].y == pset[i+1].y) {
      POLY_DEB( printf("current slice thickness = 0 => skipping\n") );
      continue;
    }

    clc = lines_in_interval(lset, l, tllist, pset[i].y, pset[i+1].y);
    qsort(tllist, clc, sizeof(p_slice), (int(*)(const void *,const void *))p_compx);

    mark_updown_slices(lset, tllist, clc);

    POLY_DEB
      (
       printf("Interval contains %d lines\n", clc);
       for(k=0; k<clc; k++) {
	 int lno = tllist[k].n;
	 p_line *ln = lset+lno;
	 printf("%d:  line #%2d: (%2d, %2d)->(%2d, %2d) (%2d/%2d, %2d/%2d) -> (%2d/%2d, %2d/%2d) alignment=%s\n",
		k, lno, ln->x1, ln->y1, ln->x2, ln->y2, 
		coarse(ln->x1), fine(ln->x1), 
		coarse(ln->y1), fine(ln->y1), 
		coarse(ln->x2), fine(ln->x2), 
		coarse(ln->y2), fine(ln->y2),
		ln->updown == 0 ? "vert" : ln->updown == 1 ? "up" : "down");
	   
       }
       );
    maxy = im->ysize * 16;
    miny = 0;
    for (k = 0; k < clc; ++k) {
      p_line const * line = lset + tllist[k].n;
      if (line->miny > miny)
	miny = line->miny;
      if (line->maxy < maxy)
	maxy = line->maxy;
      POLY_DEB( printf(" line miny %g maxy %g\n", line->miny/16.0, line->maxy/16.0) );
    }
    POLY_DEB( printf("miny %g maxy %g\n", miny/16.0, maxy/16.0) );

    for(cscl=startscan; cscl<stopscan; cscl++) {
      pcord scan_miny = i_max(miny, cscl * 16);
      pcord scan_maxy = i_min(maxy, (cscl + 1 ) * 16);
      
      tempy = i_min(cscl*16+16, pset[i+1].y);
      POLY_DEB( printf("evaluating scan line %d \n", cscl) );
      for(k=0; k<clc-1; k+=2) {
	POLY_DEB( printf("evaluating slice %d\n", k) );
	render_slice_scanline(&templine, cscl, lset+tllist[k].n, lset+tllist[k+1].n, scan_miny, scan_maxy);
      }
      if (16*coarse(tempy) == tempy) {
	POLY_DEB( printf("flushing scan line %d\n", cscl) );
	flusher(im, &templine, cscl, ctx);
	ss_scanline_reset(&templine);
      }
      /*
	else {
	scanline_flush(im, &templine, cscl, val);
	ss_scanline_reset(&templine);
	return 0;
	}
      */
    }
  } /* Intervals */
  if (16*coarse(tempy) != tempy) 
    flusher(im, &templine, cscl-1, ctx);

  ss_scanline_exorcise(&templine);
  myfree(pset);
  myfree(lset);
  myfree(tllist);
  
} /* Function */

int
i_poly_aa(i_img *im, int l, const double *x, const double *y, const i_color *val) {
  i_color c = *val;
  i_poly_aa_low(im, l, x, y, &c, scanline_flush);
  return 1;
}

struct poly_render_state {
  i_render render;
  i_fill_t *fill;
  unsigned char *cover;
};

static void
scanline_flush_render(i_img *im, ss_scanline *ss, int y, void *ctx) {
  i_img_dim x;
  i_img_dim left, right;
  struct poly_render_state *state = (struct poly_render_state *)ctx;

  left = 0;
  while (left < im->xsize && ss->line[left] <= 0)
    ++left;
  if (left < im->xsize) {
    right = im->xsize;
    /* since going from the left found something, moving from the 
       right should */
    while (/* right > left && */ ss->line[right-1] <= 0) 
      --right;
    
    /* convert to the format the render interface wants */
    for (x = left; x < right; ++x) {
      state->cover[x-left] = saturate(ss->line[x]);
    }
    i_render_fill(&state->render, left, y, right-left, state->cover, 
		  state->fill);
  }
}

int
i_poly_aa_cfill(i_img *im, int l, const double *x, const double *y, 
		i_fill_t *fill) {
  struct poly_render_state ctx;

  i_render_init(&ctx.render, im, im->xsize);
  ctx.fill = fill;
  ctx.cover = mymalloc(im->xsize);
  i_poly_aa_low(im, l, x, y, &ctx, scanline_flush_render);
  myfree(ctx.cover);
  i_render_done(&ctx.render);
  return 1;
}
