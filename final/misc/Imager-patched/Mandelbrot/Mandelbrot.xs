#define PERL_NO_GET_CONTEXT
#ifdef __cplusplus
extern "C" {
#endif
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#ifdef __cplusplus
}
#endif

#include "imext.h"
#include "imperl.h"

void 
mandelbrot(i_img *im, double minx, double miny, double maxx, double maxy, int max_iter);

DEFINE_IMAGER_CALLBACKS;

MODULE = Imager::Filter::Mandelbrot   PACKAGE = Imager::Filter::Mandelbrot

PROTOTYPES: ENABLE

void
mandelbrot(im, minx=-2.5, miny=-2.0, maxx=2.5, maxy=-2.0, max_iter=256)
        Imager::ImgRaw im
        double minx
        double miny
        double maxx
        double maxy
        int max_iter

BOOT:
        PERL_INITIALIZE_IMAGER_CALLBACKS;

