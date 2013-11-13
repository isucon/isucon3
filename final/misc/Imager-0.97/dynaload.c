#if defined(OS_hpux)
#include <dl.h>
typedef shl_t minthandle_t;
#elif defined(WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
typedef HMODULE minthandle_t;
#undef WIN32_LEAN_AND_MEAN
#else 
#include <dlfcn.h>
typedef void *minthandle_t; 
#endif 

#include "ext.h"

struct DSO_handle_tag {
  minthandle_t handle;
  char *filename;
  func_ptr *function_list;
};

#include "imager.h"
#include "dynaload.h"
/* #include "XSUB.h"  so we can compile on threaded perls */
#include "imageri.h"

static im_context_t
do_get_context(void) {
  return im_get_context();
}

static symbol_table_t symbol_table=
  {
    i_has_format,
    ICL_set_internal,
    ICL_info,
    do_get_context,
    im_img_empty_ch,
    i_img_exorcise,
    i_img_info,
    i_img_setmask,
    i_img_getmask,
    i_box,
    i_line,
    i_arc,
    i_copyto,
    i_copyto_trans,
    i_rubthru
  };


/*
  Dynamic loading works like this:
  dynaload opens the shared object and
  loads all the functions into an array of functions
  it returns a string from the dynamic function that
  can be supplied to the parser for evaling.
*/

void
DSO_call(DSO_handle *handle,int func_index,HV* hv) {
  mm_log((1,"DSO_call(handle %p, func_index %d, hv %p)\n",
	  handle, func_index, hv));
  (handle->function_list[func_index].iptr)((void*)hv);
}

func_ptr *
DSO_funclist(DSO_handle *handle) {
  return handle->function_list;
}


#if defined( OS_hpux )

void*
DSO_open(char* file,char** evalstring) {
  shl_t tt_handle;
  void *d_handle,**plugin_symtab,**plugin_utiltab;
  int  rc,*iptr, (*fptr)(int);
  func_ptr *function_list;
  DSO_handle *dso_handle;
  void (*f)(void *s,void *u); /* these will just have to be void for now */
  int i;

  *evalstring=NULL;

  mm_log( (1,"DSO_open(file '%s' (0x%08X), evalstring 0x%08X)\n",file,file,evalstring) );

  if ( (tt_handle = shl_load(file, BIND_DEFERRED,0L)) == NULL) return NULL; 
  if ( (shl_findsym(&tt_handle, I_EVALSTR,TYPE_UNDEFINED,(void*)evalstring))) return NULL;

  /*
  if ( (shl_findsym(&tt_handle, "symbol_table",TYPE_UNDEFINED,(void*)&plugin_symtab))) return NULL;
  if ( (shl_findsym(&tt_handle, "util_table",TYPE_UNDEFINED,&plugin_utiltab))) return NULL;
  (*plugin_symtab)=&symbol_table;
  (*plugin_utiltab)=&i_UTIL_table;
  */

  if ( (shl_findsym(&tt_handle, I_INSTALL_TABLES ,TYPE_UNDEFINED, &f ))) return NULL; 
 
  mm_log( (1,"Calling install_tables\n") );
  f(&symbol_table,&i_UTIL_table);
  mm_log( (1,"Call ok.\n") ); 
 
  if ( (shl_findsym(&tt_handle, I_FUNCTION_LIST ,TYPE_UNDEFINED,(func_ptr*)&function_list))) return NULL; 
  if ( (dso_handle=(DSO_handle*)malloc(sizeof(DSO_handle))) == NULL) /* checked 17jul05 tonyc */
    return NULL;

  dso_handle->handle=tt_handle; /* needed to close again */
  dso_handle->function_list=function_list;
  if ( (dso_handle->filename=(char*)malloc(strlen(file)+1)) == NULL) { /* checked 17jul05 tonyc */
    free(dso_handle); return NULL;
  }
  strcpy(dso_handle->filename,file);

  mm_log((1,"DSO_open <- (0x%X)\n",dso_handle));
  return (void*)dso_handle;
}

undef_int
DSO_close(void *ptr) {
  DSO_handle *handle=(DSO_handle*) ptr;
  mm_log((1,"DSO_close(ptr 0x%X)\n",ptr));
  return !shl_unload((handle->handle));
}

#elif defined(WIN32)

