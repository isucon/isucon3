#define IMAGER_NO_CONTEXT
#include "imager.h"
#include "iolayer.h"
#include "imerror.h"
#include "log.h"
#include <stdlib.h>
#include <stdio.h>
#ifdef _MSC_VER
#include <io.h>
#endif
#include <string.h>
#include <errno.h>
#include "imageri.h"

#define IOL_DEB(x)
#define IOL_DEBs stderr

#define IO_BUF_SIZE 8192

char *io_type_names[] = { "FDSEEK", "FDNOSEEK", "BUFFER", "CBSEEK", "CBNOSEEK", "BUFCHAIN" };

typedef struct io_blink {
  char buf[BBSIZ];
  /* size_t cnt; */
  size_t len;			/* How large is this buffer = BBZIS for now */
  struct io_blink *next;
  struct io_blink *prev;
} io_blink;


typedef struct {
  i_io_glue_t	base;
  int		fd;
} io_fdseek;

typedef struct {
  i_io_glue_t   base;
  const char	*data;
  size_t	len;
  i_io_closebufp_t     closecb;        /* free memory mapped segment or decrement refcount */
  void          *closedata;
  off_t cpos;
} io_buffer;

typedef struct {
  i_io_glue_t   base;
  void		*p;		/* Callback data */
  i_io_readl_t	readcb;
  i_io_writel_t	writecb;
  i_io_seekl_t	seekcb;
  i_io_closel_t closecb;
  i_io_destroyl_t      destroycb;
} io_cb;

typedef struct {
  off_t offset;			/* Offset of the source - not used */
  off_t length;			/* Total length of chain in bytes */
  io_blink *head;		/* Start of chain */
  io_blink *tail;		/* End of chain */
  off_t tfill;			/* End of stream in last link */
  io_blink *cp;			/* Current element of list */
  off_t cpos;			/* Offset within the current */
  off_t gpos;			/* Global position in stream */
} io_ex_bchain;

/* turn current offset, file length, whence and offset into a new offset */
#define calc_seek_offset(curr_off, length, offset, whence) \
  (((whence) == SEEK_SET) ? (offset) : \
   ((whence) == SEEK_CUR) ? (curr_off) + (offset) : \
   ((whence) == SEEK_END) ? (length) + (offset) : -1)

/*
=head1 NAME

iolayer.c - encapsulates different source of data into a single framework.

=head1 SYNOPSIS

  io_glue *ig = io_new_fd( fileno(stdin) );
  method = io_reqmeth( IOL_NOSEEK | IOL_MMAP ); // not implemented yet

  switch (method) {
  case IOL_NOSEEK:
    code that uses ig->readcb()
    to read data goes here.
    break;
  case IOL_MMAP:
    code that uses ig->readcb()
    to read data goes here.
    break;
  }  

  io_glue_destroy(ig);
  // and much more

=head1 DESCRIPTION

iolayer.c implements the basic functions to create and destroy io_glue
objects for Imager.  The typical usage pattern for data sources is:

   1. Create the source (io_new_fd)
   2. Define how you want to get data from it (io_reqmeth)
   3. read from it using the interface requested (ig->readdb, ig->mmapcb)
   4. Close the source, which 
      shouldn't really close the underlying source. (io_glue DESTROY)

=head1 FUNCTION REFERENCE

Some of these functions are internal.

=over

=cut
*/

static void
i_io_init(pIMCTX, io_glue *ig, int type, i_io_readp_t readcb,
	  i_io_writep_t writecb, i_io_seekp_t seekcb);

static ssize_t fd_read(io_glue *ig, void *buf, size_t count);
static ssize_t fd_write(io_glue *ig, const void *buf, size_t count);
static off_t fd_seek(io_glue *ig, off_t offset, int whence);
static int fd_close(io_glue *ig);
static ssize_t fd_size(io_glue *ig);
static const char *my_strerror(int err);
static void i_io_setup_buffer(io_glue *ig);
static void
i_io_start_write(io_glue *ig);
static int
i_io_read_fill(io_glue *ig, ssize_t needed);
static void
dump_data(unsigned char *start, unsigned char *end, int bias);
static ssize_t realseek_read(io_glue *igo, void *buf, size_t count);
static ssize_t realseek_write(io_glue *igo, const void *buf, size_t count);
static int realseek_close(io_glue *igo);
static off_t realseek_seek(io_glue *igo, off_t offset, int whence);
static void realseek_destroy(io_glue *igo);
static ssize_t buffer_read(io_glue *igo, void *buf, size_t count);
static ssize_t buffer_write(io_glue *ig, const void *buf, size_t count);
static int buffer_close(io_glue *ig);
static off_t buffer_seek(io_glue *igo, off_t offset, int whence);
static void buffer_destroy(io_glue *igo);
static io_blink*io_blink_new(void);
static void io_bchain_advance(io_ex_bchain *ieb);
static void io_destroy_bufchain(io_ex_bchain *ieb);
static ssize_t bufchain_read(io_glue *ig, void *buf, size_t count);
static ssize_t bufchain_write(io_glue *ig, const void *buf, size_t count);
static int bufchain_close(io_glue *ig);
static off_t bufchain_seek(io_glue *ig, off_t offset, int whence);
static void bufchain_destroy(io_glue *ig);

/*
 * Methods for setting up data source
 */

/*
=item im_io_new_bufchain(ctx)
X<im_io_new_bufchain API>X<i_io_new_bufchain API>
=order 10
=category I/O Layers

Returns a new io_glue object that has the 'empty' source and but can
be written to and read from later (like a pseudo file).

Also callable as C<io_new_bufchain()>.

=cut
*/

io_glue *
im_io_new_bufchain(pIMCTX) {
  io_glue *ig;
  io_ex_bchain *ieb = mymalloc(sizeof(io_ex_bchain));

  im_log((aIMCTX, 1, "io_new_bufchain()\n"));

  ig = mymalloc(sizeof(io_glue));
  memset(ig, 0, sizeof(*ig));
  i_io_init(aIMCTX, ig, BUFCHAIN, bufchain_read, bufchain_write, bufchain_seek);

  ieb->offset = 0;
  ieb->length = 0;
  ieb->cpos   = 0;
  ieb->gpos   = 0;
  ieb->tfill  = 0;
  
  ieb->head   = io_blink_new();
  ieb->cp     = ieb->head;
  ieb->tail   = ieb->head;
  
  ig->exdata    = ieb;
  ig->closecb   = bufchain_close;
  ig->destroycb = bufchain_destroy;

  im_context_refinc(aIMCTX, "im_io_new_bufchain");

  return ig;
}

/*
=item im_io_new_buffer(ctx, data, length)
X<im_io_new_buffer API>X<io_new_buffer API>
=order 10
=category I/O Layers

Returns a new io_glue object that has the source defined as reading
from specified buffer.  Note that the buffer is not copied.

   ctx - an Imager context object
   data - buffer to read from
   length - length of buffer

Also callable as C<io_new_buffer(data, length>.

=cut
*/

