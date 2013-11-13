#include "imager.h"
#include "regmach.h"

/*
=head1 NAME

trans2.c - entry point for the general transformation engine

=head1 SYNOPSIS

  int width, height, channels;
  struct rm_ops *ops;
  int op_count;
  double *n_regs;
  int n_regs_count;
  i_color *c_regs;
  int c_regs_count;
  i_img **in_imgs;
  int in_imgs_count;
  i_img *result = transform2(width, height, channels, ops, ops_count,
                             n_regs, n_regs_count, c_regs, c_regs_count,
                             in_imgs, in_imgs_count);

=head1 DESCRIPTION

This (short) file implements the transform2() function, just iterating 
over the image - most of the work is done in L<regmach.c>

=cut
*/

i_img* i_transform2(i_img_dim width, i_img_dim height, int channels,
		    struct rm_op *ops, int ops_count, 
		    double *n_regs, int n_regs_count, 
		    i_color *c_regs, int c_regs_count, 
		    i_img **in_imgs, int in_imgs_count)
{
  i_img *new_img;
  i_img_dim x, y;
  i_color val;
  int i;
  int need_images;

  i_clear_error();
  
  /* since the number of images is variable and the image numbers
     for getp? are fixed, we can check them here instead of in the 
     register machine - this will help performance */
  need_images = 0;
  for (i = 0; i < ops_count; ++i) {
    switch (ops[i].code) {
    case rbc_getp1:
    case rbc_getp2:
    case rbc_getp3:
      if (ops[i].code - rbc_getp1 + 1 > need_images) {
        need_images = ops[i].code - rbc_getp1 + 1;
      }
    }
  }
  
  if (need_images > in_imgs_count) {
    i_push_errorf(0, "not enough images, code requires %d, %d supplied", 
                  need_images, in_imgs_count);
    return NULL;
  }

  new_img = i_img_empty_ch(NULL, width, height, channels);
  for (x = 0; x < width; ++x) {
    for (y = 0; y < height; ++y) {
      n_regs[0] = x;
      n_regs[1] = y;
      val = i_rm_run(ops, ops_count, n_regs, n_regs_count, c_regs, c_regs_count, 
		   in_imgs, in_imgs_count);
      i_ppix(new_img, x, y, &val);
    }
  }
  
  return new_img;
}

/*
=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=head1 SEE ALSO

Imager(3), regmach.c

=cut
*/
