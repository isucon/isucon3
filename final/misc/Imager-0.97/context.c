#include "imageri.h"
#include <stdio.h>

static volatile im_slot_t slot_count = 1;
static im_slot_destroy_t *volatile slot_destructors;
static volatile i_mutex_t slot_mutex;

/*
=item im_context_new()

Create a new Imager context object.

=cut
*/

im_context_t
im_context_new(void) {
  im_context_t ctx = malloc(sizeof(im_context_struct));
  int i;

  if (!slot_mutex)
    slot_mutex = i_mutex_new();

  if (!ctx)
    return NULL;
  
  ctx->error_sp = IM_ERROR_COUNT-1;
  for (i = 0; i < IM_ERROR_COUNT; ++i) {
    ctx->error_alloc[i] = 0;
    ctx->error_stack[i].msg = NULL;
    ctx->error_stack[i].code = 0;
  }
#ifdef IMAGER_LOG
  ctx->log_level = 0;
  ctx->lg_file = NULL;
#endif
  ctx->max_width = 0;
  ctx->max_height = 0;
  ctx->max_bytes = DEF_BYTES_LIMIT;

  ctx->slot_alloc = slot_count;
  ctx->slots = calloc(sizeof(void *), ctx->slot_alloc);
  if (!ctx->slots) {
    free(ctx);
    return NULL;
  }

  ctx->refcount = 1;

#ifdef IMAGER_TRACE_CONTEXT
  fprintf(stderr, "im_context: created %p\n", ctx);
#endif


  return ctx;
}

/*
=item im_context_refinc(ctx, where)
X<im_context_refinc API>
=section Context objects
=synopsis im_context_refinc(aIMCTX, "a description");

Add a new reference to the context.

=cut
*/

void
im_context_refinc(im_context_t ctx, const char *where) {
  ++ctx->refcount;

#ifdef IMAGER_TRACE_CONTEXT
  fprintf(stderr, "im_context:%s: refinc %p (count now %lu)\n", where,
	  ctx, (unsigned long)ctx->refcount);
#endif
}

/*
=item im_context_refdec(ctx, where)
X<im_context_refdec API>
=section Context objects
=synopsis im_context_refdec(aIMCTX, "a description");

Remove a reference to the context, releasing it if all references have
been removed.

=cut
*/

void
im_context_refdec(im_context_t ctx, const char *where) {
  int i;
  im_slot_t slot;

  im_assert(ctx->refcount > 0);

  --ctx->refcount;

#ifdef IMAGER_TRACE_CONTEXT
  fprintf(stderr, "im_context:%s: delete %p (count now %lu)\n", where,
	  ctx, (unsigned long)ctx->refcount);
#endif

  if (ctx->refcount != 0)
    return;

  /* lock here to avoid slot_destructors from being moved under us */
  i_mutex_lock(slot_mutex);
  for (slot = 0; slot < ctx->slot_alloc; ++slot) {
    if (ctx->slots[slot] && slot_destructors[slot])
      slot_destructors[slot](ctx->slots[slot]);
  }
  i_mutex_unlock(slot_mutex);

  free(ctx->slots);

  for (i = 0; i < IM_ERROR_COUNT; ++i) {
    if (ctx->error_stack[i].msg)
      myfree(ctx->error_stack[i].msg);
  }
#ifdef IMAGER_LOG
  if (ctx->lg_file && ctx->own_log)
    fclose(ctx->lg_file);
#endif

  free(ctx);
}

/*
=item im_context_clone(ctx)

Clone an Imager context object, returning the result.

The error stack is not copied from the original context.

=cut
*/

im_context_t
im_context_clone(im_context_t ctx, const char *where) {
  im_context_t nctx = malloc(sizeof(im_context_struct));
  int i;

  if (!nctx)
    return NULL;

  nctx->slot_alloc = slot_count;
  nctx->slots = calloc(sizeof(void *), nctx->slot_alloc);
  if (!nctx->slots) {
    free(nctx);
    return NULL;
  }

  nctx->error_sp = IM_ERROR_COUNT-1;
  for (i = 0; i < IM_ERROR_COUNT; ++i) {
    nctx->error_alloc[i] = 0;
    nctx->error_stack[i].msg = NULL;
  }
#ifdef IMAGER_LOG
  nctx->log_level = ctx->log_level;
  if (ctx->lg_file) {
    if (ctx->own_log) {
      int newfd = dup(fileno(ctx->lg_file));
      nctx->own_log = 1;
      nctx->lg_file = fdopen(newfd, "w");
      if (nctx->lg_file)
	setvbuf(nctx->lg_file, NULL, _IONBF, BUFSIZ);
    }
    else {
      /* stderr */
      nctx->lg_file = ctx->lg_file;
      nctx->own_log = 0;
    }
  }
  else {
    nctx->lg_file = NULL;
  }
#endif
  nctx->max_width = ctx->max_width;
  nctx->max_height = ctx->max_height;
  nctx->max_bytes = ctx->max_bytes;

  nctx->refcount = 1;

#ifdef IMAGER_TRACE_CONTEXT
  fprintf(stderr, "im_context:%s: cloned %p to %p\n", where, ctx, nctx);
#endif

  return nctx;
}

/*
=item im_context_slot_new(destructor)

Allocate a new context-local-storage slot.

C<desctructor> will be called when the context is destroyed if the
corresponding slot is non-NULL.

=cut
*/

im_slot_t
im_context_slot_new(im_slot_destroy_t destructor) {
  im_slot_t new_slot;
  im_slot_destroy_t *new_destructors;
  if (!slot_mutex)
    slot_mutex = i_mutex_new();

  i_mutex_lock(slot_mutex);

  new_slot = slot_count++;
  new_destructors = realloc(slot_destructors, sizeof(void *) * slot_count);
  if (!new_destructors)
    i_fatal(1, "Cannot allocate memory for slot destructors");
  slot_destructors = new_destructors;

  slot_destructors[new_slot] = destructor;

  i_mutex_unlock(slot_mutex);

  return new_slot;
}

/*
=item im_context_slot_set(slot, value)

Set the value of a slot.

Returns true on success.

Aborts if the slot supplied is invalid.

If reallocation of slot storage fails, returns false.

=cut
*/

int
im_context_slot_set(im_context_t ctx, im_slot_t slot, void *value) {
  if (slot < 0 || slot >= slot_count) {
    fprintf(stderr, "Invalid slot %d (valid 0 - %d)\n",
	    (int)slot, (int)slot_count-1);
    abort();
  }

  if (slot >= ctx->slot_alloc) {
    ssize_t i;
    size_t new_alloc = slot_count;
    void **new_slots = realloc(ctx->slots, sizeof(void *) * new_alloc);

    if (!new_slots)
      return 0;

    for (i = ctx->slot_alloc; i < new_alloc; ++i)
      new_slots[i] = NULL;

    ctx->slots = new_slots;
    ctx->slot_alloc = new_alloc;
  }

  ctx->slots[slot] = value;

  return 1;
}

/*
=item im_context_slot_get(ctx, slot)

Retrieve the value previously stored in the given slot of the context
object.

=cut
*/

void *
im_context_slot_get(im_context_t ctx, im_slot_t slot) {
  if (slot < 0 || slot >= slot_count) {
    fprintf(stderr, "Invalid slot %d (valid 0 - %d)\n",
	    (int)slot, (int)slot_count-1);
    abort();
  }

  if (slot >= ctx->slot_alloc)
    return NULL;

  return ctx->slots[slot];
}
