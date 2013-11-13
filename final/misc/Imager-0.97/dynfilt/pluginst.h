#include "../plug.h"

#ifdef WIN32
#define WIN32_EXPORT __declspec(dllexport)
#else
/* this may need to change for other Win32 compilers */
#define WIN32_EXPORT
#endif

symbol_table_t *symbol_table;
UTIL_table_t *util_table;

void WIN32_EXPORT
install_tables(symbol_table_t *s,UTIL_table_t *u) {
  symbol_table=s;
  util_table=u;
}
