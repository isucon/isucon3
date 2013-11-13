#include "feat.h"

/* only for use as a placeholder in the old dynamic module code */
undef_int
i_has_format(char *frmt) {
  int rc,i;
  rc=0;
  i=0;
  while(i_format_list[i] != NULL) if ( !strcmp(frmt,i_format_list[i++]) ) rc=1;
  return(rc);
}
