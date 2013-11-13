#ifndef IMAGER_IMICON_H
#define IMAGER_IMICON_H

#include "imext.h"

extern i_img *
i_readico_single(io_glue *ig, int index, int masked);
extern i_img **
i_readico_multi(io_glue *ig, int *count, int masked);

extern int
i_writeico_wiol(i_io_glue_t *ig, i_img *im);

extern int
i_writeico_multi_wiol(i_io_glue_t *ig, i_img **im, int count);

extern int
i_writecur_wiol(i_io_glue_t *ig, i_img *im);

extern int
i_writecur_multi_wiol(i_io_glue_t *ig, i_img **im, int count);

#endif