io_glue *
im_io_new_buffer(pIMCTX, const char *data, size_t len, i_io_closebufp_t closecb, void *closedata) {
  io_buffer *ig;
  
  im_log((aIMCTX, 1, "io_new_buffer(data %p, len %ld, closecb %p, closedata %p)\n", data, (long)len, closecb, closedata));

  ig = mymalloc(sizeof(io_buffer));
  memset(ig, 0, sizeof(*ig));
  i_io_init(aIMCTX, &ig->base, BUFFER, buffer_read, buffer_write, buffer_seek);
  ig->data      = data;
  ig->len       = len;
  ig->closecb   = closecb;
  ig->closedata = closedata;

  ig->cpos   = 0;
  
  ig->base.closecb   = buffer_close;
  ig->base.destroycb = buffer_destroy;

  im_context_refinc(aIMCTX, "im_io_new_bufchain");

  return (io_glue *)ig;
}


/*
=item im_io_new_fd(ctx, file)
X<io_new_fd API>X<im_io_new_fd API>
=order 10
=category I/O Layers

Returns a new io_glue object that has the source defined as reading
from specified file descriptor.  Note that the the interface to receiving
data from the io_glue callbacks hasn't been done yet.

  ctx - and Imager context object
  file - file descriptor to read/write from

Also callable as C<io_new_fd(file)>.

=cut
*/

io_glue *
im_io_new_fd(pIMCTX, int fd) {
  io_fdseek *ig;

  im_log((aIMCTX, 1, "io_new_fd(fd %d)\n", fd));

  ig = mymalloc(sizeof(io_fdseek));
  memset(ig, 0, sizeof(*ig));
  i_io_init(aIMCTX, &ig->base, FDSEEK, fd_read, fd_write, fd_seek);
  ig->fd = fd;

  ig->base.closecb   = fd_close;
  ig->base.sizecb    = fd_size;
  ig->base.destroycb = NULL;
  im_context_refinc(aIMCTX, "im_io_new_bufchain");

  im_log((aIMCTX, 1, "(%p) <- io_new_fd\n", ig));
  return (io_glue *)ig;
}

/*
=item im_io_new_cb(ctx, p, read_cb, write_cb, seek_cb, close_cb, destroy_cb)
X<im_io_new_cb API>X<io_new_cb API>
=category I/O Layers
=order 10

Create a new I/O layer object that calls your supplied callbacks.

In general the callbacks should behave like the corresponding POSIX
primitives.

=over

=item *

C<read_cb>(p, buffer, length) should read up to C<length> bytes into
C<buffer> and return the number of bytes read.  At end of file, return
0.  On error, return -1.

=item *

C<write_cb>(p, buffer, length) should write up to C<length> bytes from
C<buffer> and return the number of bytes written.  A return value <= 0
will be treated as an error.

=item *

C<seekcb>(p, offset, whence) should seek and return the new offset.

=item *

C<close_cb>(p) should return 0 on success, -1 on failure.

=item *

C<destroy_cb>(p) should release any memory specific to your callback
handlers.

=back

Also callable as C<io_new_cb(p, readcb, writecb, seekcb, closecb,
destroycb)>.

=cut
*/

io_glue *
im_io_new_cb(pIMCTX, void *p, i_io_readl_t readcb, i_io_writel_t writecb, 
	  i_io_seekl_t seekcb, i_io_closel_t closecb, 
	  i_io_destroyl_t destroycb) {
  io_cb *ig;

  im_log((aIMCTX, 1, "io_new_cb(p %p, readcb %p, writecb %p, seekcb %p, closecb %p, "
          "destroycb %p)\n", p, readcb, writecb, seekcb, closecb, destroycb));
  ig = mymalloc(sizeof(io_cb));
  memset(ig, 0, sizeof(*ig));
  i_io_init(aIMCTX, &ig->base, CBSEEK, realseek_read, realseek_write, realseek_seek);
  im_log((aIMCTX, 1, "(%p) <- io_new_cb\n", ig));

  ig->base.closecb   = realseek_close;
  ig->base.destroycb = realseek_destroy;

  ig->p         = p;
  ig->readcb    = readcb;
  ig->writecb   = writecb;
  ig->seekcb    = seekcb;
  ig->closecb   = closecb;
  ig->destroycb = destroycb;
  
  im_context_refinc(aIMCTX, "im_io_new_bufchain");

  return (io_glue *)ig;
}

/*
=item io_slurp(ig, c)
X<io_slurp API>
=category I/O Layers

Takes the source that the io_glue is bound to and allocates space for
a return buffer and returns the entire content in a single buffer.
Note: This only works for io_glue objects created by
io_new_bufchain().  It is useful for saving to scalars and such.

   ig - io_glue object
   c  - pointer to a pointer to where data should be copied to

  char *data;
  size_t size = io_slurp(ig, &data);
  ... do something with the data ...
  myfree(data);

io_slurp() will abort the program if the supplied I/O layer is not
from io_new_bufchain().

=cut
*/

size_t
io_slurp(io_glue *ig, unsigned char **c) {
  ssize_t rc;
  io_ex_bchain *ieb;
  unsigned char *cc;
  io_type inn = ig->type;
  
  if ( inn != BUFCHAIN ) {
    dIMCTXio(ig);
    im_fatal(aIMCTX, 0, "io_slurp: called on a source that is not from a bufchain\n");
  }

  ieb = ig->exdata;
  cc = *c = mymalloc( ieb->length );
  
  bufchain_seek(ig, 0, SEEK_SET);
  
  rc = bufchain_read(ig, cc, ieb->length);

  if (rc != ieb->length) {
    dIMCTXio(ig);
    im_fatal(aIMCTX,1, "io_slurp: bufchain_read returned an incomplete read: rc = %d, request was %d\n", rc, ieb->length);
  }

  return rc;
}

/*
=item io_glue_destroy(ig)
X<io_glue_destroy API>
=category I/O Layers
=order 90
=synopsis io_glue_destroy(ig);

Destroy an io_glue objects.  Should clean up all related buffers.

   ig - io_glue object to destroy.

=cut
*/

void
io_glue_destroy(io_glue *ig) {
  dIMCTXio(ig);
  im_log((aIMCTX, 1, "io_glue_DESTROY(ig %p)\n", ig));

  if (ig->destroycb)
    ig->destroycb(ig);

  if (ig->buffer)
    myfree(ig->buffer);
  
  myfree(ig);

  im_context_refdec(aIMCTX, "io_glue_destroy");
}

/*
=item i_io_getc(ig)
=category I/O Layers

A macro to read a single byte from a buffered I/O glue object.

Returns EOF on failure, or a byte.

=cut
*/

int
i_io_getc_imp(io_glue *ig) {
  if (ig->write_ptr)
    return EOF;
  
  if (ig->error || ig->buf_eof)
    return EOF;
  
  if (!ig->buffered) {
    unsigned char buf;
    ssize_t rc = i_io_raw_read(ig, &buf, 1);
    if (rc > 0) {
      return buf;
    }
    else if (rc == 0) {
      ig->buf_eof = 1;
      return EOF;
    }
    else {
      ig->error = 1;
      return EOF;
    }
  }

  if (!ig->buffer)
    i_io_setup_buffer(ig);
  
  if (!ig->read_ptr || ig->read_ptr == ig->read_end) {
    if (!i_io_read_fill(ig, 1))
      return EOF;
  }
  
  return *(ig->read_ptr++);
}

/*
=item i_io_peekc(ig)
=category I/O Layers

Read the next character from the stream without advancing the stream.

On error or end of file, return EOF.

For unbuffered streams a single character buffer will be setup.

=cut
*/

