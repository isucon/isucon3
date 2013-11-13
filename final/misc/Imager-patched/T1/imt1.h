#ifndef IMAGER_IMT1_H
#define IMAGER_IMT1_H

#include "imdatatypes.h"

typedef struct i_t1_font_tag *i_t1_font_t;

extern void
i_t1_start(void);

extern undef_int
i_init_t1(int t1log);

extern void
i_close_t1(void);

extern i_t1_font_t
i_t1_new(char *pfb,char *afm);

extern int
i_t1_destroy(i_t1_font_t font);

extern undef_int
i_t1_cp(i_t1_font_t font, i_img *im,i_img_dim xb,i_img_dim yb,int channel,double points,char* str,size_t len,int align, int utf8, char const *flags, int aa);

extern int
i_t1_bbox(i_t1_font_t font,double points,const char *str,size_t len,i_img_dim *cords, int utf8,char const *flags);

extern undef_int
i_t1_text(i_t1_font_t font, i_img *im,i_img_dim xb,i_img_dim yb,const i_color *cl,double points,const char* str,size_t len,int align, int utf8, char const *flags, int aa);

extern int
i_t1_has_chars(i_t1_font_t font, const char *text, size_t len, int utf8,
               char *out);

extern int
i_t1_face_name(i_t1_font_t font, char *name_buf, size_t name_buf_size);

extern int
i_t1_glyph_name(i_t1_font_t font, unsigned long ch, char *name_buf, 
		size_t name_buf_size);
#endif
