#define PERL_NO_GET_CONTEXT
#ifdef __cplusplus
extern "C" {
#endif
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "imext.h"
#include "imperl.h"
#include "imtiff.h"

DEFINE_IMAGER_CALLBACKS;

#ifdef IEEEFP_TYPES
#define i_tiff_ieeefp() &PL_sv_yes
#else
#define i_tiff_ieeefp() &PL_sv_no
#endif

MODULE = Imager::File::TIFF  PACKAGE = Imager::File::TIFF

Imager::ImgRaw
i_readtiff_wiol(ig, allow_incomplete=0, page=0)
        Imager::IO     ig
	       int     allow_incomplete
               int     page

void
i_readtiff_multi_wiol(ig)
        Imager::IO     ig
      PREINIT:
        i_img **imgs;
        int count;
        int i;
      PPCODE:
        imgs = i_readtiff_multi_wiol(ig, &count);
        if (imgs) {
          EXTEND(SP, count);
          for (i = 0; i < count; ++i) {
            SV *sv = sv_newmortal();
            sv_setref_pv(sv, "Imager::ImgRaw", (void *)imgs[i]);
            PUSHs(sv);
          }
          myfree(imgs);
        }


undef_int
i_writetiff_wiol(im, ig)
    Imager::ImgRaw     im
        Imager::IO     ig

undef_int
i_writetiff_multi_wiol(ig, ...)
        Imager::IO     ig
      PREINIT:
        int i;
        int img_count;
        i_img **imgs;
      CODE:
        if (items < 2)
          croak("Usage: i_writetiff_multi_wiol(ig, images...)");
        img_count = items - 1;
        RETVAL = 1;
	if (img_count < 1) {
	  RETVAL = 0;
	  i_clear_error();
	  i_push_error(0, "You need to specify images to save");
	}
	else {
          imgs = mymalloc(sizeof(i_img *) * img_count);
          for (i = 0; i < img_count; ++i) {
	    SV *sv = ST(1+i);
	    imgs[i] = NULL;
	    if (SvROK(sv) && sv_derived_from(sv, "Imager::ImgRaw")) {
	      imgs[i] = INT2PTR(i_img *, SvIV((SV*)SvRV(sv)));
	    }
	    else {
	      i_clear_error();
	      i_push_error(0, "Only images can be saved");
              myfree(imgs);
	      RETVAL = 0;
	      break;
            }
	  }
          if (RETVAL) {
	    RETVAL = i_writetiff_multi_wiol(ig, imgs, img_count);
          }
	  myfree(imgs);
	}
      OUTPUT:
        RETVAL

undef_int
i_writetiff_wiol_faxable(im, ig, fine)
    Imager::ImgRaw     im
        Imager::IO     ig
	       int     fine

undef_int
i_writetiff_multi_wiol_faxable(ig, fine, ...)
        Imager::IO     ig
        int fine
      PREINIT:
        int i;
        int img_count;
        i_img **imgs;
      CODE:
        if (items < 3)
          croak("Usage: i_writetiff_multi_wiol_faxable(ig, fine, images...)");
        img_count = items - 2;
        RETVAL = 1;
	if (img_count < 1) {
	  RETVAL = 0;
	  i_clear_error();
	  i_push_error(0, "You need to specify images to save");
	}
	else {
          imgs = mymalloc(sizeof(i_img *) * img_count);
          for (i = 0; i < img_count; ++i) {
	    SV *sv = ST(2+i);
	    imgs[i] = NULL;
	    if (SvROK(sv) && sv_derived_from(sv, "Imager::ImgRaw")) {
	      imgs[i] = INT2PTR(i_img *, SvIV((SV*)SvRV(sv)));
	    }
	    else {
	      i_clear_error();
	      i_push_error(0, "Only images can be saved");
              myfree(imgs);
	      RETVAL = 0;
	      break;
            }
	  }
          if (RETVAL) {
	    RETVAL = i_writetiff_multi_wiol_faxable(ig, imgs, img_count, fine);
          }
	  myfree(imgs);
	}
      OUTPUT:
        RETVAL

const char *
i_tiff_libversion()

bool
i_tiff_has_compression(name)
	const char *name

SV *
i_tiff_ieeefp()

BOOT:
	PERL_INITIALIZE_IMAGER_CALLBACKS;
	i_tiff_init();