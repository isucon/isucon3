#define PERL_NO_GET_CONTEXT
#ifdef __cplusplus
extern "C" {
#endif
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "imext.h"
#include "imperl.h"
#include "imft2.h"

DEFINE_IMAGER_CALLBACKS;

MODULE = Imager::Font::FT2  PACKAGE = Imager::Font::FT2x     PREFIX=FT2_

#define FT2_DESTROY(font) i_ft2_destroy(font)

void
FT2_DESTROY(font)
        Imager::Font::FT2x font

int
FT2_CLONE_SKIP(...)
    CODE:
        (void)items;
        RETVAL = 1;
    OUTPUT:
        RETVAL

MODULE = Imager::Font::FT2  PACKAGE = Imager::Font::FT2

Imager::Font::FT2x
i_ft2_new(name, index)
        char *name
        int index

const char *
i_ft2_version(runtime)
	int runtime
    PREINIT:
	char buf[100];
    CODE:
	if (!i_ft2_version(runtime, buf, sizeof(buf))) {
	  XSRETURN_EMPTY;
	}
	RETVAL = buf;
    OUTPUT:
	RETVAL

undef_int
i_ft2_setdpi(font, xdpi, ydpi)
        Imager::Font::FT2x font
        int xdpi
        int ydpi

void
i_ft2_getdpi(font)
        Imager::Font::FT2x font
      PREINIT:
        int xdpi, ydpi;
      CODE:
        if (i_ft2_getdpi(font, &xdpi, &ydpi)) {
          EXTEND(SP, 2);
          PUSHs(sv_2mortal(newSViv(xdpi)));
          PUSHs(sv_2mortal(newSViv(ydpi)));
        }

undef_int
i_ft2_sethinting(font, hinting)
        Imager::Font::FT2x font
        int hinting

undef_int
i_ft2_settransform(font, matrix)
        Imager::Font::FT2x font
      PREINIT:
        double matrix[6];
        int len;
        AV *av;
        SV *sv1;
        int i;
      CODE:
        if (!SvROK(ST(1)) || SvTYPE(SvRV(ST(1))) != SVt_PVAV)
          croak("i_ft2_settransform: parameter 2 must be an array ref\n");
	av=(AV*)SvRV(ST(1));
	len=av_len(av)+1;
        if (len > 6)
          len = 6;
        for (i = 0; i < len; ++i) {
	  sv1=(*(av_fetch(av,i,0)));
	  matrix[i] = SvNV(sv1);
        }
        for (; i < 6; ++i)
          matrix[i] = 0;
        RETVAL = i_ft2_settransform(font, matrix);
      OUTPUT:
        RETVAL

void
i_ft2_bbox(font, cheight, cwidth, text_sv, utf8)
        Imager::Font::FT2x font
        double cheight
        double cwidth
        SV *text_sv
	int utf8
      PREINIT:
        i_img_dim bbox[BOUNDING_BOX_COUNT];
        int i;
        char *text;
        STRLEN text_len;
        int rc;
      PPCODE:
        text = SvPV(text_sv, text_len);
#ifdef SvUTF8
        if (SvUTF8(text_sv))
          utf8 = 1;
#endif
        rc = i_ft2_bbox(font, cheight, cwidth, text, text_len, bbox, utf8);
        if (rc) {
          EXTEND(SP, rc);
          for (i = 0; i < rc; ++i)
            PUSHs(sv_2mortal(newSViv(bbox[i])));
        }

void
i_ft2_bbox_r(font, cheight, cwidth, text_sv, vlayout, utf8)
        Imager::Font::FT2x font
        double cheight
        double cwidth
	SV *text_sv
        int vlayout
        int utf8
      PREINIT:
        i_img_dim bbox[8];
        int i;
        const char *text;
	STRLEN len;
      PPCODE:
        text = SvPV(text_sv, len);
#ifdef SvUTF8
        if (SvUTF8(text_sv))
          utf8 = 1;
#endif
        if (i_ft2_bbox_r(font, cheight, cwidth, text, len, vlayout,
                         utf8, bbox)) {
          EXTEND(SP, 8);
          for (i = 0; i < 8; ++i)
            PUSHs(sv_2mortal(newSViv(bbox[i])));
        }

undef_int
i_ft2_text(font, im, tx, ty, cl, cheight, cwidth, text_sv, align, aa, vlayout, utf8)
        Imager::Font::FT2x font
        Imager::ImgRaw im
        i_img_dim tx
        i_img_dim ty
        Imager::Color cl
        double cheight
        double cwidth
	SV *text_sv
        int align
        int aa
        int vlayout
        int utf8
      PREINIT:
        const char *text;
        STRLEN len;
      CODE:
        text = SvPV(text_sv, len);
#ifdef SvUTF8
        if (SvUTF8(text_sv)) {
          utf8 = 1;
        }
#endif
        RETVAL = i_ft2_text(font, im, tx, ty, cl, cheight, cwidth, text,
                            len, align, aa, vlayout, utf8);
      OUTPUT:
        RETVAL

undef_int
i_ft2_cp(font, im, tx, ty, channel, cheight, cwidth, text_sv, align, aa, vlayout, utf8)
        Imager::Font::FT2x font
        Imager::ImgRaw im
        i_img_dim tx
        i_img_dim ty
        int channel
        double cheight
        double cwidth
        SV *text_sv
        int align
        int aa
        int vlayout
        int utf8
      PREINIT:
	char const *text;
	STRLEN len;
      CODE:
	text = SvPV(text_sv, len);
#ifdef SvUTF8
        if (SvUTF8(text_sv))
          utf8 = 1;
#endif
        RETVAL = i_ft2_cp(font, im, tx, ty, channel, cheight, cwidth, text,
                          len, align, aa, vlayout, utf8);
      OUTPUT:
        RETVAL

void
ft2_transform_box(font, x0, x1, x2, x3)
        Imager::Font::FT2x font
        i_img_dim x0
        i_img_dim x1
        i_img_dim x2
        i_img_dim x3
      PREINIT:
        i_img_dim box[4];
      PPCODE:
        box[0] = x0; box[1] = x1; box[2] = x2; box[3] = x3;
        ft2_transform_box(font, box);
          EXTEND(SP, 4);
          PUSHs(sv_2mortal(newSViv(box[0])));
          PUSHs(sv_2mortal(newSViv(box[1])));
          PUSHs(sv_2mortal(newSViv(box[2])));
          PUSHs(sv_2mortal(newSViv(box[3])));

void
i_ft2_has_chars(handle, text_sv, utf8)
        Imager::Font::FT2x handle
        SV  *text_sv
        int utf8
      PREINIT:
        char *text;
        STRLEN len;
        char *work;
        size_t count;
        size_t i;
      PPCODE:
        text = SvPV(text_sv, len);
#ifdef SvUTF8
        if (SvUTF8(text_sv))
          utf8 = 1;
#endif
        work = mymalloc(len);
        count = i_ft2_has_chars(handle, text, len, utf8, work);
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
i_ft2_face_name(handle)
        Imager::Font::FT2x handle
      PREINIT:
        char name[255];
        size_t len;
      PPCODE:
        len = i_ft2_face_name(handle, name, sizeof(name));
        if (len) {
          EXTEND(SP, 1);
          PUSHs(sv_2mortal(newSVpv(name, 0)));
        }

undef_int
i_ft2_can_face_name()

void
i_ft2_glyph_name(handle, text_sv, utf8 = 0, reliable_only = 1)
        Imager::Font::FT2x handle
        SV *text_sv
        int utf8
        int reliable_only
      PREINIT:
        char const *text;
        STRLEN work_len;
        size_t len;
        char name[255];
	SSize_t count = 0;
      PPCODE:
        i_clear_error();
        text = SvPV(text_sv, work_len);
        len = work_len;
#ifdef SvUTF8
        if (SvUTF8(text_sv))
          utf8 = 1;
#endif
        while (len) {
          unsigned long ch;
          if (utf8) {
            ch = i_utf8_advance(&text, &len);
            if (ch == ~0UL) {
              i_push_error(0, "invalid UTF8 character");
              XSRETURN_EMPTY;
            }
          }
          else {
            ch = *text++;
            --len;
          }
          EXTEND(SP, count+1);
          if (i_ft2_glyph_name(handle, ch, name, sizeof(name), 
                                         reliable_only)) {
            ST(count) = sv_2mortal(newSVpv(name, 0));
          }
          else {
            ST(count) = &PL_sv_undef;
          }
	  ++count;
        }
	XSRETURN(count);

int
i_ft2_can_do_glyph_names()

int
i_ft2_face_has_glyph_names(handle)
        Imager::Font::FT2x handle

int
i_ft2_is_multiple_master(handle)
        Imager::Font::FT2x handle

void
i_ft2_get_multiple_masters(handle)
        Imager::Font::FT2x handle
      PREINIT:
        i_font_mm mm;
        int i;
      PPCODE:
        if (i_ft2_get_multiple_masters(handle, &mm)) {
          EXTEND(SP, 2+mm.num_axis);
          PUSHs(sv_2mortal(newSViv(mm.num_axis)));
          PUSHs(sv_2mortal(newSViv(mm.num_designs)));
          for (i = 0; i < mm.num_axis; ++i) {
            AV *av = newAV();
            SV *sv;
            av_extend(av, 3);
            sv = newSVpv(mm.axis[i].name, strlen(mm.axis[i].name));
            SvREFCNT_inc(sv);
            av_store(av, 0, sv);
            sv = newSViv(mm.axis[i].minimum);
            SvREFCNT_inc(sv);
            av_store(av, 1, sv);
            sv = newSViv(mm.axis[i].maximum);
            SvREFCNT_inc(sv);
            av_store(av, 2, sv);
            PUSHs(newRV_noinc((SV *)av));
          }
        }

undef_int
i_ft2_set_mm_coords(handle, ...)
        Imager::Font::FT2x handle
      PROTOTYPE: DISABLE
      PREINIT:
        long *coords;
        int ix_coords, i;
      CODE:
        /* T_ARRAY handling by xsubpp seems to be busted in 5.6.1, so
           transfer the array manually */
        ix_coords = items-1;
        coords = mymalloc(sizeof(long) * ix_coords);
	for (i = 0; i < ix_coords; ++i) {
          coords[i] = (long)SvIV(ST(1+i));
        }
        RETVAL = i_ft2_set_mm_coords(handle, ix_coords, coords);
        myfree(coords);
      OUTPUT:
        RETVAL


BOOT:
	PERL_INITIALIZE_IMAGER_CALLBACKS;
	i_ft2_start();
