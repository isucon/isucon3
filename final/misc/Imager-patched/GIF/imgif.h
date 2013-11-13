#ifndef IMAGER_IMGIF_H
#define IMAGER_IMGIF_H

#include "imext.h"

void i_init_gif(void);
double i_giflib_version(void);
i_img *i_readgif_wiol(io_glue *ig, int **colour_table, int *colours);
i_img *i_readgif_single_wiol(io_glue *ig, int page);
extern i_img **i_readgif_multi_wiol(io_glue *ig, int *count);
undef_int i_writegif_wiol(io_glue *ig, i_quantize *quant, 
                          i_img **imgs, int count);

#endif
