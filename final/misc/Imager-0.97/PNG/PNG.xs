#define PERL_NO_GET_CONTEXT
#ifdef __cplusplus
extern "C" {
#endif
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "imext.h"
#include "imperl.h"
#include "impng.h"

DEFINE_IMAGER_CALLBACKS;

MODULE = Imager::File::PNG  PACKAGE = Imager::File::PNG

Imager::ImgRaw
i_readpng_wiol(ig, flags=0)
        Imager::IO     ig
	int 	       flags

undef_int
i_writepng_wiol(im, ig)
    Imager::ImgRaw     im
        Imager::IO     ig

unsigned
i_png_lib_version()

MODULE = Imager::File::PNG  PACKAGE = Imager::File::PNG PREFIX=i_png_

void
i_png_features(...)
  PREINIT:
    const char * const *p;
  PPCODE:
    p = i_png_features();
    while (*p) {
      EXTEND(SP, 1);
      PUSHs(sv_2mortal(newSVpv(*p, 0)));
      ++p;
    }

int
IMPNG_READ_IGNORE_BENIGN_ERRORS()
  CODE:
    RETVAL = IMPNG_READ_IGNORE_BENIGN_ERRORS;
  OUTPUT:
    RETVAL

BOOT:
	PERL_INITIALIZE_IMAGER_CALLBACKS;
