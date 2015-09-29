#!/bin/sh -x

set -e
IMAGE_DIR="/home/isucon/image_source"
if ! [ -d "$IMAGE_DIR" ]; then
  mkdir "$IMAGE_DIR"
fi

pushd /tmp
wget -O archive_m1.zip http://30d.jp/img/yapcasia/6/archive_m1.zip
wget -O archive_o1.zip http://30d.jp/img/yapcasia/6/archive_o1.zip
unzip -o archive_m1.zip
mv 30days_album_yapcasia_6/photo/large/*.jpg "$IMAGE_DIR"
unzip -o archive_o1.zip
mv 30days_album_yapcasia_6/photo/original/*.jpg "$IMAGE_DIR"

wget -O iconset-addictive-flavour-set.zip http://media.smashingmagazine.com/wp-content/uploads/images/addictive-flavour-v3/iconset-addictive-flavour-set.zip
unzip -o iconset-addictive-flavour-set.zip
mv "png files"/*.png "$IMAGE_DIR"

pushd "$IMAGE_DIR"
for i in *_original.jpg;
do
  mv $i .$i
  convert -geometry 2400x2400 .$i $i
  rm -f .$i
done

popd
popd
carton install
carton exec perl make_thumbnails.pl "$IMAGE_DIR"
