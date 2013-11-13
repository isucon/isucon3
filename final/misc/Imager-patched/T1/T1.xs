#define PERL_NO_GET_CONTEXT
#ifdef __cplusplus
extern "C" {
#endif
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "imext.h"
#include "imperl.h"
#include "imt1.h"

DEFINE_IMAGER_CALLBACKS;

typedef i_t1_font_t Imager__Font__T1xs;

#define i_t1_DESTROY(font) i_t1_destroy(font)

MODULE = Imager::Font::T1  PACKAGE = Imager::Font::T1

undef_int
i_init_t1(t1log)
	int t1log

MODULE = Imager::Font::T1  PACKAGE = Imager::Font::T1xs PREFIX = i_t1_

Imager::Font::T1xs
i_t1_new(class,pfb,afm)
       	      char*    pfb
       	      char*    afm
  C_ARGS:
    pfb, afm

void
i_t1_DESTROY(font)
 Imager::Font::T1xs font	


undef_int
i_t1_cp(font,im,xb,yb,channel,points,str_sv,align,utf8=0,flags="",aa=1)
 Imager::Font::T1xs     font
    Imager::ImgRaw     im
	 i_img_dim     xb
	 i_img_dim     yb
	       int     channel
            double     points
	        SV*    str_sv
	       int     align
               int     utf8
              char*    flags
	       int     aa
             PREINIT:
               char *str;
               STRLEN len;
             CODE:
               str = SvPV(str_sv, len);
#ifdef SvUTF8
               if (SvUTF8(str_sv))
                 utf8 = 1;
#endif
               RETVAL = i_t1_cp(font, im, xb,yb,channel,points,str,len,align,
                                  utf8,flags,aa);
           OUTPUT:
             RETVAL


void
i_t1_bbox(fontnum,point,str_sv,utf8=0,flags="")
 Imager::Font::T1xs     fontnum
	    double     point
	        SV*    str_sv
               int     utf8
              char*    flags
	     PREINIT:
               const char *str;
               STRLEN len;
	       i_img_dim     cords[BOUNDING_BOX_COUNT];
               int i;
               int rc;
	     PPCODE:
               str = SvPV(str_sv, len);
#ifdef SvUTF8
               if (SvUTF8(str_sv))
                 utf8 = 1;
#endif
               rc = i_t1_bbox(fontnum,point,str,len,cords,utf8,flags);
               if (rc > 0) {
                 EXTEND(SP, rc);
                 for (i = 0; i < rc; ++i)
                   PUSHs(sv_2mortal(newSViv(cords[i])));
               }



undef_int
i_t1_text(font,im,xb,yb,cl,points,str_sv,align,utf8=0,flags="",aa=1)
 Imager::Font::T1xs font
    Imager::ImgRaw     im
	 i_img_dim     xb
	 i_img_dim     yb
     Imager::Color    cl
            double     points
	        SV*    str_sv
	       int     align
               int     utf8
        const char*    flags
	       int     aa
             PREINIT:
               char *str;
               STRLEN len;
             CODE:
               str = SvPV(str_sv, len);
#ifdef SvUTF8
               if (SvUTF8(str_sv))
                 utf8 = 1;
#endif
               RETVAL = i_t1_text(font,im, xb,yb,cl,points,str,len,align,
                                  utf8,flags,aa);
           OUTPUT:
             RETVAL

void
i_t1_has_chars(font, text_sv, utf8 = 0)
 Imager::Font::T1xs font
        SV  *text_sv
        int utf8
      PREINIT:
        char const *text;
        STRLEN len;
        char *work;
        int count;
        int i;
      PPCODE:
        text = SvPV(text_sv, len);
#ifdef SvUTF8
        if (SvUTF8(text_sv))
          utf8 = 1;
#endif
        work = mymalloc(len);
        count = i_t1_has_chars(font, text, len, utf8, work);
        if (GIMME_V == G_ARRAY) {
          EXTEND(SP, count);

          for (i = 0; i < count; ++i) {
            PUSHs(boolSV(work[i]));
          }
        }
        else {
          EXTEND(SP, 1);
          PUSHs(sv_2mortal(newSVpv(work, count)));
        }
        myfree(work);

void
i_t1_face_name(font)
 Imager::Font::T1xs font
      PREINIT:
        char name[255];
        int len;
      PPCODE:
        len = i_t1_face_name(font, name, sizeof(name));
        if (len) {
          EXTEND(SP, 1);
          PUSHs(sv_2mortal(newSVpv(name, strlen(name))));
        }

void
i_t1_glyph_names(font, text_sv, utf8 = 0)
 Imager::Font::T1xs font
        SV *text_sv
        int utf8
      PREINIT:
        char const *text;
        STRLEN work_len;
        size_t len;
        char name[255];
	SSize_t count = 0;
      PPCODE:
        text = SvPV(text_sv, work_len);
#ifdef SvUTF8
        if (SvUTF8(text_sv))
          utf8 = 1;
#endif
	i_clear_error();
        len = work_len;
        while (len) {
          unsigned long ch;
          if (utf8) {
            ch = i_utf8_advance(&text, &len);
            if (ch == ~0UL) {
              i_push_error(0, "invalid UTF8 character");
	      XSRETURN(0);
            }
          }
          else {
            ch = *text++;
            --len;
          }
          EXTEND(SP, count+1);
          if (i_t1_glyph_name(font, ch, name, sizeof(name))) {
            ST(count) = sv_2mortal(newSVpv(name, 0));
          }
          else {
            ST(count) = &PL_sv_undef;
          }
	  ++count;
        }
	XSRETURN(count);

int
i_t1_CLONE_SKIP(...)
    CODE:
	(void)items; /* avoid unused warning */
	RETVAL = 1;
    OUTPUT:
	RETVAL

BOOT:
	PERL_INITIALIZE_IMAGER_CALLBACKS;
	i_t1_start();