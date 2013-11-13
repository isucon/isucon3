#include "imext.h"
#include "imexif.h"
#include <stdlib.h>
#include <float.h>
#include <string.h>
#include <stdio.h>

/*
=head1 NAME

imexif.c - EXIF support for Imager

=head1 SYNOPSIS

  if (i_int_decode_exif(im, app1data, app1datasize)) {
    // exif block seen
  }

=head1 DESCRIPTION

This code provides a basic EXIF data decoder.  It is intended to be
called from the JPEG reader code when an APP1 data block is found, and
will set tags in the supplied image.

=cut
*/

typedef enum tiff_type_tag {
  tt_intel = 'I',
  tt_motorola = 'M'
} tiff_type;

typedef enum {
  ift_byte = 1,
  ift_ascii = 2,
  ift_short = 3,
  ift_long = 4,
  ift_rational = 5,
  ift_sbyte = 6,
  ift_undefined = 7,
  ift_sshort = 8,
  ift_slong = 9,
  ift_srational = 10,
  ift_float = 11,
  ift_double = 12,
  ift_last = 12 /* keep the same as the highest type code */
} ifd_entry_type;

static int type_sizes[] =
  {
    0, /* not used */
    1, /* byte */
    1, /* ascii */
    2, /* short */
    4, /* long */
    8, /* rational */
    1, /* sbyte */
    1, /* undefined */
    2, /* sshort */
    4, /* slong */
    8, /* srational */
    4, /* float */
    8, /* double */
  };

typedef struct {
  int tag;
  int type;
  int count;
  int item_size;
  int size;
  int offset;
} ifd_entry;

typedef struct {
  int tag;
  char const *name;
} tag_map;

typedef struct {
  int tag;
  char const *name;
  tag_map const *map;
  int map_count;
} tag_value_map;

#define PASTE(left, right) PASTE_(left, right)
#define PASTE_(left, right) left##right
#define QUOTE(value) #value

#define VALUE_MAP_ENTRY(name) \
  { \
    PASTE(tag_, name), \
    "exif_" QUOTE(name) "_name", \
    PASTE(name, _values), \
    ARRAY_COUNT(PASTE(name, _values)) \
  }

/* we don't process every tag */
#define tag_make 271
#define tag_model 272
#define tag_orientation 274
#define tag_x_resolution 282
#define tag_y_resolution 283
#define tag_resolution_unit 296
#define tag_copyright 33432
#define tag_software 305
#define tag_artist 315
#define tag_date_time 306
#define tag_image_description 270

#define tag_exif_ifd 34665
#define tag_gps_ifd 34853

#define resunit_none 1
#define resunit_inch 2
#define resunit_centimeter 3

/* tags from the EXIF ifd */
#define tag_exif_version 0x9000
#define tag_flashpix_version 0xA000
#define tag_color_space 0xA001
#define tag_component_configuration 0x9101
#define tag_component_bits_per_pixel 0x9102
#define tag_pixel_x_dimension 0xA002
#define tag_pixel_y_dimension 0xA003
#define tag_maker_note 0x927C
#define tag_user_comment 0x9286
#define tag_related_sound_file 0xA004
#define tag_date_time_original 0x9003
#define tag_date_time_digitized 0x9004
#define tag_sub_sec_time 0x9290
#define tag_sub_sec_time_original 0x9291
#define tag_sub_sec_time_digitized 0x9292
#define tag_image_unique_id 0xA420
#define tag_exposure_time 0x829a
#define tag_f_number 0x829D
#define tag_exposure_program 0x8822
#define tag_spectral_sensitivity 0x8824
#define tag_iso_speed_ratings 0x8827
#define tag_oecf 0x8828
#define tag_shutter_speed 0x9201
#define tag_aperture 0x9202
#define tag_brightness 0x9203
#define tag_exposure_bias 0x9204
#define tag_max_aperture 0x9205
#define tag_subject_distance 0x9206
#define tag_metering_mode 0x9207
#define tag_light_source 0x9208
#define tag_flash 0x9209
#define tag_focal_length 0x920a
#define tag_subject_area 0x9214
#define tag_flash_energy 0xA20B
#define tag_spatial_frequency_response 0xA20C
#define tag_focal_plane_x_resolution 0xA20e
#define tag_focal_plane_y_resolution 0xA20F
#define tag_focal_plane_resolution_unit 0xA210
#define tag_subject_location 0xA214
#define tag_exposure_index 0xA215
#define tag_sensing_method 0xA217
#define tag_file_source 0xA300
#define tag_scene_type 0xA301
#define tag_cfa_pattern 0xA302
#define tag_custom_rendered 0xA401
#define tag_exposure_mode 0xA402
#define tag_white_balance 0xA403
#define tag_digital_zoom_ratio 0xA404
#define tag_focal_length_in_35mm_film 0xA405
#define tag_scene_capture_type 0xA406
#define tag_gain_control 0xA407
#define tag_contrast 0xA408
#define tag_saturation 0xA409
#define tag_sharpness 0xA40A
#define tag_device_setting_description 0xA40B
#define tag_subject_distance_range 0xA40C

/* GPS tags */
#define tag_gps_version_id 0
#define tag_gps_latitude_ref 1
#define tag_gps_latitude 2
#define tag_gps_longitude_ref 3
#define tag_gps_longitude 4
#define tag_gps_altitude_ref 5
#define tag_gps_altitude 6
#define tag_gps_time_stamp 7
#define tag_gps_satellites 8
#define tag_gps_status 9
#define tag_gps_measure_mode 10
#define tag_gps_dop 11
#define tag_gps_speed_ref 12
#define tag_gps_speed 13
#define tag_gps_track_ref 14
#define tag_gps_track 15
#define tag_gps_img_direction_ref 16
#define tag_gps_img_direction 17
#define tag_gps_map_datum 18
#define tag_gps_dest_latitude_ref 19
#define tag_gps_dest_latitude 20
#define tag_gps_dest_longitude_ref 21
#define tag_gps_dest_longitude 22
#define tag_gps_dest_bearing_ref 23
#define tag_gps_dest_bearing 24
#define tag_gps_dest_distance_ref 25
#define tag_gps_dest_distance 26
#define tag_gps_processing_method 27
#define tag_gps_area_information 28
#define tag_gps_date_stamp 29
#define tag_gps_differential 30

