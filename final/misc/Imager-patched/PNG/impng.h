#ifndef IMAGER_IMPNG_H
#define IMAGER_IMPNG_H

#include "imext.h"

i_img    *i_readpng_wiol(io_glue *ig, int flags);

#define IMPNG_READ_IGNORE_BENIGN_ERRORS 1

undef_int i_writepng_wiol(i_img *im, io_glue *ig);
unsigned i_png_lib_version(void);

extern const char * const *
i_png_features(void);

#endif
