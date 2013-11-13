#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#define IMAGER_NO_CONTEXT
#include "imager.h"

/*
  2d bitmask with test and set operations
*/

struct i_bitmap*
btm_new(i_img_dim xsize,i_img_dim ysize) {
  size_t bytes;
  struct i_bitmap *btm;
  btm=(struct i_bitmap*)mymalloc(sizeof(struct i_bitmap)); /* checked 4jul05 tonyc */
  bytes = (xsize*ysize+8)/8;
  if (bytes * 8 / ysize < xsize-1) { /* this is kind of rough */
    fprintf(stderr, "Integer overflow allocating bitmap (" i_DFp ")",
	    i_DFcp(xsize, ysize));
    exit(3);
  }
  btm->data=(char*)mymalloc(bytes); /* checked 4jul05 tonyc */
  btm->xsize=xsize;
  btm->ysize=ysize;
  memset(btm->data, 0, bytes);
  return btm;
}


void
btm_destroy(struct i_bitmap *btm) {
  myfree(btm->data);
  myfree(btm);
}


int
btm_test(struct i_bitmap *btm,i_img_dim x,i_img_dim y) {
  i_img_dim btno;
  if (x<0 || x>btm->xsize-1 || y<0 || y>btm->ysize-1) return 0;
  btno=btm->xsize*y+x;
  return (1<<(btno%8))&(btm->data[btno/8]);
}

void
btm_set(struct i_bitmap *btm,i_img_dim x,i_img_dim y) {
  i_img_dim btno;
  if (x<0 || x>btm->xsize-1 || y<0 || y>btm->ysize-1) abort();
  btno=btm->xsize*y+x;
  btm->data[btno/8]|=1<<(btno%8);
}





/*
  Bucketed linked list - stack type 
*/

static struct llink *
llink_new(struct llink* p,size_t size);
static int
llist_llink_push(struct llist *lst, struct llink *lnk,const void *data);
static void
llink_destroy(struct llink* l);

/*
=item llist_new()
=synopsis struct llist *l = llist_new(100, sizeof(foo);

Create a new stack structure.  Implemented as a linked list of pools.

Parameters:

=over

=item *

multip - number of entries in each pool

=item *

ssize - size of the objects being pushed/popped

=back

=cut
*/

struct llist *
llist_new(int multip, size_t ssize) {
  struct llist *l;
  l         = mymalloc(sizeof(struct llist)); /* checked 4jul05 tonyc */
  l->h      = NULL;
  l->t      = NULL;
  l->multip = multip;
  l->ssize  = ssize;
  l->count  = 0;
  return l;
}

/*
=item llist_push()
=synopsis llist_push(l, &foo);

Push an item on the stack.

=cut
*/

void
llist_push(struct llist *l,const void *data) {
  size_t ssize  = l->ssize;
  int multip = l->multip;
  
  /*  fprintf(stderr,"llist_push: data=0x%08X\n",data);
      fprintf(stderr,"Chain size: %d\n", l->count); */
    
  if (l->t == NULL) {
    l->t = l->h = llink_new(NULL,ssize*multip);  /* Tail is empty - list is empty */
    /* fprintf(stderr,"Chain empty - extended\n"); */
  }
  else { /* Check for overflow in current tail */
    if (l->t->fill >= l->multip) {
      struct llink* nt = llink_new(l->t, ssize*multip);
      l->t->n=nt;
      l->t=nt;
      /* fprintf(stderr,"Chain extended\n"); */
    }
  }
  /*   fprintf(stderr,"0x%08X\n",l->t); */
  if (llist_llink_push(l,l->t,data)) {
    dIMCTX;
    im_fatal(aIMCTX, 3, "out of memory\n");
  }
}

/* 
=item llist_pop()

Pop an item off the list, storing it at C<data> which must have enough room for an object of the size supplied to llist_new().

returns 0 if the list is empty

=cut
*/

int
llist_pop(struct llist *l,void *data) {
  /*   int ssize=l->ssize; 
       int multip=l->multip;*/
  if (l->t == NULL) return 0;
  l->t->fill--;
  l->count--;
  memcpy(data,(char*)(l->t->data)+l->ssize*l->t->fill,l->ssize);
  
  if (!l->t->fill) {			 	/* This link empty */
    if (l->t->p == NULL) {                      /* and it's the only link */
      llink_destroy(l->t);
      l->h = l->t = NULL;
    }
    else {
      l->t=l->t->p;
      llink_destroy(l->t->n);
    }
  }
  return 1;
}

void
llist_dump(struct llist *l) {
  int j;
  int i=0;
  struct llink *lnk; 
  lnk=l->h;
  while(lnk != NULL) {
    for(j=0;j<lnk->fill;j++) {
      /*       memcpy(&k,(char*)(lnk->data)+l->ssize*j,sizeof(void*));*/
      /*memcpy(&k,(char*)(lnk->data)+l->ssize*j,sizeof(void*));*/
      printf("%d - %p\n",i,*(void **)((char *)(lnk->data)+l->ssize*j));
      i++;
    }
    lnk=lnk->n;
  }
}