/* don't use this on pointers */
#define ARRAY_COUNT(array) (sizeof(array)/sizeof(*array))

/* in memory tiff structure */
typedef struct {
  /* the data we use as a tiff */
  unsigned char *base;
  size_t size;

  /* intel or motorola byte order */
  tiff_type type;

  /* initial ifd offset */
  unsigned long first_ifd_offset;
  
  /* size (in entries) and data */
  int ifd_size; 
  ifd_entry *ifd;
  unsigned long next_ifd;
} imtiff;

static int tiff_init(imtiff *tiff, unsigned char *base, size_t length);
static int tiff_load_ifd(imtiff *tiff, unsigned long offset);
static void tiff_final(imtiff *tiff);
static void tiff_clear_ifd(imtiff *tiff);
#if 0 /* currently unused, but that may change */
static int tiff_get_bytes(imtiff *tiff, unsigned char *to, size_t offset, 
			  size_t count);
#endif
static int tiff_get_tag_double(imtiff *, int index, double *result);
static int tiff_get_tag_int(imtiff *, int index, int *result);
static unsigned tiff_get16(imtiff *, unsigned long offset);
static unsigned tiff_get32(imtiff *, unsigned long offset);
static int tiff_get16s(imtiff *, unsigned long offset);
static int tiff_get32s(imtiff *, unsigned long offset);
static double tiff_get_rat(imtiff *, unsigned long offset);
static double tiff_get_rats(imtiff *, unsigned long offset);
static void save_ifd0_tags(i_img *im, imtiff *tiff, unsigned long *exif_ifd_offset, unsigned long *gps_ifd_offset);
static void save_exif_ifd_tags(i_img *im, imtiff *tiff);
static void save_gps_ifd_tags(i_img *im, imtiff *tiff);
static void
copy_string_tags(i_img *im, imtiff *tiff, tag_map *map, int map_count);
static void
copy_int_tags(i_img *im, imtiff *tiff, tag_map *map, int map_count);
static void
copy_rat_tags(i_img *im, imtiff *tiff, tag_map *map, int map_count);
static void
copy_num_array_tags(i_img *im, imtiff *tiff, tag_map *map, int map_count);
static void
copy_name_tags(i_img *im, imtiff *tiff, tag_value_map *map, int map_count);
static void process_maker_note(i_img *im, imtiff *tiff, unsigned long offset, size_t size);

/*
=head1 PUBLIC FUNCTIONS

These functions are available to other parts of Imager.  They aren't
intended to be called from outside of Imager.

=over

=item i_int_decode_exit

i_int_decode_exif(im, data_base, data_size);

The data from data_base for data_size bytes will be scanned for EXIF
data.

Any data found will be used to set tags in the supplied image.

The intent is that invalid EXIF data will simply fail to set tags, and
write to the log.  In no case should this code exit when supplied
invalid data.

Returns true if an Exif header was seen.

=cut
*/

int
i_int_decode_exif(i_img *im, unsigned char *data, size_t length) {
  imtiff tiff;
  unsigned long exif_ifd_offset = 0;
  unsigned long gps_ifd_offset = 0;
  /* basic checks - must start with "Exif\0\0" */

  if (length < 6 || memcmp(data, "Exif\0\0", 6) != 0) {
    return 0;
  }

  data += 6;
  length -= 6;

  if (!tiff_init(&tiff, data, length)) {
    mm_log((2, "Exif header found, but no valid TIFF header\n"));
    return 1;
  }
  if (!tiff_load_ifd(&tiff, tiff.first_ifd_offset)) {
    mm_log((2, "Exif header found, but could not load IFD 0\n"));
    tiff_final(&tiff);
    return 1;
  }

  save_ifd0_tags(im, &tiff, &exif_ifd_offset, &gps_ifd_offset);

  if (exif_ifd_offset) {
    if (tiff_load_ifd(&tiff, exif_ifd_offset)) {
      save_exif_ifd_tags(im, &tiff);
    }
    else {
      mm_log((2, "Could not load Exif IFD\n"));
    }
  }

  if (gps_ifd_offset) {
    if (tiff_load_ifd(&tiff, gps_ifd_offset)) {
      save_gps_ifd_tags(im, &tiff);
    }
    else {
      mm_log((2, "Could not load GPS IFD\n"));
    }
  }

  tiff_final(&tiff);

  return 1;
}

/*

=back

=head1 INTERNAL FUNCTIONS

=head2 EXIF Processing 

=over

=item save_ifd0_tags

save_ifd0_tags(im, tiff, &exif_ifd_offset, &gps_ifd_offset)

Scans the currently loaded IFD for tags expected in IFD0 and sets them
in the image.

Sets *exif_ifd_offset to the offset of the EXIF IFD if found.

=cut

*/

static tag_map ifd0_string_tags[] =
  {
    { tag_make, "exif_make" },
    { tag_model, "exif_model" },
    { tag_copyright, "exif_copyright" },
    { tag_software, "exif_software" },
    { tag_artist, "exif_artist" },
    { tag_date_time, "exif_date_time" },
    { tag_image_description, "exif_image_description" },
  };

static const int ifd0_string_tag_count = ARRAY_COUNT(ifd0_string_tags);

static tag_map ifd0_int_tags[] =
  {
    { tag_orientation, "exif_orientation", },
    { tag_resolution_unit, "exif_resolution_unit" },
  };

static const int ifd0_int_tag_count = ARRAY_COUNT(ifd0_int_tags);

static tag_map ifd0_rat_tags[] =
  {
    { tag_x_resolution, "exif_x_resolution" },
    { tag_y_resolution, "exif_y_resolution" },
  };

static tag_map resolution_unit_values[] =
  {
    { 1, "none" },
    { 2, "inches" },
    { 3, "centimeters" },
  };

