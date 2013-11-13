#!/bin/sh -x

set -e
IMAGE_DIR="/home/isucon/image_source"

mysql -e "DELETE FROM user WHERE User=''; DROP DATABASE IF EXISTS isucon; CREATE DATABASE isucon DEFAULT CHARACTER SET utf8; GRANT ALL ON isucon.* to 'isucon'@'%'; FLUSH PRIVILEGES;" -u root mysql
mysql -uisucon isucon < ../webapp/config/schema.sql

pushd ../webapp/data
find . -name "*.jpg" -delete
find . -name "*.png" -delete
git checkout .  # restore default.png
popd

pushd ../webapp/perl
carton install
carton exec perl ../../bench/bulkloader.pl "$IMAGE_DIR"
