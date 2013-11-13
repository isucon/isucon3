#include "imexttypes.h"
#include "imager.h"
#include "imio.h"

static im_context_t get_context(void);
static i_img *mathom_i_img_8_new(i_img_dim, i_img_dim, int);
static i_img *mathom_i_img_16_new(i_img_dim, i_img_dim, int);
static i_img *mathom_i_img_double_new(i_img_dim, i_img_dim, int);
static i_img *mathom_i_img_pal_new(i_img_dim, i_img_dim, int, int);
static void mathom_i_clear_error(void);
static void mathom_i_push_error(int, const char *);
static void mathom_i_push_errorvf(int, const char *, va_list);
static int mathom_i_set_image_file_limits(i_img_dim, i_img_dim, size_t);
static int mathom_i_get_image_file_limits(i_img_dim*, i_img_dim*, size_t*);
static int
mathom_i_int_check_image_file_limits(i_img_dim, i_img_dim, int, size_t);
static i_img *mathom_i_img_alloc(void);
static void mathom_i_img_init(i_img *);
static i_io_glue_t *mathom_io_new_fd(int);
static i_io_glue_t *mathom_io_new_bufchain(void);
static i_io_glue_t *
mathom_io_new_buffer(const char *data, size_t, i_io_closebufp_t, void *);
static i_io_glue_t *
mathom_io_new_cb(void *, i_io_readl_t, i_io_writel_t, i_io_seekl_t,
		 i_io_closel_t, i_io_destroyl_t);

/*
 DON'T ADD CASTS TO THESE
*/
im_ext_funcs imager_function_table =
  {
    IMAGER_API_VERSION,
    IMAGER_API_LEVEL,

    mymalloc,
    myfree,
    myrealloc,

    mymalloc_file_line,
    myfree_file_line,
    myrealloc_file_line,

    mathom_i_img_8_new,
    mathom_i_img_16_new,
    mathom_i_img_double_new,
    mathom_i_img_pal_new,
    i_img_destroy,
    i_sametype,
    i_sametype_chans,
    i_img_info,

    i_ppix,
    i_gpix,
    i_ppixf,
    i_gpixf,
    i_plin,
    i_glin,
    i_plinf,
    i_glinf,
    i_gsamp,
    i_gsampf,
    i_gpal,
    i_ppal,
    i_addcolors,
    i_getcolors,
    i_colorcount,
    i_maxcolors,
    i_findcolor,
    i_setcolors,

    i_new_fill_solid,
    i_new_fill_solidf,
    i_new_fill_hatch,
    i_new_fill_hatchf,
    i_new_fill_image,
    i_new_fill_fount,
    i_fill_destroy,

    i_quant_makemap,
    i_quant_translate,
    i_quant_transparent,

    mathom_i_clear_error,
    mathom_i_push_error,
    i_push_errorf,
    mathom_i_push_errorvf,

    i_tags_new,
    i_tags_set,
    i_tags_setn,
    i_tags_destroy,
    i_tags_find,
    i_tags_findn,
    i_tags_delete,
    i_tags_delbyname,
    i_tags_delbycode,
    i_tags_get_float,
    i_tags_set_float,
    i_tags_set_float2,
    i_tags_get_int,
    i_tags_get_string,
    i_tags_get_color,
    i_tags_set_color,

    i_box,
    i_box_filled,
    i_box_cfill,
    i_line,
    i_line_aa,
    i_arc,
    i_arc_aa,
    i_arc_cfill,
    i_arc_aa_cfill,
    i_circle_aa,
    i_flood_fill,
    i_flood_cfill,

    i_copyto,
    i_copyto_trans,
    i_copy,
    i_rubthru,

    /* IMAGER_API_LEVEL 2 functions */
    mathom_i_set_image_file_limits,
    mathom_i_get_image_file_limits,
    mathom_i_int_check_image_file_limits,

    i_flood_fill_border,
    i_flood_cfill_border,

    /* IMAGER_API_LEVEL 3 functions */
    i_img_setmask,
    i_img_getmask,
    i_img_getchannels,
    i_img_get_width,
    i_img_get_height,
    i_lhead,
    i_loog,

    /* IMAGER_API_LEVEL 4 functions */
    mathom_i_img_alloc,
    mathom_i_img_init,

    /* IMAGER_API_LEVEL 5 functions */
    i_img_is_monochrome,
    i_gsamp_bg,
    i_gsampf_bg,
    i_get_file_background,
    i_get_file_backgroundf,
    i_utf8_advance,
    i_render_new,
    i_render_delete,
    i_render_color,
    i_render_fill,
    i_render_line,
    i_render_linef,

    /* level 6 */
    i_io_getc_imp,
    i_io_peekc_imp,
    i_io_peekn,
    i_io_putc_imp,
    i_io_read,
    i_io_write,
    i_io_seek,
    i_io_flush,
    i_io_close,
    i_io_set_buffered,
    i_io_gets,
    mathom_io_new_fd,
    mathom_io_new_bufchain,
    mathom_io_new_buffer,
    mathom_io_new_cb,
    io_slurp,
    io_glue_destroy,

    /* level 8 */
    im_img_8_new,
    im_img_16_new,
    im_img_double_new,
    im_img_pal_new,
    im_clear_error,
    im_push_error,
    im_push_errorvf,
    im_push_errorf,
    im_set_image_file_limits,
    im_get_image_file_limits,
    im_int_check_image_file_limits,
    im_img_alloc,
    im_img_init,
    im_io_new_fd,
    im_io_new_bufchain,
    im_io_new_buffer,
    im_io_new_cb,
    get_context,
    im_lhead,
    im_loog,
    im_context_refinc,
    im_context_refdec,
    im_errors,
    i_mutex_new,
    i_mutex_destroy,
    i_mutex_lock,
    i_mutex_unlock,
    im_context_slot_new,
    im_context_slot_set,
    im_context_slot_get
  };