static tag_value_map ifd0_values[] =
  {
    VALUE_MAP_ENTRY(resolution_unit),
  };

static void
save_ifd0_tags(i_img *im, imtiff *tiff, unsigned long *exif_ifd_offset,
	       unsigned long *gps_ifd_offset) {
  int tag_index;
  int work;
  ifd_entry *entry;

  for (tag_index = 0, entry = tiff->ifd; 
       tag_index < tiff->ifd_size; ++tag_index, ++entry) {
    switch (entry->tag) {
    case tag_exif_ifd:
      if (tiff_get_tag_int(tiff, tag_index, &work))
	*exif_ifd_offset = work;
      break;

    case tag_gps_ifd:
      if (tiff_get_tag_int(tiff, tag_index, &work))
	*gps_ifd_offset = work;
      break;
    }
  }

  copy_string_tags(im, tiff, ifd0_string_tags, ifd0_string_tag_count);
  copy_int_tags(im, tiff, ifd0_int_tags, ifd0_int_tag_count);
  copy_rat_tags(im, tiff, ifd0_rat_tags, ARRAY_COUNT(ifd0_rat_tags));
  copy_name_tags(im, tiff, ifd0_values, ARRAY_COUNT(ifd0_values));
  /* copy_num_array_tags(im, tiff, ifd0_num_arrays, ARRAY_COUNT(ifd0_num_arrays)); */
}

/*
=item save_exif_ifd_tags

save_exif_ifd_tags(im, tiff)

Scans the currently loaded IFD for the tags expected in the EXIF IFD
and sets them as tags in the image.

=cut

*/

static tag_map exif_ifd_string_tags[] =
  {
    { tag_exif_version, "exif_version", },
    { tag_flashpix_version, "exif_flashpix_version", },
    { tag_related_sound_file, "exif_related_sound_file", },
    { tag_date_time_original, "exif_date_time_original", },
    { tag_date_time_digitized, "exif_date_time_digitized", },
    { tag_sub_sec_time, "exif_sub_sec_time" },
    { tag_sub_sec_time_original, "exif_sub_sec_time_original" },
    { tag_sub_sec_time_digitized, "exif_sub_sec_time_digitized" },
    { tag_image_unique_id, "exif_image_unique_id" },
    { tag_spectral_sensitivity, "exif_spectral_sensitivity" },
  };

static const int exif_ifd_string_tag_count = ARRAY_COUNT(exif_ifd_string_tags);

static tag_map exif_ifd_int_tags[] =
  {
    { tag_color_space, "exif_color_space" },
    { tag_exposure_program, "exif_exposure_program" },
    { tag_metering_mode, "exif_metering_mode" },
    { tag_light_source, "exif_light_source" },
    { tag_flash, "exif_flash" },
    { tag_focal_plane_resolution_unit, "exif_focal_plane_resolution_unit" },
    { tag_subject_location, "exif_subject_location" },
    { tag_sensing_method, "exif_sensing_method" },
    { tag_custom_rendered, "exif_custom_rendered" },
    { tag_exposure_mode, "exif_exposure_mode" },
    { tag_white_balance, "exif_white_balance" },
    { tag_focal_length_in_35mm_film, "exif_focal_length_in_35mm_film" },
    { tag_scene_capture_type, "exif_scene_capture_type" },
    { tag_contrast, "exif_contrast" },
    { tag_saturation, "exif_saturation" },
    { tag_sharpness, "exif_sharpness" },
    { tag_subject_distance_range, "exif_subject_distance_range" },
  };


static const int exif_ifd_int_tag_count = ARRAY_COUNT(exif_ifd_int_tags);

static tag_map exif_ifd_rat_tags[] =
  {
    { tag_exposure_time, "exif_exposure_time" },
    { tag_f_number, "exif_f_number" },
    { tag_shutter_speed, "exif_shutter_speed" },
    { tag_aperture, "exif_aperture" },
    { tag_brightness, "exif_brightness" },
    { tag_exposure_bias, "exif_exposure_bias" },
    { tag_max_aperture, "exif_max_aperture" },
    { tag_subject_distance, "exif_subject_distance" },
    { tag_focal_length, "exif_focal_length" },
    { tag_flash_energy, "exif_flash_energy" },
    { tag_focal_plane_x_resolution, "exif_focal_plane_x_resolution" },
    { tag_focal_plane_y_resolution, "exif_focal_plane_y_resolution" },
    { tag_exposure_index, "exif_exposure_index" },
    { tag_digital_zoom_ratio, "exif_digital_zoom_ratio" },
    { tag_gain_control, "exif_gain_control" },
  };

static const int exif_ifd_rat_tag_count = ARRAY_COUNT(exif_ifd_rat_tags);

static tag_map exposure_mode_values[] =
  {
    { 0, "Auto exposure" },
    { 1, "Manual exposure" },
    { 2, "Auto bracket" },
  };
static tag_map color_space_values[] =
  {
    { 1, "sRGB" },
    { 0xFFFF, "Uncalibrated" },
  };

static tag_map exposure_program_values[] =
  {
    { 0, "Not defined" },
    { 1, "Manual" },
    { 2, "Normal program" },
    { 3, "Aperture priority" },
    { 4, "Shutter priority" },
    { 5, "Creative program" },
    { 6, "Action program" },
    { 7, "Portrait mode" },
    { 8, "Landscape mode" },
  };

static tag_map metering_mode_values[] =
  {
    { 0, "unknown" },
    { 1, "Average" },
    { 2, "CenterWeightedAverage" },
    { 3, "Spot" },
    { 4, "MultiSpot" },
    { 5, "Pattern" },
    { 6, "Partial" },
    { 255, "other" },
  };

