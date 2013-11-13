#include "imager.h"
#include "imageri.h"
#include <stdlib.h>
#ifndef _MSC_VER
#include <unistd.h>
#endif


/* FIXME: make allocation dynamic */


#ifdef IMAGER_DEBUG_MALLOC

#define MAXMAL 102400
#define MAXDESC 65

#define UNDRRNVAL 10
#define OVERRNVAL 10

#define PADBYTE 0xaa


static int malloc_need_init = 1;

typedef struct {
  void* ptr;
  size_t size;
  const char *file;
  int line;
} malloc_entry;

malloc_entry malloc_pointers[MAXMAL];




/* Utility functions */


static
void
malloc_init(void) {
  int i;
  for(i=0; i<MAXMAL; i++) malloc_pointers[i].ptr = NULL;
  malloc_need_init = 0;
  atexit(malloc_state);
}


static
int 
find_ptr(void *p) {
  int i;
  for(i=0;i<MAXMAL;i++)
    if (malloc_pointers[i].ptr == p)
      return i;
  return -1;
}


/* Takes a pointer to real start of array,
 * sets the entries in the table, returns
 * the offset corrected pointer */

static
void *
set_entry(int i, char *buf, size_t size, char *file, int line) {
  memset( buf, PADBYTE, UNDRRNVAL );
  memset( &buf[UNDRRNVAL+size], PADBYTE, OVERRNVAL );
  buf += UNDRRNVAL;
  malloc_pointers[i].ptr  = buf;
  malloc_pointers[i].size = size;
  malloc_pointers[i].file = file;
  malloc_pointers[i].line = line;
  return buf;
}

void
malloc_state(void) {
  int i;
  size_t total = 0;

  i_clear_error();
  mm_log((0,"malloc_state()\n"));
  bndcheck_all();
  for(i=0; i<MAXMAL; i++) if (malloc_pointers[i].ptr != NULL) {
      mm_log((0,"%d: %lu (%p) : %s (%d)\n", i, (unsigned long)malloc_pointers[i].size, malloc_pointers[i].ptr, malloc_pointers[i].file, malloc_pointers[i].line));
    total += malloc_pointers[i].size;
  }
  if (total == 0) mm_log((0,"No memory currently used!\n"))
    else mm_log((0,"total: %lu\n", (unsigned long)total));
}



void*
mymalloc_file_line(size_t size, char* file, int line) {
  char *buf;
  int i;
  if (malloc_need_init) malloc_init();
  
  /* bndcheck_all(); Uncomment for LOTS OF THRASHING */
  
  if ( (i = find_ptr(NULL)) < 0 ) {
    mm_log((0,"more than %d segments allocated at %s (%d)\n", MAXMAL, file, line));
    exit(3);
  }

  if ( (buf = malloc(size+UNDRRNVAL+OVERRNVAL)) == NULL ) {
    mm_log((1,"Unable to allocate %ld for %s (%i)\n", (long)size, file, line));
    exit(3);
  }
  
  buf = set_entry(i, buf, size, file, line);
  mm_log((1,"mymalloc_file_line: slot <%d> %ld bytes allocated at %p for %s (%d)\n", i, (long)size, buf, file, line));
  return buf;
}

void *
(mymalloc)(size_t size) {
  return mymalloc_file_line(size, "unknown", 0);
}

void*
myrealloc_file_line(void *ptr, size_t newsize, char* file, int line) {
  char *buf;
  int i;

  if (malloc_need_init) malloc_init();
  /* bndcheck_all(); ACTIVATE FOR LOTS OF THRASHING */
  
  if (!ptr) {
    mm_log((1, "realloc called with ptr = NULL, sending request to malloc\n"));
    return mymalloc_file_line(newsize, file, line);
  }
  
  if (!newsize) {
    mm_log((1, "newsize = 0, sending request to free\n"));
    myfree_file_line(ptr, file, line);
    return NULL;
  }

  if ( (i = find_ptr(ptr)) == -1) {
    mm_log((0, "Unable to find %p in realloc for %s (%i)\n", ptr, file, line));
    exit(3);
  }
  
  if ( (buf = realloc(((char *)ptr)-UNDRRNVAL, UNDRRNVAL+OVERRNVAL+newsize)) == NULL ) {
    mm_log((1,"Unable to reallocate %ld bytes at %p for %s (%i)\n", (long)
	    newsize, ptr, file, line));
    exit(3); 
  }
  
  buf = set_entry(i, buf, newsize, file, line);
  mm_log((1,"realloc_file_line: slot <%d> %ld bytes allocated at %p for %s (%d)\n", i, (long)newsize, buf, file, line));
  return buf;
}

