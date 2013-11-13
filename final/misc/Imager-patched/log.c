#define IMAGER_NO_CONTEXT
#include "imageri.h"
#include "imconfig.h"
#include "log.h"
#include <stdlib.h>
#include <errno.h>
#include "imerror.h"

#ifdef IMAGER_LOG

#define DTBUFF 50
#define DATABUFF DTBUFF+3+10+1+5+1+1

#define LOG_DATE_FORMAT "%Y/%m/%d %H:%M:%S"

static i_mutex_t log_mutex;

static void
im_vloog(pIMCTX, int level, const char *fmt, va_list ap);

/*
 * Logging is active
 */

int
im_init_log(pIMCTX, const char* name,int level) {
  i_clear_error();

  if (!log_mutex) {
    log_mutex = i_mutex_new();
  }

  if (aIMCTX->lg_file) {
    if (aIMCTX->own_log)
      fclose(aIMCTX->lg_file);
    aIMCTX->lg_file = NULL;
  }
  
  aIMCTX->log_level = level;
  if (level < 0) {
    aIMCTX->lg_file = NULL;
  } else {
    if (name == NULL) {
      aIMCTX->lg_file = stderr;
      aIMCTX->own_log = 0;
    } else {
      if (NULL == (aIMCTX->lg_file = fopen(name, "w+")) ) { 
	im_push_errorf(aIMCTX, errno, "Cannot open file '%s': (%d)", name, errno);
	return 0;
      }
      aIMCTX->own_log = 1;
      setvbuf(aIMCTX->lg_file, NULL, _IONBF, BUFSIZ);
    }
  }
  if (aIMCTX->lg_file) {
    im_log((aIMCTX, 0,"Imager - log started (level = %d)\n", level));
  }

  return aIMCTX->lg_file != NULL;
}

void
i_fatal(int exitcode,const char *fmt, ... ) {
  va_list ap;
  dIMCTX;

  if (aIMCTX->lg_file != NULL) {
    va_start(ap,fmt);
    im_vloog(aIMCTX, 0, fmt, ap);
    va_end(ap);
  }
  exit(exitcode);
}

void
im_fatal(pIMCTX, int exitcode,const char *fmt, ... ) {
  va_list ap;
  
  if (aIMCTX->lg_file != NULL) {
    va_start(ap,fmt);
    im_vloog(aIMCTX, 0, fmt, ap);
    va_end(ap);
  }
  exit(exitcode);
}

/*
=item i_loog(level, format, ...)
=category Logging

This is an internal function called by the mm_log() macro.

=cut
*/

static void
im_vloog(pIMCTX, int level, const char *fmt, va_list ap) {
  time_t timi;
  struct tm *str_tm;
  char date_buffer[DTBUFF];

  if (!aIMCTX->lg_file || level > aIMCTX->log_level)
    return;

  i_mutex_lock(log_mutex);
  
  timi = time(NULL);
  str_tm = localtime(&timi);
  strftime(date_buffer, DTBUFF, LOG_DATE_FORMAT, str_tm);
  fprintf(aIMCTX->lg_file, "[%s] %10s:%-5d %3d: ", date_buffer,
	  aIMCTX->filename, aIMCTX->line, level);
  vfprintf(aIMCTX->lg_file, fmt, ap);
  fflush(aIMCTX->lg_file);

  i_mutex_unlock(log_mutex);
}

void
i_loog(int level,const char *fmt, ... ) {
  dIMCTX;
  va_list ap;

  if (!aIMCTX->lg_file || level > aIMCTX->log_level)
    return;

  va_start(ap,fmt);
  im_vloog(aIMCTX, level, fmt, ap);
  va_end(ap);
}

void
im_loog(pIMCTX, int level,const char *fmt, ... ) {
  va_list ap;

  if (!aIMCTX->lg_file || level > aIMCTX->log_level)
    return;

  va_start(ap,fmt);
  im_vloog(aIMCTX, level, fmt, ap);
  va_end(ap);
}

/*
=item i_lhead(file, line)
=category Logging

This is an internal function called by the mm_log() macro.

=cut
*/

void
im_lhead(pIMCTX, const char *file, int line) {
  if (aIMCTX->lg_file != NULL) {
    aIMCTX->filename = file;
    aIMCTX->line = line;
  }
}

void i_lhead(const char *file, int line) {
  dIMCTX;

  im_lhead(aIMCTX, file, line);
}

#else

/*
 * Logging is inactive - insert dummy functions
 */

int im_init_log(pIMCTX, const char* name,int onoff) {
  i_clear_error();
  i_push_error(0, "Logging disabled");
  return 0;
}

void i_fatal(int exitcode,const char *fmt, ... ) { exit(exitcode); }
void im_fatal(pIMCTX, int exitcode,const char *fmt, ... ) { exit(exitcode); }

void
i_loog(int level,const char *fmt, ... ) {
}

void
im_loog(pIMCTX, int level,const char *fmt, ... ) {
}

void
i_lhead(const char *file, int line) { }

void
im_lhead(pIMCTX, const char *file, int line) { }

#endif