static tag_map light_source_values[] =
  {
    { 0, "unknown" },
    { 1, "Daylight" },
    { 2, "Fluorescent" },
    { 3, "Tungsten (incandescent light)" },
    { 4, "Flash" },
    { 9, "Fine weather" },
    { 10, "Cloudy weather" },
    { 11, "Shade" },
    { 12, "Daylight fluorescent (D 5700 Ð 7100K)" },
    { 13, "Day white fluorescent (N 4600 Ð 5400K)" },
    { 14, "Cool white fluorescent (W 3900 Ð 4500K)" },
    { 15, "White fluorescent (WW 3200 Ð 3700K)" },
    { 17, "Standard light A" },
    { 18, "Standard light B" },
    { 19, "Standard light C" },
    { 20, "D55" },
    { 21, "D65" },
    { 22, "D75" },
    { 23, "D50" },
    { 24, "ISO studio tungsten" },
    { 255, "other light source" },
  };

static tag_map flash_values[] =
  {
    { 0x0000, "Flash did not fire." },
    { 0x0001, "Flash fired." },
    { 0x0005, "Strobe return light not detected." },
    { 0x0007, "Strobe return light detected." },
    { 0x0009, "Flash fired, compulsory flash mode" },
    { 0x000D, "Flash fired, compulsory flash mode, return light not detected" },
    { 0x000F, "Flash fired, compulsory flash mode, return light detected" },
    { 0x0010, "Flash did not fire, compulsory flash mode" },
    { 0x0018, "Flash did not fire, auto mode" },
    { 0x0019, "Flash fired, auto mode" },
    { 0x001D, "Flash fired, auto mode, return light not detected" },
    { 0x001F, "Flash fired, auto mode, return light detected" },
    { 0x0020, "No flash function" },
    { 0x0041, "Flash fired, red-eye reduction mode" },
    { 0x0045, "Flash fired, red-eye reduction mode, return light not detected" },
    { 0x0047, "Flash fired, red-eye reduction mode, return light detected" },
    { 0x0049, "Flash fired, compulsory flash mode, red-eye reduction mode" },
    { 0x004D, "Flash fired, compulsory flash mode, red-eye reduction mode, return light not detected" },
    { 0x004F, "Flash fired, compulsory flash mode, red-eye reduction mode, return light detected" },
    { 0x0059, "Flash fired, auto mode, red-eye reduction mode" },
    { 0x005D, "Flash fired, auto mode, return light not detected, red-eye reduction mode" },
    { 0x005F, "Flash fired, auto mode, return light detected, red-eye reduction mode" },
  };

static tag_map sensing_method_values[] =
  {
    { 1, "Not defined" },
    { 2, "One-chip color area sensor" },
    { 3, "Two-chip color area sensor" },
    { 4, "Three-chip color area sensor" },
    { 5, "Color sequential area sensor" },
    { 7, "Trilinear sensor" },
    { 8, "Color sequential linear sensor" },
  };

static tag_map custom_rendered_values[] =
  {
    { 0, "Normal process" },
    { 1, "Custom process" },
  };

static tag_map white_balance_values[] =
  {
    { 0, "Auto white balance" },
    { 1, "Manual white balance" },
  };

static tag_map scene_capture_type_values[] =
  {
    { 0, "Standard" },
    { 1, "Landscape" },
    { 2, "Portrait" },
    { 3, "Night scene" },
  };

static tag_map gain_control_values[] =
  {
    { 0, "None" },
    { 1, "Low gain up" },
    { 2, "High gain up" },
    { 3, "Low gain down" },
    { 4, "High gain down" },
  };

static tag_map contrast_values[] =
  {
    { 0, "Normal" },
    { 1, "Soft" },
    { 2, "Hard" },
  };

static tag_map saturation_values[] =
  {
    { 0, "Normal" },
    { 1, "Low saturation" },
    { 2, "High saturation" },
  };

static tag_map sharpness_values[] =
  {
    { 0, "Normal" },
    { 1, "Soft" },
    { 2, "Hard" },
  };

static tag_map subject_distance_range_values[] =
  {
    { 0, "unknown" },
    { 1, "Macro" },
    { 2, "Close view" },
    { 3, "Distant view" },
  };

#define focal_plane_resolution_unit_values resolution_unit_values

static tag_value_map exif_ifd_values[] =
  {
    VALUE_MAP_ENTRY(exposure_mode),
    VALUE_MAP_ENTRY(color_space),
    VALUE_MAP_ENTRY(exposure_program),
    VALUE_MAP_ENTRY(metering_mode),
    VALUE_MAP_ENTRY(light_source),
    VALUE_MAP_ENTRY(flash),
    VALUE_MAP_ENTRY(sensing_method),
    VALUE_MAP_ENTRY(custom_rendered),
    VALUE_MAP_ENTRY(white_balance),
    VALUE_MAP_ENTRY(scene_capture_type),
    VALUE_MAP_ENTRY(gain_control),
    VALUE_MAP_ENTRY(contrast),
    VALUE_MAP_ENTRY(saturation),
    VALUE_MAP_ENTRY(sharpness),
    VALUE_MAP_ENTRY(subject_distance_range),
    VALUE_MAP_ENTRY(focal_plane_resolution_unit),
  };

static tag_map exif_num_arrays[] =
  {
    { tag_iso_speed_ratings, "exif_iso_speed_ratings" },
    { tag_subject_area, "exif_subject_area" },
    { tag_subject_location, "exif_subject_location" },
  };