void *
DSO_open(char *file, char **evalstring) {
  HMODULE d_handle;
  func_ptr *function_list;
  DSO_handle *dso_handle;
  
  void (*f)(void *s,void *u); /* these will just have to be void for now */

  mm_log( (1,"DSO_open(file '%s' (%p), evalstring %p)\n",file,file,evalstring) );

  *evalstring = NULL;
  if ((d_handle = LoadLibrary(file)) == NULL) {
    mm_log((1, "DSO_open: LoadLibrary(%s) failed: %lu\n", file, GetLastError()));
    return NULL;
  }
  if ( (*evalstring = (char *)GetProcAddress(d_handle, I_EVALSTR)) == NULL) {
    mm_log((1,"DSO_open: GetProcAddress didn't fine '%s': %lu\n", I_EVALSTR, GetLastError()));
    FreeLibrary(d_handle);
    return NULL;
  }
  if ((f = (void (*)(void *, void*))GetProcAddress(d_handle, I_INSTALL_TABLES)) == NULL) {
    mm_log((1, "DSO_open: GetProcAddress didn't find '%s': %lu\n", I_INSTALL_TABLES, GetLastError()));
    FreeLibrary(d_handle);
    return NULL;
  }
  mm_log((1, "Calling install tables\n"));
  f(&symbol_table, &i_UTIL_table);
  mm_log((1, "Call ok\n"));
  
  if ( (function_list = (func_ptr *)GetProcAddress(d_handle, I_FUNCTION_LIST)) == NULL) {
    mm_log((1, "DSO_open: GetProcAddress didn't find '%s': %lu\n", I_FUNCTION_LIST, GetLastError()));
    FreeLibrary(d_handle);
    return NULL;
  }
  if ( (dso_handle = (DSO_handle*)malloc(sizeof(DSO_handle))) == NULL) { /* checked 17jul05 tonyc */
    mm_log( (1, "DSO_Open: out of memory\n") );
    FreeLibrary(d_handle);
    return NULL;
  }
  dso_handle->handle=d_handle; /* needed to close again */
  dso_handle->function_list=function_list;
  if ( (dso_handle->filename=(char*)malloc(strlen(file)+1)) == NULL) { /* checked 17jul05 tonyc */
    free(dso_handle);
    FreeLibrary(d_handle); 
    return NULL; 
  }
  strcpy(dso_handle->filename,file);

  mm_log( (1,"DSO_open <- %p\n",dso_handle) );
  return (void*)dso_handle;

}

undef_int
DSO_close(void *ptr) {
  DSO_handle *handle = (DSO_handle *)ptr;
  BOOL result = FreeLibrary(handle->handle);
  free(handle->filename);
  free(handle);

  return result;
}

#else

/* OS/2 has no dlclose; Perl doesn't provide one. */
#ifdef __EMX__ /* OS/2 */
int
dlclose(minthandle_t h) {
  return DosFreeModule(h) ? -1 : 0;
}
#endif /* __EMX__ */

void*
DSO_open(char* file,char** evalstring) {
  void *d_handle;
  func_ptr *function_list;
  DSO_handle *dso_handle;

  void (*f)(void *s,void *u); /* these will just have to be void for now */
  
  *evalstring=NULL;

  mm_log( (1,"DSO_open(file '%s' (%p), evalstring %p)\n",
	   file, file, evalstring) );

  if ( (d_handle = dlopen(file, RTLD_LAZY)) == NULL) {
    mm_log( (1,"DSO_open: dlopen failed: %s.\n",dlerror()) );
    return NULL;
  }

  if ( (*evalstring = (char *)dlsym(d_handle, I_EVALSTR)) == NULL) {
    mm_log( (1,"DSO_open: dlsym didn't find '%s': %s.\n",I_EVALSTR,dlerror()) );
    return NULL;
  }

  /*

    I'll just leave this thing in here for now if I need it real soon

   mm_log( (1,"DSO_open: going to dlsym '%s'\n", I_SYMBOL_TABLE ));
   if ( (plugin_symtab = dlsym(d_handle, I_SYMBOL_TABLE)) == NULL) {
     mm_log( (1,"DSO_open: dlsym didn't find '%s': %s.\n",I_SYMBOL_TABLE,dlerror()) );
     return NULL;
   }
  
   mm_log( (1,"DSO_open: going to dlsym '%s'\n", I_UTIL_TABLE ));
    if ( (plugin_utiltab = dlsym(d_handle, I_UTIL_TABLE)) == NULL) {
     mm_log( (1,"DSO_open: dlsym didn't find '%s': %s.\n",I_UTIL_TABLE,dlerror()) );
     return NULL;
   }

  */

  f = (void(*)(void *s,void *u))dlsym(d_handle, I_INSTALL_TABLES);
  mm_log( (1,"DSO_open: going to dlsym '%s'\n", I_INSTALL_TABLES ));
  if ( (f = (void(*)(void *s,void *u))dlsym(d_handle, I_INSTALL_TABLES)) == NULL) {
    mm_log( (1,"DSO_open: dlsym didn't find '%s': %s.\n",I_INSTALL_TABLES,dlerror()) );
    return NULL;
  }

  mm_log( (1,"Calling install_tables\n") );
  f(&symbol_table,&i_UTIL_table);
  mm_log( (1,"Call ok.\n") );

  /* (*plugin_symtab)=&symbol_table;
     (*plugin_utiltab)=&i_UTIL_table; */
  
  mm_log( (1,"DSO_open: going to dlsym '%s'\n", I_FUNCTION_LIST ));
  if ( (function_list=(func_ptr *)dlsym(d_handle, I_FUNCTION_LIST)) == NULL) {
    mm_log( (1,"DSO_open: dlsym didn't find '%s': %s.\n",I_FUNCTION_LIST,dlerror()) );
    return NULL;
  }
  
  if ( (dso_handle=(DSO_handle*)malloc(sizeof(DSO_handle))) == NULL) /* checked 17jul05 tonyc */
    return NULL;
  
  dso_handle->handle=d_handle; /* needed to close again */
  dso_handle->function_list=function_list;
  if ( (dso_handle->filename=(char*)malloc(strlen(file)+1)) == NULL) { /* checked 17jul05 tonyc */
    free(dso_handle); 
    return NULL;
  }
  strcpy(dso_handle->filename,file);

  mm_log( (1,"DSO_open <- %p\n",dso_handle) );
  return (void*)dso_handle;
}

undef_int
DSO_close(void *ptr) {
  DSO_handle *handle;
  mm_log((1,"DSO_close(ptr %p)\n",ptr));
  handle=(DSO_handle*) ptr;
  return !dlclose(handle->handle);
}

#endif

