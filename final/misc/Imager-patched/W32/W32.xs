#define PERL_NO_GET_CONTEXT
#ifdef __cplusplus
extern "C" {
#endif
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "imext.h"
#include "imperl.h"
#include "imw32.h"

DEFINE_IMAGER_CALLBACKS;

MODULE = Imager::Font::W32  PACKAGE = Imager::Font::W32

void
i_wf_bbox(face, size, text_sv, utf8=0)
	const char *face
	i_img_dim size
	SV *text_sv
	int utf8
      PREINIT:
	i_img_dim cords[BOUNDING_BOX_COUNT];
        int rc, i;
	char const *text;
         STRLEN text_len;
      PPCODE:
        text = SvPV(text_sv, text_len);
#ifdef SvUTF8
        if (SvUTF8(text_sv))
          utf8 = 1;
#endif
        if (rc = i_wf_bbox(face, size, text, text_len, cords, utf8)) {
          EXTEND(SP, rc);  
          for (i = 0; i < rc; ++i) 
            PUSHs(sv_2mortal(newSViv(cords[i])));
        }

undef_int
i_wf_text(face, im, tx, ty, cl, size, text_sv, align, aa, utf8 = 0)
	const char *face
	Imager::ImgRaw im
	i_img_dim tx
	i_img_dim ty
	Imager::Color cl
	i_img_dim size
	SV *text_sv
	int align
	int aa
 	int utf8
      PREINIT:
	char const *text;
	STRLEN text_len;
      CODE:
        text = SvPV(text_sv, text_len);
#ifdef SvUTF8
        if (SvUTF8(text_sv))
          utf8 = 1;
#endif
	RETVAL = i_wf_text(face, im, tx, ty, cl, size, text, text_len, 
	                   align, aa, utf8);
      OUTPUT:
	RETVAL

undef_int
i_wf_cp(face, im, tx, ty, channel, size, text_sv, align, aa, utf8 = 0)
	const char *face
	Imager::ImgRaw im
	i_img_dim tx
	i_img_dim ty
	int channel
	i_img_dim size
	SV *text_sv
	int align
	int aa
	int utf8
      PREINIT:
	char const *text;
	STRLEN text_len;
      CODE:
        text = SvPV(text_sv, text_len);
#ifdef SvUTF8
        if (SvUTF8(text_sv))
          utf8 = 1;
#endif
	RETVAL = i_wf_cp(face, im, tx, ty, channel, size, text, text_len, 
		         align, aa, utf8);
      OUTPUT:
	RETVAL

undef_int
i_wf_addfont(font)
        char *font

undef_int
i_wf_delfont(font)
        char *font


BOOT:
	PERL_INITIALIZE_IMAGER_CALLBACKS;
