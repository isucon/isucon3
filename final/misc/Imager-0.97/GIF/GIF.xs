#define PERL_NO_GET_CONTEXT
#ifdef __cplusplus
extern "C" {
#endif
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "imext.h"
#include "imperl.h"
#include "imgif.h"
#include "imextpl.h"

DEFINE_IMAGER_CALLBACKS;
DEFINE_IMAGER_PERL_CALLBACKS;

MODULE = Imager::File::GIF  PACKAGE = Imager::File::GIF

double
i_giflib_version()

undef_int
i_writegif_wiol(ig, opts,...)
	Imager::IO ig
      PREINIT:
	i_quantize quant;
	i_img **imgs = NULL;
	int img_count;
	int i;
	HV *hv;
      CODE:
	if (items < 3)
	    croak("Usage: i_writegif_wiol(IO,hashref, images...)");
	if (!SvROK(ST(1)) || ! SvTYPE(SvRV(ST(1))))
	    croak("i_writegif_callback: Second argument must be a hash ref");
	hv = (HV *)SvRV(ST(1));
	memset(&quant, 0, sizeof(quant));
	quant.version = 1;
	quant.mc_size = 256;
	quant.transp = tr_threshold;
	quant.tr_threshold = 127;
	ip_handle_quant_opts(aTHX_ &quant, hv);
	img_count = items - 2;
	RETVAL = 1;
	if (img_count < 1) {
	  RETVAL = 0;
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
	      RETVAL = 0;
	      break;
            }
	  }
          if (RETVAL) {
	    RETVAL = i_writegif_wiol(ig, &quant, imgs, img_count);
          }
	  myfree(imgs);
          if (RETVAL) {
	    ip_copy_colors_back(aTHX_ hv, &quant);
          }
	}
	ST(0) = sv_newmortal();
	if (RETVAL == 0) ST(0)=&PL_sv_undef;
	else sv_setiv(ST(0), (IV)RETVAL);
	ip_cleanup_quant_opts(aTHX_ &quant);


void
i_readgif_wiol(ig)
     Imager::IO         ig
	      PREINIT:
	        int*    colour_table;
	        int     colours, q, w;
	      i_img*    rimg;
                 SV*    temp[3];
                 AV*    ct; 
                 SV*    r;
	       PPCODE:
 	       colour_table = NULL;
               colours = 0;

	if(GIMME_V == G_ARRAY) {
            rimg = i_readgif_wiol(ig,&colour_table,&colours);
        } else {
            /* don't waste time with colours if they aren't wanted */
            rimg = i_readgif_wiol(ig,NULL,NULL);
        }
	
	if (colour_table == NULL) {
            EXTEND(SP,1);
            r=sv_newmortal();
            sv_setref_pv(r, "Imager::ImgRaw", (void*)rimg);
            PUSHs(r);
	} else {
            /* the following creates an [[r,g,b], [r, g, b], [r, g, b]...] */
            /* I don't know if I have the reference counts right or not :( */
            /* Neither do I :-) */
            /* No Idea here either */

            ct=newAV();
            av_extend(ct, colours);
            for(q=0; q<colours; q++) {
                for(w=0; w<3; w++)
                    temp[w]=sv_2mortal(newSViv(colour_table[q*3 + w]));
                av_store(ct, q, (SV*)newRV_noinc((SV*)av_make(3, temp)));
            }
            myfree(colour_table);

            EXTEND(SP,2);
            r = sv_newmortal();
            sv_setref_pv(r, "Imager::ImgRaw", (void*)rimg);
            PUSHs(r);
            PUSHs(newRV_noinc((SV*)ct));
        }

Imager::ImgRaw
i_readgif_single_wiol(ig, page=0)
	Imager::IO	ig
        int		page

void
i_readgif_multi_wiol(ig)
        Imager::IO ig
      PREINIT:
        i_img **imgs;
        int count;
        int i;
      PPCODE:
        imgs = i_readgif_multi_wiol(ig, &count);
        if (imgs) {
          EXTEND(SP, count);
          for (i = 0; i < count; ++i) {
            SV *sv = sv_newmortal();
            sv_setref_pv(sv, "Imager::ImgRaw", (void *)imgs[i]);
            PUSHs(sv);
          }
          myfree(imgs);
        }


BOOT:
	PERL_INITIALIZE_IMAGER_CALLBACKS;
	PERL_INITIALIZE_IMAGER_PERL_CALLBACKS;
	i_init_gif();