int
i_io_peekc_imp(io_glue *ig) {
  if (ig->write_ptr)
    return EOF;

  if (!ig->buffer)
    i_io_setup_buffer(ig);

  if (!ig->buffered) {
    ssize_t rc = i_io_raw_read(ig, ig->buffer, 1);
    if (rc > 0) {
      ig->read_ptr = ig->buffer;
      ig->read_end = ig->buffer + 1;
      return *(ig->buffer);
    }
    else if (rc == 0) {
      ig->buf_eof = 1;
      return EOF;
    }
    else {
      ig->error = 1;
      return EOF;
    }
  }

  if (!ig->read_ptr || ig->read_ptr == ig->read_end) {
    if (ig->error || ig->buf_eof)
      return EOF;
    
    if (!i_io_read_fill(ig, 1))
      return EOF;
  }

  return *(ig->read_ptr);
}

/*
=item i_io_peekn(ig, buffer, size)
=category I/O Layers
=synopsis ssize_t count = i_io_peekn(ig, buffer, sizeof(buffer));

Buffer at least C<size> (at most C<< ig->buf_size >> bytes of data
from the stream and return C<size> bytes of it to the caller in
C<buffer>.

This ignores the buffered state of the stream, and will always setup
buffering if needed.

If no C<type> parameter is provided to Imager::read() or
Imager::read_multi(), Imager will call C<i_io_peekn()> when probing
for the file format.

Returns -1 on error, 0 if there is no data before EOF, or the number
of bytes read into C<buffer>.

=cut
*/

ssize_t
i_io_peekn(io_glue *ig, void *buf, size_t size) {
  IOL_DEB(fprintf(IOL_DEBs, "i_io_peekn(%p, %p, %d)\n", ig, buf, (int)size));

  if (size == 0) {
    dIMCTXio(ig);
    i_push_error(0, "peekn size must be positive");
    IOL_DEB(fprintf(IOL_DEBs, "i_io_peekn() => -1 (zero size)\n"));
    return -1;
  }

  if (ig->write_ptr) {
    IOL_DEB(fprintf(IOL_DEBs, "i_io_peekn() => -1 (write_ptr set)\n"));
    return -1;
  }

  if (!ig->buffer)
    i_io_setup_buffer(ig);

  if ((!ig->read_ptr || size > ig->read_end - ig->read_ptr)
      && !(ig->buf_eof || ig->error)) {
    i_io_read_fill(ig, size);
  }
  
  if (size > ig->read_end - ig->read_ptr)
    size = ig->read_end - ig->read_ptr;

  if (size)
    memcpy(buf, ig->read_ptr, size);
  else if (ig->buf_eof) {
    IOL_DEB(fprintf(IOL_DEBs, "i_io_peekn() => 0 (eof)\n"));
    return 0;
  }
  else if (ig->error) {
    IOL_DEB(fprintf(IOL_DEBs, "i_io_peekn() => -1 (error)\n"));
    return -1;
  }
  else {
    IOL_DEB(fprintf(IOL_DEBs, "i_io_peekn() - size 0 but not eof or error!\n"));
    return -1;
  }

  IOL_DEB(fprintf(IOL_DEBs, "i_io_peekn() => %d\n", (int)size));

  return size;
}

/*
=item i_io_putc(ig, c)
=category I/O Layers

Write a single character to the stream.

On success return c, on error returns EOF

=cut
*/

int
i_io_putc_imp(io_glue *ig, int c) {
  IOL_DEB(fprintf(IOL_DEBs, "i_io_putc_imp(%p, %d)\n", ig, c));

  if (!ig->buffered) {
    char buf = c;
    ssize_t write_result;
    int result = c;

    if (ig->error)
      return EOF;

    write_result = i_io_raw_write(ig, &buf, 1);
    if (write_result != 1) {
      ig->error = 1;
      result = EOF;
      IOL_DEB(fprintf(IOL_DEBs, "  unbuffered putc() failed, setting error mode\n"));
    }
    IOL_DEB(fprintf(IOL_DEBs, "  unbuffered: result %d\n", result));

    return result;
  }

  if (ig->read_ptr)
    return EOF;

  if (ig->error)
    return EOF;

  if (!ig->buffer)
    i_io_setup_buffer(ig);

  if (ig->write_ptr && ig->write_ptr == ig->write_end) {
    if (!i_io_flush(ig))
      return EOF;
  }

  i_io_start_write(ig);

  *(ig->write_ptr)++ = c;

  return (unsigned char)c;
}

/*
=item i_io_read(io, buffer, size)
=category I/O Layers

Read up to C<size> bytes from the stream C<io> into C<buffer>.

Returns the number of bytes read.  Returns 0 on end of file.  Returns
-1 on error.

=cut
*/

ssize_t
i_io_read(io_glue *ig, void *buf, size_t size) {
  unsigned char *pbuf = buf;
  ssize_t read_total = 0;

  IOL_DEB(fprintf(IOL_DEBs, "i_io_read(%p, %p, %u)\n", ig, buf, (unsigned)size));

  if (ig->write_ptr) {
    IOL_DEB(fprintf(IOL_DEBs, "i_io_read() => -1 (write_ptr set)\n"));
    return -1;
  }

  if (!ig->buffer && ig->buffered)
    i_io_setup_buffer(ig);

  if (ig->read_ptr && ig->read_ptr < ig->read_end) {
    size_t alloc = ig->read_end - ig->read_ptr;
    
    if (alloc > size)
      alloc = size;

    memcpy(pbuf, ig->read_ptr, alloc);
    ig->read_ptr += alloc;
    pbuf += alloc;
    size -= alloc;
    read_total += alloc;
  }

  if (size > 0 && !(ig->error || ig->buf_eof)) {
    if (!ig->buffered || size > ig->buf_size) {
      ssize_t rc;
      
      while (size > 0 && (rc = i_io_raw_read(ig, pbuf, size)) > 0) {
	size -= rc;
	pbuf += rc;
	read_total += rc;
      }
      
      IOL_DEB(fprintf(IOL_DEBs, "i_io_read() => %d (raw read)\n", (int)read_total));

      if (rc < 0)
	ig->error = 1;
      else if (rc == 0)
	ig->buf_eof = 1;

      if (!read_total)
	return rc;
    }
    else {
      if (i_io_read_fill(ig, size)) {
	size_t alloc = ig->read_end - ig->read_ptr;
	if (alloc > size)
	  alloc = size;
	
	memcpy(pbuf, ig->read_ptr, alloc);
	ig->read_ptr += alloc;
	pbuf += alloc;
	size -= alloc;
	read_total += alloc;
      }
      else {
	if (!read_total && ig->error) {
	  IOL_DEB(fprintf(IOL_DEBs, "i_io_read() => -1 (fill failure)\n"));
	  return -1;
	}
      }
    }
  }

  if (!read_total && ig->error)
    read_total = -1;

  IOL_DEB(fprintf(IOL_DEBs, "i_io_read() => %d\n", (int)read_total));

  return read_total;
}

/*
=item i_io_write(io, buffer, size)
=category I/O Layers
=synopsis ssize_t result = i_io_write(io, buffer, size)

Write to the given I/O stream.

Returns the number of bytes written.

=cut
*/