/* in general these functions aren't called by Imager internally, but
   only via the pointers above, since faster macros that call the
   image vtable pointers are used.

   () are used around the function names to prevent macro replacement
   on the function names.
*/

/*
=item i_ppix(im, x, y, color)

=category Drawing

Sets the pixel at (x,y) to I<color>.

Returns 0 if the pixel was drawn, or -1 if not.

Does no alpha blending, just copies the channels from the supplied
color to the image.

=cut
*/

int 
(i_ppix)(i_img *im, i_img_dim x, i_img_dim y, const i_color *val) {
  return i_ppix(im, x, y, val);
}

/*
=item i_gpix(im, C<x>, C<y>, C<color>)

=category Drawing

Retrieves the C<color> of the pixel (x,y).

Returns 0 if the pixel was retrieved, or -1 if not.

=cut
*/

int
(i_gpix)(i_img *im,i_img_dim x,i_img_dim y,i_color *val) {
  return i_gpix(im, x, y, val);
}

/*
=item i_ppixf(im, C<x>, C<y>, C<fcolor>)

=category Drawing

Sets the pixel at (C<x>,C<y>) to the floating point color C<fcolor>.

Returns 0 if the pixel was drawn, or -1 if not.

Does no alpha blending, just copies the channels from the supplied
color to the image.

=cut
*/
int
(i_ppixf)(i_img *im, i_img_dim x, i_img_dim y, const i_fcolor *val) {
  return i_ppixf(im, x, y, val);
}

/*
=item i_gpixf(im, C<x>, C<y>, C<fcolor>)

=category Drawing

Retrieves the color of the pixel (x,y) as a floating point color into
C<fcolor>.

Returns 0 if the pixel was retrieved, or -1 if not.

=cut
*/

int
(i_gpixf)(i_img *im,i_img_dim x,i_img_dim y,i_fcolor *val) {
  return i_gpixf(im, x, y, val);
}

/*
=item i_plin(im, l, r, y, colors)

=category Drawing

Sets (r-l) pixels starting from (l,y) using (r-l) values from
I<colors>.

Returns the number of pixels set.

=cut
*/

i_img_dim
(i_plin)(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, const i_color *vals) {
  return i_plin(im, l, r, y, vals);
}

/*
=item i_glin(im, l, r, y, colors)

=category Drawing

Retrieves (r-l) pixels starting from (l,y) into I<colors>.

Returns the number of pixels retrieved.

=cut
*/

i_img_dim
(i_glin)(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_color *vals) {
  return i_glin(im, l, r, y, vals);
}

/*
=item i_plinf(im, C<left>, C<right>, C<fcolors>)

=category Drawing

Sets (right-left) pixels starting from (left,y) using (right-left)
floating point colors from C<fcolors>.

Returns the number of pixels set.

=cut
*/

