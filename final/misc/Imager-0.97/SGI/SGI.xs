#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "imext.h"
#include "imperl.h"
#include "imsgi.h"
#include "ppport.h"

DEFINE_IMAGER_CALLBACKS;

MODULE = Imager::File::SGI  PACKAGE = Imager::File::SGI

PROTOTYPES: DISABLE

Imager::ImgRaw
i_readsgi_wiol(ig, partial)
	Imager::IO ig
	int partial

int
i_writesgi_wiol(ig, im)
	Imager::IO ig
	Imager::ImgRaw im

BOOT:
	PERL_INITIALIZE_IMAGER_CALLBACKS;