static void
save_exif_ifd_tags(i_img *im, imtiff *tiff) {
  int i, tag_index;
  ifd_entry *entry;
  char *user_comment;
  unsigned long maker_note_offset = 0;
  size_t maker_note_size = 0;

  for (tag_index = 0, entry = tiff->ifd; 
       tag_index < tiff->ifd_size; ++tag_index, ++entry) {
    switch (entry->tag) {
    case tag_user_comment:
      /* I don't want to trash the source, so work on a copy */
      user_comment = mymalloc(entry->size);
      memcpy(user_comment, tiff->base + entry->offset, entry->size);
      /* the first 8 bytes indicate the encoding, make them into spaces
	 for better presentation */
      for (i = 0; i < entry->size && i < 8; ++i) {
	if (user_comment[i] == '\0')
	  user_comment[i] = ' ';
      }
      /* find the actual end of the string */
      while (i < entry->size && user_comment[i])
	++i;
      i_tags_set(&im->tags, "exif_user_comment", user_comment, i);
      myfree(user_comment);
      break;

    case tag_maker_note:
      maker_note_offset = entry->offset;
      maker_note_size = entry->size;
      break;

      /* the following aren't processed yet */
    case tag_oecf:
    case tag_spatial_frequency_response:
    case tag_file_source:
    case tag_scene_type:
    case tag_cfa_pattern:
    case tag_device_setting_description:
    case tag_subject_area:
      break;
    }
  }

  copy_string_tags(im, tiff, exif_ifd_string_tags, exif_ifd_string_tag_count);
  copy_int_tags(im, tiff, exif_ifd_int_tags, exif_ifd_int_tag_count);
  copy_rat_tags(im, tiff, exif_ifd_rat_tags, exif_ifd_rat_tag_count);
  copy_name_tags(im, tiff, exif_ifd_values, ARRAY_COUNT(exif_ifd_values));
  copy_num_array_tags(im, tiff, exif_num_arrays, ARRAY_COUNT(exif_num_arrays));

  /* This trashes the IFD - make sure it's done last */
  if (maker_note_offset) {
    process_maker_note(im, tiff, maker_note_offset, maker_note_size);
  }
}

static tag_map gps_ifd_string_tags[] =
  {
    { tag_gps_version_id, "exif_gps_version_id" },
    { tag_gps_latitude_ref, "exif_gps_latitude_ref" },
    { tag_gps_longitude_ref, "exif_gps_longitude_ref" },
    { tag_gps_altitude_ref, "exif_gps_altitude_ref" },
    { tag_gps_satellites, "exif_gps_satellites" },
    { tag_gps_status, "exif_gps_status" },
    { tag_gps_measure_mode, "exif_gps_measure_mode" },
    { tag_gps_speed_ref, "exif_gps_speed_ref" },
    { tag_gps_track_ref, "exif_gps_track_ref" },
  };

static tag_map gps_ifd_int_tags[] =
  {
    { tag_gps_differential, "exif_gps_differential" },
  };

static tag_map gps_ifd_rat_tags[] =
  {
    { tag_gps_altitude, "exif_gps_altitude" },
    { tag_gps_time_stamp, "exif_gps_time_stamp" },
    { tag_gps_dop, "exif_gps_dop" },
    { tag_gps_speed, "exif_gps_speed" },
    { tag_gps_track, "exif_track" }
  };

static tag_map gps_differential_values [] =
  {
    { 0, "without differential correction" },
    { 1, "Differential correction applied" },
  };

static tag_value_map gps_ifd_values[] =
  {
    VALUE_MAP_ENTRY(gps_differential),
  };

static tag_map gps_num_arrays[] =
  {
    { tag_gps_latitude, "exif_gps_latitude" },
    { tag_gps_longitude, "exif_gps_longitude" },
  };

static void
save_gps_ifd_tags(i_img *im, imtiff *tiff) {
  /* int i, tag_index; 
  int work;
  ifd_entry *entry; */

  /* for (tag_index = 0, entry = tiff->ifd; 
       tag_index < tiff->ifd_size; ++tag_index, ++entry) {
    switch (entry->tag) {
      break;
    }
    }*/

  copy_string_tags(im, tiff, gps_ifd_string_tags, 
	 ARRAY_COUNT(gps_ifd_string_tags));
  copy_int_tags(im, tiff, gps_ifd_int_tags, ARRAY_COUNT(gps_ifd_int_tags));
  copy_rat_tags(im, tiff, gps_ifd_rat_tags, ARRAY_COUNT(gps_ifd_rat_tags));
  copy_name_tags(im, tiff, gps_ifd_values, ARRAY_COUNT(gps_ifd_values));
  copy_num_array_tags(im, tiff, gps_num_arrays, ARRAY_COUNT(gps_num_arrays));
}

/*
=item process_maker_note

This is a stub for processing the maker note tag.

Maker notes aren't covered by EXIF itself and in general aren't
documented by the manufacturers.

=cut
*/

static void
process_maker_note(i_img *im, imtiff *tiff, unsigned long offset, size_t size) {
  /* this will be added in a future release */
}

/*
=back

=head2 High level TIFF functions

To avoid relying upon tifflib when we're not processing an image we
have some simple in-memory TIFF file management.

=over

=item tiff_init

imtiff tiff;
if (tiff_init(tiff, data_base, data_size)) {
  // success
}

Initialize the tiff data structure.

Scans for the byte order and version markers, and stores the offset to
the first IFD (IFD0 in EXIF) in first_ifd_offset.

=cut
*/

static int
tiff_init(imtiff *tiff, unsigned char *data, size_t length) {
  int version;

  tiff->base = data;
  tiff->size = length;
  if (length < 8) /* well... would have to be much bigger to be useful */
    return 0;
  if (data[0] == 'M' && data[1] == 'M')
    tiff->type = tt_motorola;
  else if (data[0] == 'I' && data[1] == 'I') 
    tiff->type = tt_intel;
  else
    return 0; /* invalid header */

  version = tiff_get16(tiff, 2);
  if (version != 42)
    return 0;

  tiff->first_ifd_offset = tiff_get32(tiff, 4);
  if (tiff->first_ifd_offset > length || tiff->first_ifd_offset < 8)
    return 0;

  tiff->ifd_size = 0;
  tiff->ifd = NULL;
  tiff->next_ifd = 0;

  return 1;
}

/*
=item tiff_final

tiff_final(&tiff)

Clean up the tiff structure initialized by tiff_init()

=cut
*/

static void
tiff_final(imtiff *tiff) {
  tiff_clear_ifd(tiff);
}

/*
=item tiff_load_ifd

if (tiff_load_ifd(tiff, offset)) {
  // process the ifd
}

Loads the IFD from the given offset into the tiff objects ifd.

This can fail if the IFD extends beyond end of file, or if any data
offsets combined with their sizes, extends beyond end of file.

Returns true on success.

=cut
*/