i_img_dim
(i_plinf)(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, const i_fcolor *vals) {
  return i_plinf(im, l, r, y, vals);
}

/*
=item i_glinf(im, l, r, y, colors)

=category Drawing

Retrieves (r-l) pixels starting from (l,y) into I<colors> as floating
point colors.

Returns the number of pixels retrieved.

=cut
*/

i_img_dim
(i_glinf)(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_fcolor *vals) {
  return i_glinf(im, l, r, y, vals);
}

/*
=item i_gsamp(im, left, right, y, samples, channels, channel_count)

=category Drawing

Reads sample values from C<im> for the horizontal line (left, y) to
(right-1,y) for the channels specified by C<channels>, an array of int
with C<channel_count> elements.

If channels is NULL then the first channels_count channels are retrieved for
each pixel.

Returns the number of samples read (which should be (right-left) *
channel_count)

=cut
*/
i_img_dim
(i_gsamp)(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_sample_t *samp, 
                   const int *chans, int chan_count) {
  return i_gsamp(im, l, r, y, samp, chans, chan_count);
}

/*
=item i_gsampf(im, left, right, y, samples, channels, channel_count)

=category Drawing

Reads floating point sample values from C<im> for the horizontal line
(left, y) to (right-1,y) for the channels specified by C<channels>, an
array of int with channel_count elements.

If C<channels> is NULL then the first C<channel_count> channels are
retrieved for each pixel.

Returns the number of samples read (which should be (C<right>-C<left>)
* C<channel_count>)

=cut
*/
i_img_dim
(i_gsampf)(i_img *im, i_img_dim l, i_img_dim r, i_img_dim y, i_fsample_t *samp, 
           const int *chans, int chan_count) {
  return i_gsampf(im, l, r, y, samp, chans, chan_count);
}

/*
=item i_gsamp_bits(im, left, right, y, samples, channels, channel_count, bits)
=category Drawing

Reads integer samples scaled to C<bits> bits of precision into the
C<unsigned int> array C<samples>.

Expect this to be slow unless C<< bits == im->bits >>.

Returns the number of samples copied, or -1 on error.

Not all image types implement this method.

Pushes errors, but does not call C<i_clear_error()>.

=cut
*/

/*
=item i_psamp_bits(im, left, right, y, samples, channels, channel_count, bits)
=category Drawing

Writes integer samples scaled to C<bits> bits of precision from the
C<unsigned int> array C<samples>.

Expect this to be slow unless C<< bits == im->bits >>.

Returns the number of samples copied, or -1 on error.

Not all image types implement this method.

Pushes errors, but does not call C<i_clear_error()>.

=cut
*/

/*
=item i_gpal(im, left, right, y, indexes)

=category Drawing

Reads palette indexes for the horizontal line (left, y) to (right-1,
y) into C<indexes>.

Returns the number of indexes read.

Always returns 0 for direct color images.

=cut
*/
i_img_dim
(i_gpal)(i_img *im, i_img_dim x, i_img_dim r, i_img_dim y, i_palidx *vals) {
  return i_gpal(im, x, r, y, vals);
}

/*
=item i_ppal(im, left, right, y, indexes)

=category Drawing

Writes palette indexes for the horizontal line (left, y) to (right-1,
y) from C<indexes>.

Returns the number of indexes written.

Always returns 0 for direct color images.

=cut
*/
i_img_dim
(i_ppal)(i_img *im, i_img_dim x, i_img_dim r, i_img_dim y, const i_palidx *vals) {
  return i_ppal(im, x, r, y, vals);
}

/*
=item i_addcolors(im, colors, count)

=category Paletted images

Adds colors to the image's palette.

On success returns the index of the lowest color added.

On failure returns -1.

Always fails for direct color images.

=cut
*/

int
(i_addcolors)(i_img *im, const i_color *colors, int count) {
  return i_addcolors(im, colors, count);
}

/*
=item i_getcolors(im, index, colors, count)

=category Paletted images

Retrieves I<count> colors starting from I<index> in the image's
palette.

On success stores the colors into I<colors> and returns true.

On failure returns false.

Always fails for direct color images.

Fails if there are less than I<index>+I<count> colors in the image's
palette.

=cut
*/

int
(i_getcolors)(i_img *im, int i, i_color *colors, int count) {
  return i_getcolors(im, i, colors, count);
}