ssize_t
i_io_write(io_glue *ig, const void *buf, size_t size) {
  const unsigned char *pbuf = buf;
  size_t write_count = 0;

  IOL_DEB(fprintf(IOL_DEBs, "i_io_write(%p, %p, %u)\n", ig, buf, (unsigned)size));

  if (!ig->buffered) {
    ssize_t result;

    if (ig->error) {
      IOL_DEB(fprintf(IOL_DEBs, "  unbuffered, error state\n"));
      return -1;
    }

    result = i_io_raw_write(ig, buf, size);

    if (result != size) {
      ig->error = 1;
      IOL_DEB(fprintf(IOL_DEBs, "  unbuffered, setting error flag\n"));
    }

    IOL_DEB(fprintf(IOL_DEBs, "  unbuffered, result: %d\n", (int)result));

    return result;
  }

  if (ig->read_ptr) {
    IOL_DEB(fprintf(IOL_DEBs, "i_io_write() => -1 (read_ptr set)\n"));
    return -1;
  }

  if (ig->error) {
    IOL_DEB(fprintf(IOL_DEBs, "i_io_write() => -1 (error)\n"));
    return -1;
  }

  if (!ig->buffer)
    i_io_setup_buffer(ig);

  if (!ig->write_ptr)
    i_io_start_write(ig);

  if (ig->write_ptr && ig->write_ptr + size <= ig->write_end) {
    size_t alloc = ig->write_end - ig->write_ptr;
    if (alloc > size)
      alloc = size;
    memcpy(ig->write_ptr, pbuf, alloc);
    write_count += alloc;
    size -= alloc;
    pbuf += alloc;
    ig->write_ptr += alloc;
  }

  if (size) {
    if (!i_io_flush(ig)) {
      IOL_DEB(fprintf(IOL_DEBs, "i_io_write() => %d (i_io_flush failure)\n", (int)write_count));
      return write_count ? write_count : -1;
    }

    i_io_start_write(ig);
    
    if (size > ig->buf_size) {
      ssize_t rc;
      while (size > 0 && (rc = i_io_raw_write(ig, pbuf, size)) > 0) {
	write_count += rc;
	pbuf += rc;
	size -= rc;
      }
      if (rc <= 0) {
	ig->error = 1;
	if (!write_count) {
	  IOL_DEB(fprintf(IOL_DEBs, "i_io_write() => -1 (direct write failure)\n"));
	  return -1;
	}
      }
    }
    else {
      memcpy(ig->write_ptr, pbuf, size);
      write_count += size;
      ig->write_ptr += size;
    }
  }

  IOL_DEB(fprintf(IOL_DEBs, "i_io_write() => %d\n", (int)write_count));

  return write_count;
}

/*
=item i_io_seek(io, offset, whence)
=category I/O Layers

Seek within the stream.

Acts like perl's seek.

=cut
 */

off_t
i_io_seek(io_glue *ig, off_t offset, int whence) {
  off_t new_off;

  IOL_DEB(fprintf(IOL_DEBs, "i_io_seek(%p, %ld, %d)\n", ig, (long)offset, whence));

  if (ig->write_ptr && ig->write_ptr != ig->write_end) {
    if (!i_io_flush(ig))
      return (off_t)(-1);
  }

  if (whence == SEEK_CUR && ig->read_ptr && ig->read_ptr != ig->read_end)
    offset -= ig->read_end - ig->read_ptr;

  ig->read_ptr = ig->read_end = NULL;
  ig->write_ptr = ig->write_end = NULL;
  ig->error = 0;
  ig->buf_eof = 0;
  
  new_off = i_io_raw_seek(ig, offset, whence);
  if (new_off < 0)
    ig->error = 1;

  IOL_DEB(fprintf(IOL_DEBs, "i_io_seek() => %ld\n", (long)new_off));

  return new_off;
}

/*
=item i_io_flush(io)
=category I/O Layers

Flush any buffered output.

Returns true on success,

=cut
*/

int
i_io_flush(io_glue *ig) {
  unsigned char *bufp;

  IOL_DEB(fprintf(IOL_DEBs, "i_io_flush(%p)\n", ig));

  if (ig->error) {
    IOL_DEB(fprintf(IOL_DEBs, "i_io_flush() => 0 (error set)\n", ig));
    return 0;
  }

  /* nothing to do */
  if (!ig->write_ptr)
    return 1;

  bufp = ig->buffer;
  while (bufp < ig->write_ptr) {
    ssize_t rc = i_io_raw_write(ig, bufp, ig->write_ptr - bufp);
    if (rc <= 0) {
      IOL_DEB(fprintf(IOL_DEBs, "i_io_flush() => 0 (write error)\n", ig));
      ig->error = 1;
      return 0;
    }
    
    bufp += rc;
  }

  ig->write_ptr = ig->write_end = NULL;

  IOL_DEB(fprintf(IOL_DEBs, "i_io_flush() => 1\n", ig));

  return 1;
}

/*
=item i_io_close(io)
=category I/O Layers

Flush any pending output and perform the close action for the stream.

Returns 0 on success.

=cut
*/

int
i_io_close(io_glue *ig) {
  int result = 0;

  IOL_DEB(fprintf(IOL_DEBs, "i_io_close(%p)\n", ig));
  if (ig->error)
    result = -1;

  if (ig->write_ptr && !i_io_flush(ig))
    result = -1;

  if (i_io_raw_close(ig))
    result = -1;

  IOL_DEB(fprintf(IOL_DEBs, "i_io_close() => %d\n", result));

  return result;
}

/*
=item i_io_gets(ig, buffer, size, end_of_line)
=category I/O Layers
=synopsis char buffer[BUFSIZ]
=synopsis ssize_t len = i_io_gets(buffer, sizeof(buffer), '\n');

Read up to C<size>-1 bytes from the stream C<ig> into C<buffer>.

If the byte C<end_of_line> is seen then no further bytes will be read.

Returns the number of bytes read.

Always C<NUL> terminates the buffer.

=cut
*/

ssize_t
i_io_gets(io_glue *ig, char *buffer, size_t size, int eol) {
  ssize_t read_count = 0;
  if (size < 2)
    return 0;
  --size; /* room for nul */
  while (size > 0) {
    int byte = i_io_getc(ig);
    if (byte == EOF)
      break;
    *buffer++ = byte;
    ++read_count;
    if (byte == eol)
      break;
    --size;
  }
  *buffer++ = '\0';

  return read_count;
}

/*
=item i_io_init(ig, readcb, writecb, seekcb)

Do common initialization for io_glue objects.

=cut
*/

static void
i_io_init(pIMCTX, io_glue *ig, int type, i_io_readp_t readcb, i_io_writep_t writecb,
	  i_io_seekp_t seekcb) {
  ig->type = type;
  ig->exdata = NULL;
  ig->readcb = readcb;
  ig->writecb = writecb;
  ig->seekcb = seekcb;
  ig->closecb = NULL;
  ig->sizecb = NULL;
  ig->destroycb = NULL;
  ig->context = aIMCTX;

  ig->buffer = NULL;
  ig->read_ptr = NULL;
  ig->read_end = NULL;
  ig->write_ptr = NULL;
  ig->write_end = NULL;
  ig->buf_size = IO_BUF_SIZE;
  ig->buf_eof = 0;
  ig->error = 0;
  ig->buffered = 1;
}

