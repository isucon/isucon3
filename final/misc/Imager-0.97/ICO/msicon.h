#ifndef IMAGER_MSICON_H_
#define IMAGER_MSICON_H_

#include "iolayert.h"

typedef struct ico_reader_tag ico_reader_t;

#define ICON_ICON 1
#define ICON_CURSOR 2

typedef struct {
  unsigned char r, g, b, a;
} ico_color_t;

typedef struct {
  int width;
  int height;
  int direct;
  int bit_count;
  void *image_data;
  int palette_size;
  ico_color_t *palette;
  unsigned char *mask_data;
  int hotspot_x, hotspot_y;
} ico_image_t;

extern ico_reader_t *ico_reader_open(i_io_glue_t *ig, int *error);
extern int ico_image_count(ico_reader_t *file);
extern int ico_type(ico_reader_t *file);
extern ico_image_t *ico_image_read(ico_reader_t *file, int index, int *error);
extern void ico_image_release(ico_image_t *image);
extern void ico_reader_close(ico_reader_t *file);

extern int ico_write(i_io_glue_t *ig, ico_image_t const *images, 
		     int image_count, int type, int *error);

extern size_t ico_error_message(int error, char *buffer, size_t buffer_size);

#define ICO_MAX_MESSAGE 80

#define ICOERR_Short_File 100
#define ICOERR_File_Error 101
#define ICOERR_Write_Failure 102

#define ICOERR_Invalid_File 200
#define ICOERR_Unknown_Bits 201

#define ICOERR_Bad_Image_Index 300
#define ICOERR_Bad_File_Type 301
#define ICOERR_Invalid_Width 302
#define ICOERR_Invalid_Height 303
#define ICOERR_Invalid_Palette 304
#define ICOERR_No_Data 305

#define ICOERR_Out_Of_Memory 400

#endif