void *
(myrealloc)(void *ptr, size_t newsize) {
  return myrealloc_file_line(ptr, newsize, "unknown", 0);
}

static
void
bndcheck(int idx) {
  int i;
  size_t s = malloc_pointers[idx].size;
  unsigned char *pp = malloc_pointers[idx].ptr;
  if (!pp) {
    mm_log((1, "bndcheck: No pointer in slot %d\n", idx));
    return;
  }
  
  for(i=0;i<UNDRRNVAL;i++) {
    if (pp[-(1+i)] != PADBYTE)
      mm_log((1,"bndcheck: UNDERRUN OF %d bytes detected: slot = %d, point = %p, size = %ld\n", i+1, idx, pp, (long)s ));
  }
  
  for(i=0;i<OVERRNVAL;i++) {
    if (pp[s+i] != PADBYTE)
      mm_log((1,"bndcheck: OVERRUN OF %d bytes detected: slot = %d, point = %p, size = %ld\n", i+1, idx, pp, (long)s ));
  }
}

void
bndcheck_all() {
  int idx;
  mm_log((1, "bndcheck_all()\n"));
  for(idx=0; idx<MAXMAL; idx++)
    if (malloc_pointers[idx].ptr)
      bndcheck(idx);
}

void
myfree_file_line(void *p, char *file, int line) {
  char  *pp = p;
  int match = 0;
  int i;

  if (p == NULL)
    return;
  
  for(i=0; i<MAXMAL; i++) if (malloc_pointers[i].ptr == p) {
      mm_log((1,"myfree_file_line: pointer %i (%s (%d)) freed at %s (%i)\n", i, malloc_pointers[i].file, malloc_pointers[i].line, file, line));
    bndcheck(i);
    malloc_pointers[i].ptr = NULL;
    match++;
  }

  mm_log((1, "myfree_file_line: freeing address %p (real %p)\n", pp, pp-UNDRRNVAL));
  
  if (match != 1) {
    mm_log((1, "myfree_file_line: INCONSISTENT REFCOUNT %d at %s (%i)\n", match, file, line));
    fprintf(stderr, "myfree_file_line: INCONSISTENT REFCOUNT %d at %s (%i)\n", match, file, line);
		exit(255);
  }
  
  
  free(pp-UNDRRNVAL);
}

void
(myfree)(void *block) {
  myfree_file_line(block, "unknown", 0);
}

#else 

void
malloc_state() {
}

void*
mymalloc(size_t size) {
  void *buf;

  if (size < 0) {
    fprintf(stderr, "Attempt to allocate size %ld\n", (long)size);
    exit(3);
  }

  if ( (buf = malloc(size)) == NULL ) {
    mm_log((1, "mymalloc: unable to malloc %ld\n", (long)size));
    fprintf(stderr,"Unable to malloc %ld.\n", (long)size); exit(3);
  }
  mm_log((1, "mymalloc(size %ld) -> %p\n", (long)size, buf));
  return buf;
}

void *
mymalloc_file_line(size_t size, char *file, int line) {
  return mymalloc(size);
}

void
myfree(void *p) {
  mm_log((1, "myfree(p %p)\n", p));
  free(p);
}

void
myfree_file_line(void *p, char *file, int line) {
  myfree(p);
}

