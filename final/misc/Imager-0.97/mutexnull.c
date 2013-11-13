/*
  dummy mutexes, for non-threaded builds
*/

#include "imageri.h"

#include <pthread.h>

/* documented in mutexwin.c */

struct i_mutex_tag {
  int dummy;
};

i_mutex_t
i_mutex_new(void) {
  i_mutex_t m;

  m = malloc(sizeof(*m));
  if (!m)
    i_fatal(3, "Cannot allocate mutex object");

  return m;
}

void
i_mutex_destroy(i_mutex_t m) {
  free(m);
}

void
i_mutex_lock(i_mutex_t m) {
  (void)m;
}

void
i_mutex_unlock(i_mutex_t m) {
  (void)m;
}
