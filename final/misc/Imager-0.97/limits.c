/*
=head1 NAME

limits.c - manages data/functions for limiting the sizes of images read from files.

=head1 SYNOPSIS

  // user code
  if (!i_set_image_file_limits(max_width, max_height, max_bytes)) {
    // error
  }
  i_get_image_file_limits(&max_width, &max_height, &max_bytes);

  // file reader implementations
  if (!i_int_check_image_file_limits(width, height, channels, sizeof(i_sample_t))) {
    // error handling
  }

=head1 DESCRIPTION

Manage limits for image files read by Imager.

Setting a value of zero means that limit will be ignored.

=over

=cut
 */

#define IMAGER_NO_CONTEXT
#include "imageri.h"

/*
=item im_set_image_file_limits(ctx, width, height, bytes)
X<im_set_image_file_limits API>X<i_set_image_file_limits API>
=category Files
=synopsis im_set_image_file_limits(aIMCTX, 500, 500, 1000000);
=synopsis i_set_image_file_limits(500, 500, 1000000);

Set limits on the sizes of images read by Imager.

Setting a limit to 0 means that limit is ignored.

Negative limits result in failure.

Parameters:

=over

=item *

i_img_dim width, height - maximum width and height.

=item *

size_t bytes - maximum size in memory in bytes.  A value of zero sets
this limit to one gigabyte.

=back

Returns non-zero on success.

Also callable as C<i_set_image_file_limits(width, height, bytes)>.

=cut
*/

int
im_set_image_file_limits(pIMCTX, i_img_dim width, i_img_dim height, size_t bytes) {
  i_clear_error();

  if (width < 0) {
    i_push_error(0, "width must be non-negative");
    return 0;
  }
  if (height < 0) {
    i_push_error(0, "height must be non-negative");
    return 0;
  }
  if (bytes < 0) {
    i_push_error(0, "bytes must be non-negative");
    return 0;
  }

  aIMCTX->max_width = width;
  aIMCTX->max_height = height;
  aIMCTX->max_bytes = bytes ? bytes : DEF_BYTES_LIMIT;

  return 1;
}

/*
=item im_get_image_file_limits(ctx, &width, &height, &bytes)
X<im_get_image_file_limits API>X<i_get_image_file_limits>
=category Files
=synopsis im_get_image_file_limits(aIMCTX, &width, &height, &bytes)
=synopsis i_get_image_file_limits(&width, &height, &bytes)

Retrieves the file limits set by i_set_image_file_limits().

=over

=item *

i_img_dim *width, *height - the maximum width and height of the image.

=item *

size_t *bytes - size in memory of the image in bytes.

=back

Also callable as C<i_get_image_file_limits(&width, &height, &bytes)>.

=cut
*/

int
im_get_image_file_limits(pIMCTX, i_img_dim *width, i_img_dim *height, size_t *bytes) {
  im_clear_error(aIMCTX);

  *width = aIMCTX->max_width;
  *height = aIMCTX->max_height;
  *bytes = aIMCTX->max_bytes;

  return 1;
}

/*
=item im_int_check_image_file_limits(width, height, channels, sample_size)
X<im_int_check_image_file_limits API>X<i_int_check_image_file_limits>
=category Files
=synopsis im_int_check_image_file_limits(aIMCTX, width, height, channels, sizeof(i_sample_t))
=synopsis i_int_check_image_file_limits(width, height, channels, sizeof(i_sample_t))

Checks the size of a file in memory against the configured image file
limits.

This also range checks the values to those permitted by Imager and
checks for overflows in calculating the size.

Returns non-zero if the file is within limits.

This function is intended to be called by image file read functions.

Also callable as C<i_int_check_image_file_limits(width, height, channels, sizeof(i_sample_t)>.

=cut
*/

int
im_int_check_image_file_limits(pIMCTX, i_img_dim width, i_img_dim height, int channels, size_t sample_size) {
  size_t bytes;
  im_clear_error(aIMCTX);
  
  if (width <= 0) {
    im_push_errorf(aIMCTX, 0, "file size limit - image width of %" i_DF " is not positive",
		  i_DFc(width));
    return 0;
  }
  if (aIMCTX->max_width && width > aIMCTX->max_width) {
    im_push_errorf(aIMCTX, 0, "file size limit - image width of %" i_DF " exceeds limit of %" i_DF,
		  i_DFc(width), i_DFc(aIMCTX->max_width));
    return 0;
  }

  if (height <= 0) {
    im_push_errorf(aIMCTX, 0, "file size limit - image height of %" i_DF " is not positive",
		  i_DFc(height));
    return 0;
  }

  if (aIMCTX->max_height && height > aIMCTX->max_height) {
    im_push_errorf(aIMCTX, 0, "file size limit - image height of %" i_DF
		  " exceeds limit of %" i_DF, i_DFc(height), i_DFc(aIMCTX->max_height));
    return 0;
  }

  if (channels < 1 || channels > MAXCHANNELS) {
    im_push_errorf(aIMCTX, 0, "file size limit - channels %d out of range",
		  channels);
    return 0;
  }
  
  if (sample_size < 1 || sample_size > sizeof(long double)) {
    im_push_errorf(aIMCTX, 0, "file size limit - sample_size %ld out of range",
		  (long)sample_size);
    return 0;
  }

  /* This overflow check is a bit more paranoid than usual.
     We don't protect it under max_bytes since we always want to check 
     for overflow.
  */
  bytes = width * height * channels * sample_size;
  if (bytes / width != height * channels * sample_size
      || bytes / height != width * channels * sample_size) {
    im_push_error(aIMCTX, 0, "file size limit - integer overflow calculating storage");
    return 0;
  }
  if (aIMCTX->max_bytes) {
    if (bytes > aIMCTX->max_bytes) {
      im_push_errorf(aIMCTX, 0, "file size limit - storage size of %lu "
		    "exceeds limit of %lu", (unsigned long)bytes,
		    (unsigned long)aIMCTX->max_bytes);
      return 0;
    }
  }

  return 1;
}