/*
=item i_colorcount(im)

=category Paletted images

Returns the number of colors in the image's palette.

Returns -1 for direct images.

=cut
*/

int
(i_colorcount)(i_img *im) {
  return i_colorcount(im);
}

/*
=item i_maxcolors(im)

=category Paletted images

Returns the maximum number of colors the palette can hold for the
image.

Returns -1 for direct color images.

=cut
*/

int
(i_maxcolors)(i_img *im) {
  return i_maxcolors(im);
}

/*
=item i_findcolor(im, color, &entry)

=category Paletted images

Searches the images palette for the given color.

On success sets *I<entry> to the index of the color, and returns true.

On failure returns false.

Always fails on direct color images.

=cut
*/
int
(i_findcolor)(i_img *im, const i_color *color, i_palidx *entry) {
  return i_findcolor(im, color, entry);
}

/*
=item i_setcolors(im, index, colors, count)

=category Paletted images

Sets I<count> colors starting from I<index> in the image's palette.

On success returns true.

On failure returns false.

The image must have at least I<index>+I<count> colors in it's palette
for this to succeed.

Always fails on direct color images.

=cut
*/
int
(i_setcolors)(i_img *im, int index, const i_color *colors, int count) {
  return i_setcolors(im, index, colors, count);
}

/*
=item im_get_context()

Retrieve the context object for the current thread.

Inside Imager itself this is just a function pointer, which the
F<Imager.xs> BOOT handler initializes for use within perl.  If you're
taking the Imager code and embedding it elsewhere you need to
initialize the C<im_get_context> pointer at some point.

=cut
*/

static im_context_t
get_context(void) {
  return im_get_context();
}

static i_img *
mathom_i_img_8_new(i_img_dim xsize, i_img_dim ysize, int channels) {
  return i_img_8_new(xsize, ysize, channels);
}

static i_img *
mathom_i_img_16_new(i_img_dim xsize, i_img_dim ysize, int channels) {
  return i_img_16_new(xsize, ysize, channels);
}

static i_img *
mathom_i_img_double_new(i_img_dim xsize, i_img_dim ysize, int channels) {
  return i_img_double_new(xsize, ysize, channels);
}

static i_img *
mathom_i_img_pal_new(i_img_dim xsize, i_img_dim ysize, int channels,
		     int maxpal) {
  return i_img_pal_new(xsize, ysize, channels, maxpal);
}

static void
mathom_i_clear_error(void) {
  i_clear_error();
}

static void
mathom_i_push_error(int code, const char *msg) {
  i_push_error(code, msg);
}

static void
mathom_i_push_errorvf(int code, const char *fmt, va_list args) {
  i_push_errorvf(code, fmt, args);
}

static int
mathom_i_set_image_file_limits(i_img_dim max_width, i_img_dim max_height,
			       size_t max_bytes) {
  return i_set_image_file_limits(max_width, max_height, max_bytes);
}

static int
mathom_i_get_image_file_limits(i_img_dim *pmax_width, i_img_dim *pmax_height,
			       size_t *pmax_bytes) {
  return i_get_image_file_limits(pmax_width, pmax_height, pmax_bytes);
}

static int
mathom_i_int_check_image_file_limits(i_img_dim width, i_img_dim height,
				     int channels, size_t sample_size) {
  return i_int_check_image_file_limits(width, height, channels, sample_size);
}

static i_img *
mathom_i_img_alloc(void) {
  return i_img_alloc();
}

static void
mathom_i_img_init(i_img *im) {
  i_img_init(im);
}

static i_io_glue_t *
mathom_io_new_fd(int fd) {
  return io_new_fd(fd);
}
static i_io_glue_t *
mathom_io_new_bufchain(void) {
  return io_new_bufchain();
}

static i_io_glue_t *
mathom_io_new_buffer(const char *data, size_t size, i_io_closebufp_t closefp,
		     void *close_data) {
  return io_new_buffer(data, size, closefp, close_data);
}

static i_io_glue_t *
mathom_io_new_cb(void *p, i_io_readl_t readcb, i_io_writel_t writecb,
		 i_io_seekl_t seekcb, i_io_closel_t closecb,
		 i_io_destroyl_t destroycb) {
  return io_new_cb(p, readcb, writecb, seekcb, closecb, destroycb);
}
