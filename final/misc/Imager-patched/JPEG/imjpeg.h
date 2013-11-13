#ifndef IMAGER_IMJPEG_H
#define IMAGER_IMJPEG_H

#include "imdatatypes.h"

i_img*
i_readjpeg_wiol(io_glue *data, int length, char** iptc_itext, int *itlength);

undef_int
i_writejpeg_wiol(i_img *im, io_glue *ig, int qfactor);

extern const char *
i_libjpeg_version(void);

#endif
