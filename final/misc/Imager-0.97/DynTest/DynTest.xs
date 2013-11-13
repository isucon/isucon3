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

extern void lin_stretch(i_img *, int, int);

DEFINE_IMAGER_CALLBACKS;

MODULE = Imager::Filter::DynTest   PACKAGE = Imager::Filter::DynTest

PROTOTYPES: ENABLE

void
lin_stretch(im, a, b)
        Imager::ImgRaw im
        int a
        int b

BOOT:
        PERL_INITIALIZE_IMAGER_CALLBACKS;