/*
=item i_io_set_buffered(io, buffered)
=category I/O Layers

Set the buffering mode of the stream.

If you switch buffering off on a stream with buffering on:

=over

=item *

any buffered output will be flushed.

=item *

any existing buffered input will be consumed before reads become
unbuffered.

=back

Returns true on success.  This may fail if any buffered output cannot
be flushed.

=cut
*/

int
i_io_set_buffered(io_glue *ig, int buffered) {
  if (!buffered && ig->write_ptr) {
    if (!i_io_flush(ig)) {
      ig->error = 1;
      return 0;
    }
  }
  ig->buffered = buffered;

  return 1;
}

/*
=item i_io_dump(ig)

Dump the base fields of an io_glue object to stdout.

=cut
*/
void
i_io_dump(io_glue *ig, int flags) {
  fprintf(IOL_DEBs, "ig %p:\n", ig);
  fprintf(IOL_DEBs, "  type: %d\n", ig->type);  
  fprintf(IOL_DEBs, "  exdata: %p\n", ig->exdata);
  if (flags & I_IO_DUMP_CALLBACKS) {
    fprintf(IOL_DEBs, "  readcb: %p\n", ig->readcb);
    fprintf(IOL_DEBs, "  writecb: %p\n", ig->writecb);
    fprintf(IOL_DEBs, "  seekcb: %p\n", ig->seekcb);
    fprintf(IOL_DEBs, "  closecb: %p\n", ig->closecb);
    fprintf(IOL_DEBs, "  sizecb: %p\n", ig->sizecb);
  }
  if (flags & I_IO_DUMP_BUFFER) {
    fprintf(IOL_DEBs, "  buffer: %p\n", ig->buffer);
    fprintf(IOL_DEBs, "  read_ptr: %p\n", ig->read_ptr);
    if (ig->read_ptr) {
      fprintf(IOL_DEBs, "    ");
      dump_data(ig->read_ptr, ig->read_end, 0);
      putc('\n', IOL_DEBs);
    }
    fprintf(IOL_DEBs, "  read_end: %p\n", ig->read_end);
    fprintf(IOL_DEBs, "  write_ptr: %p\n", ig->write_ptr);
    if (ig->write_ptr) {
      fprintf(IOL_DEBs, "    ");
      dump_data(ig->buffer, ig->write_ptr, 1);
      putc('\n', IOL_DEBs);
    }
    fprintf(IOL_DEBs, "  write_end: %p\n", ig->write_end);
    fprintf(IOL_DEBs, "  buf_size: %u\n", (unsigned)(ig->buf_size));
  }
  if (flags & I_IO_DUMP_STATUS) {
    fprintf(IOL_DEBs, "  buf_eof: %d\n", ig->buf_eof);
    fprintf(IOL_DEBs, "  error: %d\n", ig->error);
    fprintf(IOL_DEBs, "  buffered: %d\n", ig->buffered);
  }
}

/*
=back

=head1 INTERNAL FUNCTIONS

=over

=item my_strerror

Calls strerror() and ensures we don't return NULL.

On some platforms it's possible for strerror() to return NULL, this
wrapper ensures we only get non-NULL values.

=cut
*/

static
const char *my_strerror(int err) {
  const char *result = strerror(err);
  
  if (!result)
    result = "Unknown error";
  
  return result;
}

static void
i_io_setup_buffer(io_glue *ig) {
  ig->buffer = mymalloc(ig->buf_size);
}

static void
i_io_start_write(io_glue *ig) {
  ig->write_ptr = ig->buffer;
  ig->write_end = ig->buffer + ig->buf_size;
}

static int
i_io_read_fill(io_glue *ig, ssize_t needed) {
  unsigned char *buf_end = ig->buffer + ig->buf_size;
  unsigned char *buf_start = ig->buffer;
  unsigned char *work = ig->buffer;
  ssize_t rc;
  int good = 0;

  IOL_DEB(fprintf(IOL_DEBs, "i_io_read_fill(%p, %d)\n", ig, (int)needed));

  /* these conditions may be unused, callers should also be checking them */
  if (ig->error || ig->buf_eof)
    return 0;

  if (needed > ig->buf_size)
    needed = ig->buf_size;

  if (ig->read_ptr && ig->read_ptr < ig->read_end) {
    size_t kept = ig->read_end - ig->read_ptr;

    if (needed < kept) {
      IOL_DEB(fprintf(IOL_DEBs, "i_io_read_fill(%u) -> 1 (already have enough)\n", (unsigned)needed));
      return 1;
    }

    if (ig->read_ptr != ig->buffer)
      memmove(ig->buffer, ig->read_ptr, kept);

    good = 1; /* we have *something* available to read */
    work = buf_start + kept;
    needed -= kept;
  }
  else {
    work = ig->buffer;
  }

  /* there should always be buffer space the first time around, but
     avoid a compiler warning here */
  rc = -1;
  while (work < buf_end && (rc = i_io_raw_read(ig, work, buf_end - work)) > 0) {
    work += rc;
    good = 1;
    if (needed < rc)
      break;

    needed -= rc;
  }

  if (rc < 0) {
    ig->error = 1;
    IOL_DEB(fprintf(IOL_DEBs, " i_io_read_fill -> rc %d, setting error\n",
		    (int)rc));
  }
  else if (rc == 0) {
    ig->buf_eof = 1;
    IOL_DEB(fprintf(IOL_DEBs, " i_io_read_fill -> rc 0, setting eof\n"));
  }

  if (good) {
    ig->read_ptr = buf_start;
    ig->read_end = work;
  }
  
  IOL_DEB(fprintf(IOL_DEBs, "i_io_read_fill => %d, %u buffered\n", good,
		  (unsigned)(ig->read_end - ig->read_ptr)));
  return good;
}

/*
=item dump_data(start, end, bias)

Hex dump the data between C<start> and C<end>.

If there is more than a pleasing amount of data, either dump the
beginning (C<bias == 0>) or dump the end C(<bias != 0>) of the range.

=cut
*/

static void
dump_data(unsigned char *start, unsigned char *end, int bias) {
  unsigned char *p;
  size_t count = end - start;

  if (start == end) {
    fprintf(IOL_DEBs, "(empty)");
    return;
  }

  if (count > 15) {
    if (bias) {
      fprintf(IOL_DEBs, "... ");
      start = end - 14;
    }
    else {
      end = start + 14;
    }
      
    for (p = start; p < end; ++p) {
      fprintf(IOL_DEBs, " %02x", *p);
    }
    putc(' ', IOL_DEBs);
    putc('<', IOL_DEBs);
    for (p = start; p < end; ++p) {
      if (*p < ' ' || *p > '~')
	putc('.', IOL_DEBs);
      else
	putc(*p, IOL_DEBs);
    }
    putc('>', IOL_DEBs);
    if (!bias)
      fprintf(IOL_DEBs, " ...");
  }
  else {
    for (p = start; p < end; ++p) {
      fprintf(IOL_DEBs, " %02x", *p);
    }
    putc(' ', IOL_DEBs);
    for (p = start; p < end; ++p) {
      if (*p < ' ' || *p > '~')
	putc('.', IOL_DEBs);
      else
	putc(*p, IOL_DEBs);
    }
  }
}

/*
 * Callbacks for sources that cannot seek
 */

/*
 * Callbacks for sources that can seek 
 */

