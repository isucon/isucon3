#include "regmach.h"
#include <float.h>
#include "imageri.h"

/*#define DEBUG*/
#ifdef DEBUG
#define DBG(x) printf x
#else
#define DBG(x) 
#endif

static float MAX_EXP_ARG; /* = log(DBL_MAX); */


/* these functions currently assume RGB images - there seems to be some 
   support for other color spaces, but I can't tell how you find what 
   space an image is using.

   HSV conversions from pages 401-403 "Procedural Elements for Computer 
   Graphics", 1985, ISBN 0-07-053534-5.  The algorithm presents to produce
   an HSV color calculates all components at once - I don't, so I've 
   simiplified the algorithm to avoid unnecessary calculation (any errors 
   (of which I had a few ;) are mine).
*/

/* returns the value (brightness) of color from 0 to 1 */
static double hsv_value(i_color color) {
  return i_max(i_max(color.rgb.r, color.rgb.g), color.rgb.b) / 255.0;
}

/* returns the hue (color) of color from 0 to 360 */
static double hsv_hue(i_color color) {
  int val;
  int temp;
  temp = i_min(i_min(color.rgb.r, color.rgb.g), color.rgb.b);
  val = i_max(color.rgb.r, i_max(color.rgb.g, color.rgb.b));
  if (val == 0 || val==temp) {
    return 0;
  }
  else {
    double cr = (val - color.rgb.r) / (double)(val - temp);
    double cg = (val - color.rgb.g) / (double)(val - temp);
    double cb = (val - color.rgb.b) / (double)(val - temp);
    double hue;
    if (color.rgb.r == val) {
      hue = cb-cg;
    }
    else if (color.rgb.g == val) {
      hue = 2.0 + cr-cb;
    }
    else { /* if (blue == val) */
      hue = 4.0 + cg - cr;
    }
    hue *= 60.0; /* to degrees */
    if (hue < 0) 
      hue += 360;

    return hue;
  }
}

/* return the saturation of color from 0 to 1 */
static double hsv_sat(i_color color) {
  int value = i_max(i_max(color.rgb.r, color.rgb.g), color.rgb.b);
  if (value == 0) {
    return 0;
  }
  else {
    int temp = i_min(i_min(color.rgb.r, color.rgb.g), color.rgb.b);
    return (value - temp) / (double)value;
  }
}

static i_color make_hsv(double hue, double sat, double val, int alpha) {
  int i;
  i_color c;
  for( i=0; i< MAXCHANNELS; i++) c.channel[i]=0;
  DBG(("hsv=%f %f %f\n", hue, sat, val));
  if (sat <= 0) { /* handle -ve in case someone supplies a bad value */
    /* should this be * 256? */
    c.rgb.r = c.rgb.g = c.rgb.b = 255 * val;
  }
  else {
    int i, m, n, k, v;
    double f;
    
    if (val < 0) val = 0;
    if (val > 1) val = 1;
    if (sat > 1) sat = 1;

    /* I want to handle -360 <= hue < 720 so that the caller can
       fiddle with colour 
    */
    if (hue >= 360)
      hue -= 360;
    else if (hue < 0) 
      hue += 360;
    hue /= 60;
    i = hue; /* floor */
    f = hue - i;
    val *= 255; 
    m = val * (1.0 - sat);
    n = val * (1.0 - sat * f);
    k = val * (1.0 - sat * (1 - f));
    v = val;
    switch (i) {
    case 0:
      c.rgb.r = v; c.rgb.g = k; c.rgb.b = m;
      break;
    case 1:
      c.rgb.r = n; c.rgb.g = v; c.rgb.b = m;
      break;
    case 2:
      c.rgb.r = m; c.rgb.g = v; c.rgb.b = k;
      break;
    case 3:
      c.rgb.r = m; c.rgb.g = n; c.rgb.b = v;
      break;
    case 4:
      c.rgb.r = k; c.rgb.g = m; c.rgb.b = v;
      break;
    case 5:
      c.rgb.r = v; c.rgb.g = m; c.rgb.b = n;
      break;
    }
  }
  c.rgba.a = alpha;

  return c;
}

static i_color make_rgb(int r, int g, int b, int a) {
  i_color c;
  if (r < 0)
    r = 0;
  if (r > 255)
    r = 255;
  c.rgb.r = r;
  if (g < 0)
    g = 0;
  if (g > 255)
    g = 255;
  c.rgb.g = g;
  if (b < 0)
    b = 0;
  if (b > 255)
    b = 255;
  c.rgb.b = b;

  c.rgba.a = a;

  return c;
}

/* greatly simplifies the code */
#define nout n_regs[codes->rout]
#define na n_regs[codes->ra]
#define nb n_regs[codes->rb]
#define nc n_regs[codes->rc]
#define nd n_regs[codes->rd]
#define cout c_regs[codes->rout]
#define ca c_regs[codes->ra]
#define cb c_regs[codes->rb]
#define cc c_regs[codes->rc]
#define cd c_regs[codes->rd]

/* this is a pretty poor epsilon used for loosening up equality comparisons
   It isn't currently used for inequalities 
*/

#define n_epsilon(x, y) (fabs(x)+fabs(y))*0.001
static i_color bcol = {{ 0 }};