void *
myrealloc(void *block, size_t size) {
  void *result;

  mm_log((1, "myrealloc(block %p, size %ld)\n", block, (long)size));
  if ((result = realloc(block, size)) == NULL) {
    mm_log((1, "myrealloc: out of memory\n"));
    fprintf(stderr, "Out of memory.\n");
    exit(3);
  }
  return result;
}

void *
myrealloc_file_line(void *block, size_t newsize, char *file, int size) {
  return myrealloc(block, newsize);
}

#endif /* IMAGER_MALLOC_DEBUG */




/* memory pool implementation */

void
i_mempool_init(i_mempool *mp) {
  mp->alloc = 10;
  mp->used  = 0;
  mp->p = mymalloc(sizeof(void*)*mp->alloc);
}

void
i_mempool_extend(i_mempool *mp) {
  mp->p = myrealloc(mp->p, mp->alloc * 2);
  mp->alloc *=2;
}

void *
i_mempool_alloc(i_mempool *mp, size_t size) {
  if (mp->used == mp->alloc) i_mempool_extend(mp);
  mp->p[mp->used] = mymalloc(size);
  mp->used++;
  return mp->p[mp->used-1];
}


void
i_mempool_destroy(i_mempool *mp) {
  unsigned int i;
  for(i=0; i<mp->used; i++) myfree(mp->p[i]);
  myfree(mp->p);
}



/* Should these really be here? */

#undef min
#undef max

i_img_dim
i_minx(i_img_dim a, i_img_dim b) {
  if (a<b) return a; else return b;
}

i_img_dim
i_maxx(i_img_dim a, i_img_dim b) {
  if (a>b) return a; else return b;
}


struct utf8_size {
  int mask, expect;
  int size;
};

struct utf8_size utf8_sizes[] =
{
  { 0x80, 0x00, 1 },
  { 0xE0, 0xC0, 2 },
  { 0xF0, 0xE0, 3 },
  { 0xF8, 0xF0, 4 },
};

/*
=item i_utf8_advance(char **p, size_t *len)

Retrieve a C<UTF-8> character from the stream.

Modifies *p and *len to indicate the consumed characters.

This doesn't support the extended C<UTF-8> encoding used by later
versions of Perl.  Since this is typically used to implement text
output by font drivers, the strings supplied shouldn't have such out
of range characters.

This doesn't check that the C<UTF-8> character is using the shortest
possible representation.

Returns ~0UL on failure.

=cut
*/

unsigned long 
i_utf8_advance(char const **p, size_t *len) {
  unsigned char c;
  int i, ci, clen = 0;
  unsigned char codes[3];
  if (*len == 0)
    return ~0UL;
  c = *(*p)++; --*len;

  for (i = 0; i < sizeof(utf8_sizes)/sizeof(*utf8_sizes); ++i) {
    if ((c & utf8_sizes[i].mask) == utf8_sizes[i].expect) {
      clen = utf8_sizes[i].size;
      break;
    }
  }
  if (clen == 0 || *len < clen-1) {
    --*p; ++*len;
    return ~0UL;
  }

  /* check that each character is well formed */
  i = 1;
  ci = 0;
  while (i < clen) {
    if (((*p)[ci] & 0xC0) != 0x80) {
      --*p; ++*len;
      return ~0UL;
    }
    codes[ci] = (*p)[ci];
    ++ci; ++i;
  }
  *p += clen-1; *len -= clen-1;
  if (c & 0x80) {
    if ((c & 0xE0) == 0xC0) {
      return ((c & 0x1F) << 6) + (codes[0] & 0x3F);
    }
    else if ((c & 0xF0) == 0xE0) {
      return ((c & 0x0F) << 12) | ((codes[0] & 0x3F) << 6) | (codes[1] & 0x3f);
    }
    else if ((c & 0xF8) == 0xF0) {
      return ((c & 0x07) << 18) | ((codes[0] & 0x3F) << 12) 
              | ((codes[1] & 0x3F) << 6) | (codes[2] & 0x3F);
    }
    else {
      *p -= clen; *len += clen;
      return ~0UL;
    }
  }
  else {
    return c;
  }
}