/*
=item realseek_read(ig, buf, count)

Does the reading from a source that can be seeked on

   ig    - io_glue object
   buf   - buffer to return data in
   count - number of bytes to read into buffer max

=cut
*/

static
ssize_t 
realseek_read(io_glue *igo, void *buf, size_t count) {
  io_cb        *ig = (io_cb *)igo;
  void *p          = ig->p;
  ssize_t       rc = 0;

  IOL_DEB( fprintf(IOL_DEBs, "realseek_read:  buf = %p, count = %u\n", 
		   buf, (unsigned)count) );
  rc = ig->readcb(p,buf,count);

  IOL_DEB( fprintf(IOL_DEBs, "realseek_read: rc = %d\n", (int)rc) );

  return rc;
}


/*
=item realseek_write(ig, buf, count)

Does the writing to a 'source' that can be seeked on

   ig    - io_glue object
   buf   - buffer that contains data
   count - number of bytes to write

=cut
*/

static
ssize_t 
realseek_write(io_glue *igo, const void *buf, size_t count) {
  io_cb        *ig = (io_cb *)igo;
  void          *p = ig->p;
  ssize_t       rc = 0;
  size_t        bc = 0;
  char       *cbuf = (char*)buf; 
  
  IOL_DEB( fprintf(IOL_DEBs, "realseek_write: ig = %p, buf = %p, "
		   "count = %u\n", ig, buf, (unsigned)count) );

  /* Is this a good idea? Would it be better to handle differently? 
     skip handling? */
  while( count!=bc && (rc = ig->writecb(p,cbuf+bc,count-bc))>0 ) {
    bc+=rc;
  }

  IOL_DEB( fprintf(IOL_DEBs, "realseek_write: rc = %d, bc = %u\n", (int)rc, (unsigned)bc) );
  return rc < 0 ? rc : bc;
}


/*
=item realseek_close(ig)

Closes a source that can be seeked on.  Not sure if this should be an
actual close or not.  Does nothing for now.  Should be fixed.

   ig - data source

=cut */

static
int
realseek_close(io_glue *igo) {
  io_cb *ig = (io_cb *)igo;
  dIMCTXio(igo);

  IOL_DEB(fprintf(IOL_DEBs, "realseek_close(%p)\n", ig));
  im_log((aIMCTX,1, "realseek_close(ig %p)\n", ig));
  if (ig->closecb)
    return ig->closecb(ig->p);
  else
    return 0;
}


/*
=item realseek_seek(ig, offset, whence)

Implements seeking for a source that is seekable, the purpose of having this is to be able to
have an offset into a file that is different from what the underlying library thinks.

   ig     - data source
   offset - offset into stream
   whence - whence argument a la lseek

=cut
*/

static
off_t
realseek_seek(io_glue *igo, off_t offset, int whence) {
  io_cb *ig = (io_cb *)igo;
  void *p = ig->p;
  off_t rc;
  IOL_DEB( fprintf(IOL_DEBs, "realseek_seek(ig %p, offset %ld, whence %d)\n", ig, (long) offset, whence) );
  rc = ig->seekcb(p, offset, whence);

  IOL_DEB( fprintf(IOL_DEBs, "realseek_seek: rc %ld\n", (long) rc) );
  return rc;
  /* FIXME: How about implementing this offset handling stuff? */
}

static
void
realseek_destroy(io_glue *igo) {
  io_cb *ig = (io_cb *)igo;

  if (ig->destroycb)
    ig->destroycb(ig->p);
}

/*
 * Callbacks for sources that are a fixed size buffer
 */

/*
=item buffer_read(ig, buf, count)

Does the reading from a buffer source

   ig    - io_glue object
   buf   - buffer to return data in
   count - number of bytes to read into buffer max

=cut
*/

static
ssize_t 
buffer_read(io_glue *igo, void *buf, size_t count) {
  io_buffer *ig = (io_buffer *)igo;

  IOL_DEB( fprintf(IOL_DEBs, "buffer_read: ig->cpos = %ld, buf = %p, count = %u\n", (long) ig->cpos, buf, (unsigned)count) );

  if ( ig->cpos+count > ig->len ) {
    dIMCTXio(igo);
    im_log((aIMCTX, 1,"buffer_read: short read: cpos=%ld, len=%ld, count=%ld\n", (long)ig->cpos, (long)ig->len, (long)count));
    count = ig->len - ig->cpos;
  }
  
  memcpy(buf, ig->data+ig->cpos, count);
  ig->cpos += count;
  IOL_DEB( fprintf(IOL_DEBs, "buffer_read: count = %ld\n", (long)count) );
  return count;
}


/*
=item buffer_write(ig, buf, count)

Does nothing, returns -1

   ig    - io_glue object
   buf   - buffer that contains data
   count - number of bytes to write

=cut
*/

static
ssize_t 
buffer_write(io_glue *ig, const void *buf, size_t count) {
  dIMCTXio(ig);
  im_log((aIMCTX, 1, "buffer_write called, this method should never be called.\n"));
  return -1;
}


/*
=item buffer_close(ig)

Closes a source that can be seeked on.  Not sure if this should be an actual close
or not.  Does nothing for now.  Should be fixed.

   ig - data source

=cut
*/

static
int
buffer_close(io_glue *ig) {
  dIMCTXio(ig);
  im_log((aIMCTX, 1, "buffer_close(ig %p)\n", ig));

  return 0;
}


/*
=item buffer_seek(ig, offset, whence)

Implements seeking for a buffer source.

   ig     - data source
   offset - offset into stream
   whence - whence argument a la lseek

=cut
*/

static
off_t
buffer_seek(io_glue *igo, off_t offset, int whence) {
  io_buffer *ig = (io_buffer *)igo;
  off_t reqpos = 
    calc_seek_offset(ig->cpos, ig->len, offset, whence);
  
  if (reqpos > ig->len) {
    dIMCTXio(igo);
    im_log((aIMCTX, 1, "seeking out of readable range\n"));
    return (off_t)-1;
  }
  if (reqpos < 0) {
    dIMCTXio(igo);
    i_push_error(0, "seek before beginning of file");
    return (off_t)-1;
  }
  
  ig->cpos = reqpos;
  IOL_DEB( fprintf(IOL_DEBs, "buffer_seek(ig %p, offset %ld, whence %d)\n", ig, (long) offset, whence) );

  return reqpos;
  /* FIXME: How about implementing this offset handling stuff? */
}

static
void
buffer_destroy(io_glue *igo) {
  io_buffer *ig = (io_buffer *)igo;

  if (ig->closecb) {
    dIMCTXio(igo);
    im_log((aIMCTX, 1,"calling close callback %p for io_buffer\n", 
	    ig->closecb));
    ig->closecb(ig->closedata);
  }
}



/*
 * Callbacks for sources that are a chain of variable sized buffers
 */



/* Helper functions for buffer chains */

static
io_blink*
io_blink_new(void) {
  io_blink *ib;

#if 0
  im_log((aIMCTX, 1, "io_blink_new()\n"));
#endif

  ib = mymalloc(sizeof(io_blink));

  ib->next = NULL;
  ib->prev = NULL;
  ib->len  = BBSIZ;

  memset(&ib->buf, 0, ib->len);
  return ib;
}



/*
=item io_bchain_advance(ieb)

Advances the buffer chain to the next link - extending if
necessary.  Also adjusts the cpos and tfill counters as needed.

   ieb   - buffer chain object

=cut
*/

