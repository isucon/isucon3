/* perlio.c - Imager's interface to PerlIO

 */
#define IMAGER_NO_CONTEXT
#include "imager.h"
#include "EXTERN.h"
#include "perl.h"
#include "imperlio.h"


static ssize_t
perlio_reader(void *handle, void *buf, size_t count);
static ssize_t
perlio_writer(void *handle, const void *buf, size_t count);
static off_t
perlio_seeker(void *handle, off_t offset, int whence);
static int
perlio_closer(void *handle);
static void
perlio_destroy(void *handle);
static const char *my_strerror(pTHX_ int err);

#ifndef tTHX
#define tTHX PerlInterpreter *
#endif

typedef struct {
  PerlIO *handle;
  pIMCTX;
#ifdef MULTIPLICITY
  tTHX my_perl;
#endif
} im_perlio;

#define dIMCTXperlio(state) dIMCTXctx(state->aIMCTX)

/*
=item im_io_new_perlio(PerlIO *)

Create a new perl I/O object that reads/writes/seeks on a PerlIO
handle.

The close() handle flushes output but does not close the handle.

=cut
*/

i_io_glue_t *
im_io_new_perlio(pTHX_ PerlIO *handle) {
  im_perlio *state = mymalloc(sizeof(im_perlio));
  dIMCTX;

  state->handle = handle;
#ifdef MULTIPLICITY
  state->aTHX = aTHX;
#endif
  state->aIMCTX = aIMCTX;

  return io_new_cb(state, perlio_reader, perlio_writer,
		   perlio_seeker, perlio_closer, perlio_destroy);
}

static ssize_t
perlio_reader(void *ctx, void *buf, size_t count) {
  im_perlio *state = ctx;
  dTHXa(state->my_perl);
  dIMCTXperlio(state);

  ssize_t result = PerlIO_read(state->handle, buf, count);
  if (result == 0 && PerlIO_error(state->handle)) {
    im_push_errorf(aIMCTX, errno, "read() failure (%s)", my_strerror(aTHX_ errno));
    return -1;
  }

  return result;
}

static ssize_t
perlio_writer(void *ctx, const void *buf, size_t count) {
  im_perlio *state = ctx;
  dTHXa(state->my_perl);
  dIMCTXperlio(state);
  ssize_t result;

  result = PerlIO_write(state->handle, buf, count);

  if (result == 0) {
    im_push_errorf(aIMCTX, errno, "write() failure (%s)", my_strerror(aTHX_ errno));
  }

  return result;
}

static off_t
perlio_seeker(void *ctx, off_t offset, int whence) {
  im_perlio *state = ctx;
  dTHXa(state->my_perl);
  dIMCTXperlio(state);

  if (whence != SEEK_CUR || offset != 0) {
    if (PerlIO_seek(state->handle, offset, whence) < 0) {
      im_push_errorf(aIMCTX, errno, "seek() failure (%s)", my_strerror(aTHX_ errno));
      return -1;
    }
  }

  return PerlIO_tell(state->handle);
}

static int
perlio_closer(void *ctx) {
  im_perlio *state = ctx;
  dTHXa(state->my_perl);
  dIMCTXperlio(state);

  if (PerlIO_flush(state->handle) < 0) {
    im_push_errorf(aIMCTX, errno, "flush() failure (%s)", my_strerror(aTHX_ errno));
    return -1;
  }
  return 0;
}

static void
perlio_destroy(void *ctx) {
  myfree(ctx);
}

static
const char *my_strerror(pTHX_ int err) {
  const char *result = strerror(err);
  
  if (!result)
    result = "Unknown error";
  
  return result;
}

