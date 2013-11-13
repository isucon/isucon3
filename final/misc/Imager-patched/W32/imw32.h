#ifndef IMAGER_IMW32_H
#define IMAGER_IMW32_H

#include "imdatatypes.h"

extern int i_wf_bbox(const char *face, i_img_dim size, const char *text, size_t length, i_img_dim *bbox, int utf8);
extern int i_wf_text(const char *face, i_img *im, i_img_dim tx, i_img_dim ty, const i_color *cl, 
		     i_img_dim size, const char *text, size_t len, int align, int aa, int utf8);
extern int i_wf_cp(const char *face, i_img *im, i_img_dim tx, i_img_dim ty, int channel, 
		   i_img_dim size, const char *text, size_t len, int align, int aa, int utf8);
extern int i_wf_addfont(char const *file);
extern int i_wf_delfont(char const *file);

#endif
