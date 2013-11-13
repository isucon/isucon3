/*
  pthreads mutexes
*/

#include "imageri.h"

#include <pthread.h>
#include <errno.h>

/* documented in mutexwin.c */

struct i_mutex_tag {
  pthread_mutex_t mutex;
};

i_mutex_t
i_mutex_new(void) {
  i_mutex_t m;

  m = malloc(sizeof(*m));
  if (!m)
    i_fatal(3, "Cannot allocate mutex object");
  if (pthread_mutex_init(&m->mutex, NULL) != 0) {
    i_fatal(3, "Error initializing mutex %d", errno);
  }

  return m;
}

void
i_mutex_destroy(i_mutex_t m) {
  pthread_mutex_destroy(&(m->mutex));
  free(m);
}

void
i_mutex_lock(i_mutex_t m) {
  pthread_mutex_lock(&(m->mutex));
}

void
i_mutex_unlock(i_mutex_t m) {
  pthread_mutex_unlock(&m->mutex);
}