static
void
io_bchain_advance(io_ex_bchain *ieb) {
  if (ieb->cp->next == NULL) {
    ieb->tail = io_blink_new();
    ieb->tail->prev = ieb->cp;
    ieb->cp->next   = ieb->tail;

    ieb->tfill = 0; /* Only set this if we added a new slice */
  }
  ieb->cp    = ieb->cp->next;
  ieb->cpos  = 0;
}



/*
=item io_bchain_destroy()

frees all resources used by a buffer chain.

=cut
*/

static void
io_destroy_bufchain(io_ex_bchain *ieb) {
  io_blink *cp;
#if 0
  mm_log((1, "io_destroy_bufchain(ieb %p)\n", ieb));
#endif
  cp = ieb->head;
  
  while(cp) {
    io_blink *t = cp->next;
    myfree(cp);
    cp = t;
  }
}




/*

static
void
bufchain_dump(io_ex_bchain *ieb) {
  mm_log((1, "  buf_chain_dump(ieb %p)\n"));
  mm_log((1, "  buf_chain_dump: ieb->offset = %d\n", ieb->offset));
  mm_log((1, "  buf_chain_dump: ieb->length = %d\n", ieb->length));
  mm_log((1, "  buf_chain_dump: ieb->head   = %p\n", ieb->head  ));
  mm_log((1, "  buf_chain_dump: ieb->tail   = %p\n", ieb->tail  ));
  mm_log((1, "  buf_chain_dump: ieb->tfill  = %d\n", ieb->tfill ));
  mm_log((1, "  buf_chain_dump: ieb->cp     = %p\n", ieb->cp    ));
  mm_log((1, "  buf_chain_dump: ieb->cpos   = %d\n", ieb->cpos  ));
  mm_log((1, "  buf_chain_dump: ieb->gpos   = %d\n", ieb->gpos  ));
}
*/

/*
 * TRUE if lengths are NOT equal
 */

/*
static
void
chainlencert( io_glue *ig ) {
  int clen;
  int cfl           = 0;
  size_t csize      = 0;
  size_t cpos       = 0;
  io_ex_bchain *ieb = ig->exdata;
  io_blink *cp      = ieb->head;
  

  if (ieb->gpos > ieb->length) mm_log((1, "BBAR : ieb->gpos = %d, ieb->length = %d\n", ieb->gpos, ieb->length));

  while(cp) {
    clen = (cp == ieb->tail) ? ieb->tfill : cp->len;
    if (ieb->head == cp && cp->prev) mm_log((1, "Head of chain has a non null prev\n"));
    if (ieb->tail == cp && cp->next) mm_log((1, "Tail of chain has a non null next\n"));
    
    if (ieb->head != cp && !cp->prev) mm_log((1, "Middle of chain has a null prev\n"));
    if (ieb->tail != cp && !cp->next) mm_log((1, "Middle of chain has a null next\n"));
    
    if (cp->prev && cp->prev->next != cp) mm_log((1, "%p = cp->prev->next != cp\n", cp->prev->next));
    if (cp->next && cp->next->prev != cp) mm_log((1, "%p cp->next->prev != cp\n", cp->next->prev));

    if (cp == ieb->cp) {
      cfl = 1;
      cpos += ieb->cpos;
    }

    if (!cfl) cpos += clen;

    csize += clen;
    cp     = cp->next;
  }
  if (( csize != ieb->length )) mm_log((1, "BAR : csize = %d, ieb->length = %d\n", csize, ieb->length));
  if (( cpos  != ieb->gpos   )) mm_log((1, "BAR : cpos  = %d, ieb->gpos   = %d\n", cpos,  ieb->gpos  ));
}


static
void
chaincert( io_glue *ig) {
  size_t csize   = 0;
  io_ex_bchain *ieb = ig->exdata;
  io_blink *cp   = ieb->head;
  
  mm_log((1, "Chain verification.\n"));

  mm_log((1, "  buf_chain_dump: ieb->offset = %d\n", ieb->offset));
  mm_log((1, "  buf_chain_dump: ieb->length = %d\n", ieb->length));
  mm_log((1, "  buf_chain_dump: ieb->head   = %p\n", ieb->head  ));
  mm_log((1, "  buf_chain_dump: ieb->tail   = %p\n", ieb->tail  ));
  mm_log((1, "  buf_chain_dump: ieb->tfill  = %d\n", ieb->tfill ));
  mm_log((1, "  buf_chain_dump: ieb->cp     = %p\n", ieb->cp    ));
  mm_log((1, "  buf_chain_dump: ieb->cpos   = %d\n", ieb->cpos  ));
  mm_log((1, "  buf_chain_dump: ieb->gpos   = %d\n", ieb->gpos  ));

  while(cp) {
    int clen = cp == ieb->tail ? ieb->tfill : cp->len;
    mm_log((1, "link: %p <- %p -> %p\n", cp->prev, cp, cp->next));
    if (ieb->head == cp && cp->prev) mm_log((1, "Head of chain has a non null prev\n"));
    if (ieb->tail == cp && cp->next) mm_log((1, "Tail of chain has a non null next\n"));
    
    if (ieb->head != cp && !cp->prev) mm_log((1, "Middle of chain has a null prev\n"));
    if (ieb->tail != cp && !cp->next) mm_log((1, "Middle of chain has a null next\n"));
    
    if (cp->prev && cp->prev->next != cp) mm_log((1, "%p = cp->prev->next != cp\n", cp->prev->next));
    if (cp->next && cp->next->prev != cp) mm_log((1, "%p cp->next->prev != cp\n", cp->next->prev));

    csize += clen;
    cp     = cp->next;
  }

  mm_log((1, "csize = %d %s ieb->length = %d\n", csize, csize == ieb->length ? "==" : "!=", ieb->length));
}
*/

/*
=item bufchain_read(ig, buf, count)

Does the reading from a source that can be seeked on

   ig    - io_glue object
   buf   - buffer to return data in
   count - number of bytes to read into buffer max

=cut
*/

static
ssize_t 
bufchain_read(io_glue *ig, void *buf, size_t count) {
  io_ex_bchain *ieb = ig->exdata;
  size_t     scount = count;
  char        *cbuf = buf;
  size_t         sk;
  dIMCTXio(ig);

  im_log((aIMCTX, 1, "bufchain_read(ig %p, buf %p, count %ld)\n", ig, buf, (long)count));

  while( scount ) {
    int clen = (ieb->cp == ieb->tail) ? ieb->tfill : ieb->cp->len;
    if (clen == ieb->cpos) {
      if (ieb->cp == ieb->tail) break; /* EOF */
      ieb->cp = ieb->cp->next;
      ieb->cpos = 0;
      clen = (ieb->cp == ieb->tail) ? ieb->tfill : ieb->cp->len;
    }

    sk = clen - ieb->cpos;
    sk = sk > scount ? scount : sk;

    memcpy(&cbuf[count-scount], &ieb->cp->buf[ieb->cpos], sk);
    scount    -= sk;
    ieb->cpos += sk;
    ieb->gpos += sk;
  }

  im_log((aIMCTX, 1, "bufchain_read: returning %ld\n", (long)(count-scount)));
  return count-scount;
}





/*
=item bufchain_write(ig, buf, count)

Does the writing to a 'source' that can be seeked on

   ig    - io_glue object
   buf   - buffer that contains data
   count - number of bytes to write

=cut
*/

