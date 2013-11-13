/*
=head1 NAME

mutex.c - Imager's mutex API.

=head1 FUNCTIONS

=over

=cut
*/

#include "imageri.h"

#include <windows.h>

struct i_mutex_tag {
  CRITICAL_SECTION section;
};

/*
=item i_mutex_new()
=category Mutex functions
=synopsis i_mutex_t m = i_mutex_new();
=order 10

Create a mutex.

If a critical section cannot be created for whatever reason, Imager
will abort.

=cut
*/

i_mutex_t
i_mutex_new(void) {
  i_mutex_t m;

  m = malloc(sizeof(*m));
  if (!m)
    i_fatal(3, "Cannot allocate mutex object");
  InitializeCriticalSection(&(m->section));

  return m;
}

/*
=item i_mutex_destroy(m)
=category Mutex functions
=synopsis i_mutex_destroy(m);

Destroy a mutex.

=cut
*/

void
i_mutex_destroy(i_mutex_t m) {
  DeleteCriticalSection(&(m->section));
  free(m);
}

/*
=item i_mutex_lock(m)
=category Mutex functions
=synopsis i_mutex_lock(m);

Lock the mutex, waiting if another thread has the mutex locked.

=cut
*/

void
i_mutex_lock(i_mutex_t m) {
  EnterCriticalSection(&(m->section));
}

/*
=item i_mutex_unlock(m)
=category Mutex functions
=synopsis i_mutex_unlock(m);

Release the mutex.

The behavior of releasing a mutex you don't hold is unspecified.

=cut
*/

void
i_mutex_unlock(i_mutex_t m) {
  LeaveCriticalSection(&(m->section));
}