i_color i_rm_run(struct rm_op codes[], size_t code_count, 
	       double n_regs[],  size_t n_regs_count,
	       i_color c_regs[], size_t c_regs_count,
	       i_img *images[],  size_t image_count) {
  double dx, dy;
  struct rm_op *codes_base = codes;
  size_t count_base = code_count;

  DBG(("rm_run(%p, %d)\n", codes, code_count));
  while (code_count) {
    DBG((" rm_code %d\n", codes->code));
    switch (codes->code) {
    case rbc_add:
      nout = na + nb;
      break;
      
    case rbc_subtract:
      nout = na - nb;
      break;
      
    case rbc_mult:
      nout = na * nb;
      break;
      
    case rbc_div:
      if (fabs(nb) < 1e-10)
	nout = 1e10;
      else
	nout = na / nb;
      break;
      
    case rbc_mod:
      if (fabs(nb) > 1e-10) {
	nout = fmod(na, nb);
      }
      else {
	nout = 0; /* close enough ;) */
      }
      break;

    case rbc_pow:
      nout = pow(na, nb);
      break;

    case rbc_uminus:
      nout = -na;
      break;

    case rbc_multp:
      cout = make_rgb(ca.rgb.r * nb, ca.rgb.g * nb, ca.rgb.b * nb, 255);
      break;

    case rbc_addp:
      cout = make_rgb(ca.rgb.r + cb.rgb.r, ca.rgb.g + cb.rgb.g, 
		      ca.rgb.b + cb.rgb.b, 255);
      break;

    case rbc_subtractp:
      cout = make_rgb(ca.rgb.r - cb.rgb.r, ca.rgb.g - cb.rgb.g, 
		      ca.rgb.b - cb.rgb.b, 255);
      break;

    case rbc_sin:
      nout = sin(na);
      break;

    case rbc_cos:
      nout = cos(na);
      break;

    case rbc_atan2:
      nout = atan2(na, nb);
      break;

    case rbc_sqrt:
      nout = sqrt(na);
      break;

    case rbc_distance:
      dx = na-nc;
      dy = nb-nd;
      nout = sqrt(dx*dx+dy*dy);
      break;

    case rbc_getp1:
      i_gpix(images[0], na, nb, c_regs+codes->rout);
      if (images[0]->channels < 4) cout.rgba.a = 255;
      break;

    case rbc_getp2:
      i_gpix(images[1], na, nb, c_regs+codes->rout);
      if (images[1]->channels < 4) cout.rgba.a = 255;
      break;

    case rbc_getp3:
      i_gpix(images[2], na, nb, c_regs+codes->rout);
      if (images[2]->channels < 4) cout.rgba.a = 255;
      break;

    case rbc_value:
      nout = hsv_value(ca);
      break;

    case rbc_hue:
      nout = hsv_hue(ca);
      break;

    case rbc_sat:
      nout = hsv_sat(ca);
      break;
      
    case rbc_hsv:
      cout = make_hsv(na, nb, nc, 255);
      break;

    case rbc_hsva:
      cout = make_hsv(na, nb, nc, nd);
      break;

    case rbc_red:
      nout = ca.rgb.r;
      break;

    case rbc_green:
      nout = ca.rgb.g;
      break;

    case rbc_blue:
      nout = ca.rgb.b;
      break;

    case rbc_alpha:
      nout = ca.rgba.a;
      break;

    case rbc_rgb:
      cout = make_rgb(na, nb, nc, 255);
      break;

    case rbc_rgba:
      cout = make_rgb(na, nb, nc, nd);
      break;

    case rbc_int:
      nout = (int)(na);
      break;

    case rbc_if:
      nout = na ? nb : nc;
      break;

    case rbc_ifp:
      cout = na ? cb : cc;
      break;

    case rbc_le:
      nout = na <= nb + n_epsilon(na,nb);
      break;

    case rbc_lt:
      nout = na < nb;
      break;

    case rbc_ge:
      nout = na >= nb - n_epsilon(na,nb);
      break;

    case rbc_gt:
      nout = na > nb;
      break;

    case rbc_eq:
      nout = fabs(na-nb) <= n_epsilon(na,nb);
      break;

    case rbc_ne:
      nout = fabs(na-nb) > n_epsilon(na,nb);
      break;

    case rbc_and:
      nout = na && nb;
      break;
 
    case rbc_or:
      nout = na || nb;
      break;

    case rbc_not:
      nout = !na;
      break;

    case rbc_abs:
      nout = fabs(na);
      break;

    case rbc_ret:
      return ca;
      break;

    case rbc_jump:
      /* yes, order is important here */
      code_count = count_base - codes->ra;
      codes = codes_base + codes->ra;
      continue;
    
    case rbc_jumpz:
      if (!na) {	
	/* yes, order is important here */
	code_count = count_base - codes->rb;
	codes = codes_base + codes->rb;
	continue;
      }
      break;

    case rbc_jumpnz:
      if (na) {
	/* yes, order is important here */
	code_count = count_base - codes->rb;
	codes = codes_base + codes->rb;
	continue;
      }
      break;

    case rbc_set:
      nout = na;
      break;

    case rbc_setp:
      cout = ca;
      break;

    case rbc_log:
      if (na > 0) {
	nout = log(na);
      }
      else {
	nout = DBL_MAX;
      }
      break;

    case rbc_exp:
      if (!MAX_EXP_ARG) MAX_EXP_ARG = log(DBL_MAX);
      if (na <= MAX_EXP_ARG) {
	nout = exp(na);
      }
      else {
	nout = DBL_MAX;
      }
      break;

    case rbc_print:
      nout = na;
      printf("r%d is %g\n", codes->ra, na);
      break;

    case rbc_det:
      nout = na*nd-nb*nc;
      break;

    default:
      /*croak("bad opcode"); */
      printf("bad op %d\n", codes->code);
      return bcol;
    }
    --code_count;
    ++codes;
  }
  return bcol;
  /* croak("no return opcode"); */
}
