/*
=head1 NAME

  map.c - inplace image mapping and related functionality

=head1 SYNOPSIS

  i_map(srcimage, coeffs, outchans, inchans)

=head1 DESCRIPTION

Converts images from one format to another, typically in this case for
converting from RGBA to greyscale and back.

=over

=cut
*/

#include "imager.h"


/*
=item i_map(im, mapcount, maps, chmasks)

maps im inplace into another image.

  Each map is a unsigned char array of 256 entries, its corresponding
  channel mask is the same numbered entry in the chmasks array.
  If two maps apply to the same channel then the second one is used.
  If no map applies to a channel then that channel is not altered.
  mapcount is the number of maps.

=cut
*/

void
i_map(i_img *im, unsigned char (*maps)[256], unsigned int mask) {
  i_color *vals;
  i_img_dim x, y;
  int i, ch;
  int minset = -1, maxset = 0;

  mm_log((1,"i_map(im %p, maps %p, chmask %u)\n", im, maps, mask));

  if (!mask) return; /* nothing to do here */

  for(i=0; i<im->channels; i++)
    if (mask & (1<<i)) {
      if (minset == -1) minset = i;
      maxset = i;
    }

  mm_log((1, "minset=%d maxset=%d\n", minset, maxset));

  vals = mymalloc(sizeof(i_color) * im->xsize);

  for (y = 0; y < im->ysize; ++y) {
    i_glin(im, 0, im->xsize, y, vals);
    for (x = 0; x < im->xsize; ++x) {
      for(ch = minset; ch<=maxset; ch++) {
	if (!maps[ch]) continue;
	vals[x].channel[ch] = maps[ch][vals[x].channel[ch]];
      }
    }
    i_plin(im, 0, im->xsize, y, vals);
  }
  myfree(vals);
}

/*
=back

=head1 SEE ALSO

Imager(3)

=head1 AUTHOR

Arnar M. Hrafnkelsson <addi@umich.edu>

=cut
*/