static
ssize_t
bufchain_write(io_glue *ig, const void *buf, size_t count) {
  char *cbuf = (char *)buf;
  io_ex_bchain *ieb = ig->exdata;
  size_t         ocount = count;
  size_t         sk;
  dIMCTXio(ig);

  im_log((aIMCTX, 1, "bufchain_write: ig = %p, buf = %p, count = %ld\n", ig, buf, (long)count));

  IOL_DEB( fprintf(IOL_DEBs, "bufchain_write: ig = %p, ieb->cpos = %ld, buf = %p, count = %ld\n", ig, (long) ieb->cpos, buf, (long)count) );
  
  while(count) {
    im_log((aIMCTX, 2, "bufchain_write: - looping - count = %ld\n", (long)count));
    if (ieb->cp->len == ieb->cpos) {
      im_log((aIMCTX, 1, "bufchain_write: cp->len == ieb->cpos = %ld - advancing chain\n", (long) ieb->cpos));
      io_bchain_advance(ieb);
    }

    sk = ieb->cp->len - ieb->cpos;
    sk = sk > count ? count : sk;
    memcpy(&ieb->cp->buf[ieb->cpos], &cbuf[ocount-count], sk);

    if (ieb->cp == ieb->tail) {
      int extend = ieb->cpos + sk - ieb->tfill;
      im_log((aIMCTX, 2, "bufchain_write: extending tail by %d\n", extend));
      if (extend > 0) {
	ieb->length += extend;
	ieb->tfill  += extend;
      }
    }

    ieb->cpos += sk;
    ieb->gpos += sk;
    count     -= sk;
  }
  return ocount;
}

/*
=item bufchain_close(ig)

Closes a source that can be seeked on.  Not sure if this should be an actual close
or not.  Does nothing for now.  Should be fixed.

   ig - data source

=cut
*/

static
int
bufchain_close(io_glue *ig) {
  dIMCTXio(ig);
  im_log((aIMCTX, 1, "bufchain_close(ig %p)\n",ig));
  IOL_DEB( fprintf(IOL_DEBs, "bufchain_close(ig %p)\n", ig) );

  return 0;  
}


/*
=item bufchain_seek(ig, offset, whence)

Implements seeking for a source that is seekable, the purpose of having this is to be able to
have an offset into a file that is different from what the underlying library thinks.

   ig     - data source
   offset - offset into stream
   whence - whence argument a la lseek

=cut
*/

static
off_t
bufchain_seek(io_glue *ig, off_t offset, int whence) {
  io_ex_bchain *ieb = ig->exdata;
  int wrlen;

  off_t scount = calc_seek_offset(ieb->gpos, ieb->length, offset, whence);
  off_t sk;
  dIMCTXio(ig);

  im_log((aIMCTX, 1, "bufchain_seek(ig %p, offset %ld, whence %d)\n", ig, (long)offset, whence));

  if (scount < 0) {
    i_push_error(0, "invalid whence supplied or seek before start of file");
    return (off_t)-1;
  }

  ieb->cp   = ieb->head;
  ieb->cpos = 0;
  ieb->gpos = 0;
  
  while( scount ) {
    int clen = (ieb->cp == ieb->tail) ? ieb->tfill : ieb->cp->len;
    if (clen == ieb->cpos) {
      if (ieb->cp == ieb->tail) break; /* EOF */
      ieb->cp = ieb->cp->next;
      ieb->cpos = 0;
      clen = (ieb->cp == ieb->tail) ? ieb->tfill : ieb->cp->len;
    }
    
    sk = clen - ieb->cpos;
    sk = sk > scount ? scount : sk;
    
    scount    -= sk;
    ieb->cpos += sk;
    ieb->gpos += sk;
  }
  
  wrlen = scount;

  if (wrlen > 0) { 
    /*
     * extending file - get ieb into consistent state and then
     * call write which will get it to the correct position 
     */
    char TB[BBSIZ];
    memset(TB, 0, BBSIZ);
    ieb->gpos = ieb->length;
    ieb->cpos = ieb->tfill;
    
    while(wrlen > 0) {
      ssize_t rc, wl = i_min(wrlen, BBSIZ);
      im_log((aIMCTX, 1, "bufchain_seek: wrlen = %d, wl = %ld\n", wrlen, (long)wl));
      rc = bufchain_write( ig, TB, wl );
      if (rc != wl) im_fatal(aIMCTX, 0, "bufchain_seek: Unable to extend file\n");
      wrlen -= rc;
    }
  }

  im_log((aIMCTX, 2, "bufchain_seek: returning ieb->gpos = %ld\n", (long)ieb->gpos));
  return ieb->gpos;
}

static
void
bufchain_destroy(io_glue *ig) {
  io_ex_bchain *ieb = ig->exdata;

  io_destroy_bufchain(ieb);

  myfree(ieb);
}

/*
=item fd_read(ig, buf, count)

Read callback for file descriptor IO objects.

=cut
*/
static ssize_t fd_read(io_glue *igo, void *buf, size_t count) {
  io_fdseek *ig = (io_fdseek *)igo;
  ssize_t result;
#ifdef _MSC_VER
  result = _read(ig->fd, buf, count);
#else
  result = read(ig->fd, buf, count);
#endif

  IOL_DEB(fprintf(IOL_DEBs, "fd_read(%p, %p, %u) => %d\n", ig, buf,
		  (unsigned)count, (int)result));

  /* 0 is valid - means EOF */
  if (result < 0) {
    dIMCTXio(igo);
    im_push_errorf(aIMCTX, 0, "read() failure: %s (%d)", my_strerror(errno), errno);
  }

  return result;
}

static ssize_t fd_write(io_glue *igo, const void *buf, size_t count) {
  io_fdseek *ig = (io_fdseek *)igo;
  ssize_t result;
#ifdef _MSC_VER
  result = _write(ig->fd, buf, count);
#else
  result = write(ig->fd, buf, count);
#endif

  IOL_DEB(fprintf(IOL_DEBs, "fd_write(%p, %p, %u) => %d\n", ig, buf,
		  (unsigned)count, (int)result));

  if (result <= 0) {
    dIMCTXio(igo);
    im_push_errorf(aIMCTX, errno, "write() failure: %s (%d)", my_strerror(errno), errno);
  }

  return result;
}

static off_t fd_seek(io_glue *igo, off_t offset, int whence) {
  io_fdseek *ig = (io_fdseek *)igo;
  off_t result;
#ifdef _MSC_VER
  result = _lseek(ig->fd, offset, whence);
#else
  result = lseek(ig->fd, offset, whence);
#endif

  if (result == (off_t)-1) {
    dIMCTXio(igo);
    im_push_errorf(aIMCTX, errno, "lseek() failure: %s (%d)", my_strerror(errno), errno);
  }

  return result;
}

static int fd_close(io_glue *ig) {
  /* no, we don't close it */
  return 0;
}

static ssize_t fd_size(io_glue *ig) {
  dIMCTXio(ig);
  im_log((aIMCTX, 1, "fd_size(ig %p) unimplemented\n", ig));
  
  return -1;
}


/*
=back

=head1 AUTHOR

Arnar M. Hrafnkelsson <addi@umich.edu>

=head1 SEE ALSO

Imager(3)

=cut
*/