static int
tiff_load_ifd(imtiff *tiff, unsigned long offset) {
  unsigned count;
  int ifd_size;
  ifd_entry *entries = NULL;
  int i;
  unsigned long base;

  tiff_clear_ifd(tiff);

  /* rough check count + 1 entry + next offset */
  if (offset + (2+12+4) > tiff->size) {
    mm_log((2, "offset %lu beyond end off Exif block", offset));
    return 0;
  }

  count = tiff_get16(tiff, offset);
  
  /* check we can fit the whole thing */
  ifd_size = 2 + count * 12 + 4; /* count + count entries + next offset */
  if (offset + ifd_size > tiff->size) {
    mm_log((2, "offset %lu beyond end off Exif block", offset));
    return 0;
  }

  entries = mymalloc(count * sizeof(ifd_entry));
  memset(entries, 0, count * sizeof(ifd_entry));
  base = offset + 2;
  for (i = 0; i < count; ++i) {
    ifd_entry *entry = entries + i;
    entry->tag = tiff_get16(tiff, base);
    entry->type = tiff_get16(tiff, base+2);
    entry->count = tiff_get32(tiff, base+4);
    if (entry->type >= 1 && entry->type <= ift_last) {
      entry->item_size = type_sizes[entry->type];
      entry->size = entry->item_size * entry->count;
      if (entry->size / entry->item_size != entry->count) {
	myfree(entries);
	mm_log((1, "Integer overflow calculating tag data size processing EXIF block\n"));
	return 0;
      }
      else if (entry->size <= 4) {
	entry->offset = base + 8;
      }
      else {
	entry->offset = tiff_get32(tiff, base+8);
	if (entry->offset + entry->size > tiff->size) {
	  mm_log((2, "Invalid data offset processing IFD\n"));
	  myfree(entries);
	  return 0;
	}
      }
    }
    else {
      entry->size = 0;
      entry->offset = 0;
    }
    base += 12;
  }

  tiff->ifd_size = count;
  tiff->ifd = entries;
  tiff->next_ifd = tiff_get32(tiff, base);

  return 1;
}

/*
=item tiff_clear_ifd

tiff_clear_ifd(tiff)

Releases any memory associated with the stored IFD and resets the IFD
pointers.

This is called by tiff_load_ifd() and tiff_final().

=cut
*/

static void
tiff_clear_ifd(imtiff *tiff) {
  if (tiff->ifd_size && tiff->ifd) {
    myfree(tiff->ifd);
    tiff->ifd_size = 0;
    tiff->ifd = NULL;
  }
}

/*
=item tiff_get_tag_double

  double value;
  if (tiff_get_tag(tiff, index, &value)) {
    // process value
  }

Attempts to retrieve a double value from the given index in the
current IFD.

The value must have a count of 1.

=cut
*/

static int
tiff_get_tag_double_array(imtiff *tiff, int index, double *result, 
			  int array_index) {
  ifd_entry *entry;
  unsigned long offset;
  if (index < 0 || index >= tiff->ifd_size) {
    mm_log((3, "tiff_get_tag_double_array() tag index out of range"));
    return 0;
  }
  
  entry = tiff->ifd + index;
  if (array_index < 0 || array_index >= entry->count) {
    mm_log((3, "tiff_get_tag_double_array() array index out of range"));
    return 0;
  }

  offset = entry->offset + array_index * entry->item_size;

  switch (entry->type) {
  case ift_short:
    *result = tiff_get16(tiff, offset);
    return 1;
   
  case ift_long:
    *result = tiff_get32(tiff, offset);
    return 1;

  case ift_rational:
    *result = tiff_get_rat(tiff, offset);
    return 1;

  case ift_sshort:
    *result = tiff_get16s(tiff, offset);
    return 1;

  case ift_slong:
    *result = tiff_get32s(tiff, offset);
    return 1;

  case ift_srational:
    *result = tiff_get_rats(tiff, offset);
    return 1;

  case ift_byte:
    *result = *(tiff->base + offset);
    return 1;
  }

  return 0;
}

/*
=item tiff_get_tag_double

  double value;
  if (tiff_get_tag(tiff, index, &value)) {
    // process value
  }

Attempts to retrieve a double value from the given index in the
current IFD.

The value must have a count of 1.

=cut
*/

static int
tiff_get_tag_double(imtiff *tiff, int index, double *result) {
  ifd_entry *entry;
  if (index < 0 || index >= tiff->ifd_size) {
    mm_log((3, "tiff_get_tag_double() index out of range"));
    return 0;
  }
  
  entry = tiff->ifd + index;
  if (entry->count != 1) {
    mm_log((3, "tiff_get_tag_double() called on tag with multiple values"));
    return 0;
  }

  return tiff_get_tag_double_array(tiff, index, result, 0);
}

/*
=item tiff_get_tag_int_array

  int value;
  if (tiff_get_tag_int_array(tiff, index, &value, array_index)) {
    // process value
  }

Attempts to retrieve an integer value from the given index in the
current IFD.

=cut
*/

static int
tiff_get_tag_int_array(imtiff *tiff, int index, int *result, int array_index) {
  ifd_entry *entry;
  unsigned long offset;
  if (index < 0 || index >= tiff->ifd_size) {
    mm_log((3, "tiff_get_tag_int_array() tag index out of range"));
    return 0;
  }
  
  entry = tiff->ifd + index;
  if (array_index < 0 || array_index >= entry->count) {
    mm_log((3, "tiff_get_tag_int_array() array index out of range"));
    return 0;
  }

  offset = entry->offset + array_index * entry->item_size;

  switch (entry->type) {
  case ift_short:
    *result = tiff_get16(tiff, offset);
    return 1;
   
  case ift_long:
    *result = tiff_get32(tiff, offset);
    return 1;

  case ift_sshort:
    *result = tiff_get16s(tiff, offset);
    return 1;

  case ift_slong:
    *result = tiff_get32s(tiff, offset);
    return 1;

  case ift_byte:
    *result = *(tiff->base + offset);
    return 1;
  }

  return 0;
}