/*
=item llist_destroy()

Destroy a linked-list based stack.

=cut
*/

void
llist_destroy(struct llist *l) {
  struct llink *t,*lnk = l->h;
  while( lnk != NULL ) {
    t=lnk;
    lnk=lnk->n;
    myfree(t);
  }
  myfree(l);
}

/* Links */

static struct llink *
llink_new(struct llink* p,size_t size) {
  struct llink *l;
  l       = mymalloc(sizeof(struct llink)); /* checked 4jul05 tonyc */
  l->n    = NULL;
  l->p    = p;
  l->fill = 0;
  l->data = mymalloc(size); /* checked 4jul05 tonyc - depends on caller to llist_push */
  return l;
}

/* free's the data pointer, itself, and sets the previous' next pointer to null */

static void
llink_destroy(struct llink* l) {
  if (l->p != NULL) { l->p->n=NULL; }
  myfree(l->data);
  myfree(l);
}


/* if it returns true there wasn't room for the
   item on the link */

static int
llist_llink_push(struct llist *lst, struct llink *lnk, const void *data) {
  /*   fprintf(stderr,"llist_llink_push: data=0x%08X -> 0x%08X\n",data,*(int*)data);
       fprintf(stderr,"ssize = %d, multip = %d, fill = %d\n",lst->ssize,lst->multip,lnk->fill); */
  if (lnk->fill == lst->multip) return 1;
  /*   memcpy((char*)(lnk->data)+lnk->fill*lst->ssize,data,lst->ssize); */
  memcpy((char*)(lnk->data)+lnk->fill*lst->ssize,data,lst->ssize);
  
  /*   printf("data=%X res=%X\n",*(int*)data,*(int*)(lnk->data));*/
  lnk->fill++;
  lst->count++;
  return 0;
}

/*
  Oct-tree implementation 
*/

struct octt *
octt_new() {
  int i;
  struct octt *t;
  
  t=(struct octt*)mymalloc(sizeof(struct octt)); /* checked 4jul05 tonyc */
  for(i=0;i<8;i++) t->t[i]=NULL;
  t->cnt=0;
  return t;
}


/* returns 1 if the colors wasn't in the octtree already */


int
octt_add(struct octt *ct,unsigned char r,unsigned char g,unsigned char b) {
  struct octt *c;
  int i,cm;
  int ci;
  int rc;
  rc=0;
  c=ct;
  /*  printf("[r,g,b]=[%d,%d,%d]\n",r,g,b); */
  for(i=7;i>-1;i--) {
    cm=1<<i;
    ci=((!!(r&cm))<<2)+((!!(g&cm))<<1)+!!(b&cm); 
    /* printf("idx[%d]=%d\n",i,ci); */
    if (c->t[ci] == NULL) { 
      c->t[ci]=octt_new(); 
      rc=1; 
    }
    c=c->t[ci];
  }
  c->cnt++;  /* New. The only thing really needed (I think) */
  return rc;
}


void
octt_delete(struct octt *ct) {
  int i;
  for(i=0;i<8;i++) if (ct->t[i] != NULL) octt_delete(ct->t[i]);  /* do not free instance here because it will free itself */
  myfree(ct);
}


void
octt_dump(struct octt *ct) {
	int i;
	/* 	printf("node [0x%08X] -> (%d)\n",ct,ct->cnt); */
	for(i=0;i<8;i++)
	  if (ct->t[i] != NULL) 
	    printf("[ %d ] -> %p\n", i, (void *)ct->t[i]);	
	for(i=0;i<8;i++) 
	  if (ct->t[i] != NULL) 
	    octt_dump(ct->t[i]);
}

/* note that all calls of octt_count are operating on the same overflow 
   variable so all calls will know at the same time if an overflow
   has occured and stops there. */

void
octt_count(struct octt *ct,int *tot,int max,int *overflow) {
  int i,c;
  c=0;
  if (!(*overflow)) return;
  for(i=0;i<8;i++) if (ct->t[i]!=NULL) { 
    octt_count(ct->t[i],tot,max,overflow);
    c++;
  }
  if (!c) (*tot)++;
  if ( (*tot) > (*overflow) ) *overflow=0;
}

/* This whole function is new */
/* walk through the tree and for each colour, store its seen count in the
   space pointed by *col_usage_it_adr */
void
octt_histo(struct octt *ct, unsigned int **col_usage_it_adr) {
    int i,c;
    c = 0;
    for(i = 0; i < 8; i++) 
        if (ct->t[i] != NULL) { 
            octt_histo(ct->t[i], col_usage_it_adr);
            c++;
        }
    if (!c) {
        *(*col_usage_it_adr)++ = ct->cnt;
    }
}


i_img_dim
i_abs(i_img_dim x) {
  return x < 0 ? -x : x;
}
