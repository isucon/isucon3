#define PERL_NO_GET_CONTEXT
#ifdef __cplusplus
extern "C" {
#endif
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "imext.h"
#include "imperl.h"
#include "imjpeg.h"

DEFINE_IMAGER_CALLBACKS;

MODULE = Imager::File::JPEG  PACKAGE = Imager::File::JPEG

const char *
i_libjpeg_version()

undef_int
i_writejpeg_wiol(im, ig, qfactor)
    Imager::ImgRaw     im
        Imager::IO     ig
	       int     qfactor


void
i_readjpeg_wiol(ig)
        Imager::IO     ig
	     PREINIT:
	      char*    iptc_itext;
	       int     tlength;
	     i_img*    rimg;
                SV*    r;
	     PPCODE:
 	      iptc_itext = NULL;
	      rimg = i_readjpeg_wiol(ig,-1,&iptc_itext,&tlength);
	      if (iptc_itext == NULL) {
		    r = sv_newmortal();
	            EXTEND(SP,1);
	            sv_setref_pv(r, "Imager::ImgRaw", (void*)rimg);
 		    PUSHs(r);
	      } else {
		    r = sv_newmortal();
	            EXTEND(SP,2);
	            sv_setref_pv(r, "Imager::ImgRaw", (void*)rimg);
 		    PUSHs(r);
		    PUSHs(sv_2mortal(newSVpv(iptc_itext,tlength)));
                    myfree(iptc_itext);
	      }

BOOT:
	PERL_INITIALIZE_IMAGER_CALLBACKS;