/*
=item tiff_get_tag_int

  int value;
  if (tiff_get_tag_int(tiff, index, &value)) {
    // process value
  }

Attempts to retrieve an integer value from the given index in the
current IFD.

The value must have a count of 1.

=cut
*/

static int
tiff_get_tag_int(imtiff *tiff, int index, int *result) {
  ifd_entry *entry;
  if (index < 0 || index >= tiff->ifd_size) {
    mm_log((3, "tiff_get_tag_int() index out of range"));
    return 0;
  }

  entry = tiff->ifd + index;
  if (entry->count != 1) {
    mm_log((3, "tiff_get_tag_int() called on tag with multiple values"));
    return 0;
  }

  return tiff_get_tag_int_array(tiff, index, result, 0);
}

/*
=back

=head2 Table-based tag setters

This set of functions checks for matches between the current IFD and
tags supplied in an array, when there's a match it sets the
appropriate tag in the image.

=over

=item copy_int_tags

Scans the IFD for integer tags and sets them in the image,

=cut
*/

static void
copy_int_tags(i_img *im, imtiff *tiff, tag_map *map, int map_count) {
  int i, tag_index;
  ifd_entry *entry;

  for (tag_index = 0, entry = tiff->ifd; 
       tag_index < tiff->ifd_size; ++tag_index, ++entry) {
    for (i = 0; i < map_count; ++i) {
      int value;
      if (map[i].tag == entry->tag
	  && tiff_get_tag_int(tiff, tag_index, &value)) {
	i_tags_setn(&im->tags, map[i].name, value);
	break;
      }
    }
  }
}

/*
=item copy_rat_tags

Scans the IFD for rational tags and sets them in the image.

=cut
*/

static void
copy_rat_tags(i_img *im, imtiff *tiff, tag_map *map, int map_count) {
  int i, tag_index;
  ifd_entry *entry;

  for (tag_index = 0, entry = tiff->ifd; 
       tag_index < tiff->ifd_size; ++tag_index, ++entry) {
    for (i = 0; i < map_count; ++i) {
      double value;
      if (map[i].tag == entry->tag
	  && tiff_get_tag_double(tiff, tag_index, &value)) {
	i_tags_set_float2(&im->tags, map[i].name, 0, value, 6);
	break;
      }
    }
  }
}

/*
=item copy_string_tags

Scans the IFD for string tags and sets them in the image.

=cut
*/

static void
copy_string_tags(i_img *im, imtiff *tiff, tag_map *map, int map_count) {
  int i, tag_index;
  ifd_entry *entry;

  for (tag_index = 0, entry = tiff->ifd; 
       tag_index < tiff->ifd_size; ++tag_index, ++entry) {
    for (i = 0; i < map_count; ++i) {
      if (map[i].tag == entry->tag) {
	int len = entry->type == ift_ascii ? entry->size - 1 : entry->size;
	i_tags_set(&im->tags, map[i].name,
		   (char const *)(tiff->base + entry->offset), len);
	break;
      }
    }
  }
}

/*
=item copy_num_array_tags

Scans the IFD for arrays of numbers and sets them in the image.

=cut
*/

/* a more general solution would be better in some ways, but we don't need it */
#define MAX_ARRAY_VALUES 10
#define MAX_ARRAY_STRING (MAX_ARRAY_VALUES * 20)

static void
copy_num_array_tags(i_img *im, imtiff *tiff, tag_map *map, int map_count) {
  int i, j, tag_index;
  ifd_entry *entry;

  for (tag_index = 0, entry = tiff->ifd; 
       tag_index < tiff->ifd_size; ++tag_index, ++entry) {
    for (i = 0; i < map_count; ++i) {
      if (map[i].tag == entry->tag && entry->count <= MAX_ARRAY_VALUES) {
	if (entry->type == ift_rational || entry->type == ift_srational) {
	  double value;
	  char workstr[MAX_ARRAY_STRING];
	  size_t len = 0, item_len;
	  *workstr = '\0';
	  for (j = 0; j < entry->count; ++j) {
	    if (!tiff_get_tag_double_array(tiff, tag_index, &value, j)) {
	      mm_log((3, "unexpected failure from tiff_get_tag_double_array(..., %d, ..., %d)\n", tag_index, j));
	      return;
	    }
	    if (len >= sizeof(workstr) - 1) {
	      mm_log((3, "Buffer would overflow reading tag %#x\n", entry->tag));
	      return;
	    }
	    if (j) {
	      strcat(workstr, " ");
	      ++len;
	    }
#ifdef IMAGER_SNPRINTF
	    item_len = snprintf(workstr + len, sizeof(workstr)-len, "%.6g", value);
#else
	    item_len = sprintf(workstr + len, "%.6g", value);
#endif
	    len += item_len;
	  }
	  i_tags_set(&im->tags, map[i].name, workstr, -1);
	}
	else if (entry->type == ift_short || entry->type == ift_long
		 || entry->type == ift_sshort || entry->type == ift_slong
		 || entry->type == ift_byte) {
	  int value;
	  char workstr[MAX_ARRAY_STRING];
	  size_t len = 0, item_len;
	  *workstr = '\0';
	  for (j = 0; j < entry->count; ++j) {
	    if (!tiff_get_tag_int_array(tiff, tag_index, &value, j)) {
	      mm_log((3, "unexpected failure from tiff_get_tag_int_array(..., %d, ..., %d)\n", tag_index, j));
	      return;
	    }
	    if (len >= sizeof(workstr) - 1) {
	      mm_log((3, "Buffer would overflow reading tag %#x\n", entry->tag));
	      return;
	    }
	    if (j) {
	      strcat(workstr, " ");
	      ++len;
	    }
#ifdef IMAGER_SNPRINTF
	    item_len = snprintf(workstr + len, sizeof(workstr) - len, "%d", value);
#else
	    item_len = sprintf(workstr + len, "%d", value);
#endif
	    len += item_len;
	  }
	  i_tags_set(&im->tags, map[i].name, workstr, -1);
	}
	break;
      }
    }
  }
}

/*
=item copy_name_tags

This function maps integer values to descriptions for those values.

In general we handle the integer value through copy_int_tags() and
then the same tage with a "_name" suffix here.

=cut
*/

static void
copy_name_tags(i_img *im, imtiff *tiff, tag_value_map *map, int map_count) {
  int i, j, tag_index;
  ifd_entry *entry;

  for (tag_index = 0, entry = tiff->ifd; 
       tag_index < tiff->ifd_size; ++tag_index, ++entry) {
    for (i = 0; i < map_count; ++i) {
      int value;
      if (map[i].tag == entry->tag
	  && tiff_get_tag_int(tiff, tag_index, &value)) {
	tag_map const *found = NULL;
	for (j = 0; j < map[i].map_count; ++j) {
	  if (value == map[i].map[j].tag) {
	    found = map[i].map + j;
	    break;
	  }
	}
	if (found) {
	  i_tags_set(&im->tags, map[i].name, found->name, -1);
	}
	break;
      }
    }
  }
}


/*
=back

=head2 Low level data access functions

These functions use the byte order in the tiff object to extract
various types of data from the tiff data.

These functions will abort if called with an out of range offset.

The intent is that any offset checks should have been done by the caller.

=over

=item tiff_get16

Retrieve a 16 bit unsigned integer from offset.

=cut
*/

static unsigned
tiff_get16(imtiff *tiff, unsigned long offset) {
  if (offset + 2 > tiff->size) {
    mm_log((3, "attempt to get16 at %lu in %lu image", offset,
	    (unsigned long)tiff->size));
    return 0;
  }

  if (tiff->type == tt_intel) 
    return tiff->base[offset] + 0x100 * tiff->base[offset+1];
  else
    return tiff->base[offset+1] + 0x100 * tiff->base[offset];
}

/*
=item tiff_get32

Retrieve a 32-bit unsigned integer from offset.

=cut
*/

static unsigned
tiff_get32(imtiff *tiff, unsigned long offset) {
  if (offset + 4 > tiff->size) {
    mm_log((3, "attempt to get16 at %lu in %lu image", offset,
	    (unsigned long)tiff->size));
    return 0;
  }

  if (tiff->type == tt_intel) 
    return tiff->base[offset] + 0x100 * tiff->base[offset+1] 
      + 0x10000 * tiff->base[offset+2] + 0x1000000 * tiff->base[offset+3];
  else
    return tiff->base[offset+3] + 0x100 * tiff->base[offset+2]
      + 0x10000 * tiff->base[offset+1] + 0x1000000 * tiff->base[offset];
}

#if 0 /* currently unused, but that may change */

/*
=item tiff_get_bytes

Retrieve a byte string from offset.

This isn't used much, you can usually deal with the data in-situ.
This is intended for use when you need to modify the data in some way.

=cut
*/

static int
tiff_get_bytes(imtiff *tiff, unsigned char *data, size_t offset, 
	       size_t size) {
  if (offset + size > tiff->size)
    return 0;

  memcpy(data, tiff->base+offset, size);

  return 1;
}

#endif

/*
=item tiff_get16s

Retrieve a 16-bit signed integer from offset.

=cut
*/

static int
tiff_get16s(imtiff *tiff, unsigned long offset) {
  int result;

  if (offset + 2 > tiff->size) {
    mm_log((3, "attempt to get16 at %lu in %lu image", offset,
	    (unsigned long)tiff->size));
    return 0;
  }

  if (tiff->type == tt_intel) 
    result = tiff->base[offset] + 0x100 * tiff->base[offset+1];
  else
    result = tiff->base[offset+1] + 0x100 * tiff->base[offset];

  if (result > 0x7FFF)
    result -= 0x10000;

  return result;
}

/*
=item tiff_get32s

Retrieve a 32-bit signed integer from offset.

=cut
*/

static int
tiff_get32s(imtiff *tiff, unsigned long offset) {
  unsigned work;

  if (offset + 4 > tiff->size) {
    mm_log((3, "attempt to get16 at %lu in %lu image", offset,
	    (unsigned long)tiff->size));
    return 0;
  }

  if (tiff->type == tt_intel) 
    work = tiff->base[offset] + 0x100 * tiff->base[offset+1] 
      + 0x10000 * tiff->base[offset+2] + 0x1000000 * tiff->base[offset+3];
  else
    work = tiff->base[offset+3] + 0x100 * tiff->base[offset+2]
      + 0x10000 * tiff->base[offset+1] + 0x1000000 * tiff->base[offset];

  /* not really needed on 32-bit int machines */
  if (work > 0x7FFFFFFFUL)
    return work - 0x80000000UL;
  else
    return work;
}

/*
=item tiff_get_rat

Retrieve an unsigned rational from offset.

=cut
*/

static double
tiff_get_rat(imtiff *tiff, unsigned long offset) {
  unsigned long numer, denom;
  if (offset + 8 > tiff->size) {
    mm_log((3, "attempt to get_rat at %lu in %lu image", offset,
	    (unsigned long)tiff->size));
    return 0;
  }

  numer = tiff_get32(tiff, offset);
  denom = tiff_get32(tiff, offset+4);

  if (denom == 0) {
    return -DBL_MAX;
  }

  return (double)numer / denom;
}

/*
=item tiff_get_rats

Retrieve an signed rational from offset.

=cut
*/

static double
tiff_get_rats(imtiff *tiff, unsigned long offset) {
  long numer, denom;
  if (offset + 8 > tiff->size) {
    mm_log((3, "attempt to get_rat at %lu in %lu image", offset,
	    (unsigned long)tiff->size));
    return 0;
  }

  numer = tiff_get32s(tiff, offset);
  denom = tiff_get32s(tiff, offset+4);

  if (denom == 0) {
    return -DBL_MAX;
  }

  return (double)numer / denom;
}

/*
=back

=head1 SEE ALSO

L<Imager>, jpeg.c

http://www.exif.org/

=head1 AUTHOR

Tony Cook <tonyc@cpan.org>

=head1 REVISION

$Revision$

=cut
*/
