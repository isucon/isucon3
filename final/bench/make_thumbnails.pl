#!/usr/bin/env perl
use strict;
use 5.12.0;
use Image::Size;
use POSIX qw/ floor /;
use Path::Tiny;
my $dir = path( shift || "." );
chdir "$dir";
mkdir "$dir/s";
mkdir "$dir/m";
mkdir "$dir/l";

my @jpg = map { "$_" } grep { /\.jpg$/ } $dir->children;
my @png = map { "$_" } grep { /\.png$/ } $dir->children;

for my $file (@jpg) {
    say $file;
    my ($w, $h) = imgsize($file);
    my ($pixels, $crop_x, $crop_y);
    if ( $w > $h ) {
        $pixels = $h;
        $crop_x = floor(($w - $pixels) / 2);
        $crop_y = 0;
    }
    elsif ( $w < $h ) {
        $pixels = $w;
        $crop_x = 0;
        $crop_y = floor(($h - $pixels) / 2);
    }
    else {
        $pixels = $w;
        $crop_x = 0;
        $crop_y = 0;
    }
    system("convert", "-crop", "${pixels}x${pixels}+${crop_x}+${crop_y}", $file, ".$$.jpg");
    (my $s_file = $file) =~ s{/?([^/]+\.jpg)}{/s/$1};
    (my $m_file = $file) =~ s{/?([^/]+\.jpg)}{/m/$1};
    system("convert", "-geometry", "128x128", ".$$.jpg", $s_file);
    system("convert", "-geometry", "256x256", ".$$.jpg", $m_file);
    unlink ".$$.jpg";
}

for my $file (@png) {
    chomp $file;
    say $file;
    (my $s_file = $file) =~ s{/?([^/]+\.png)}{/s/$1};
    (my $m_file = $file) =~ s{/?([^/]+\.png)}{/m/$1};
    (my $l_file = $file) =~ s{/?([^/]+\.png)}{/l/$1};
    system("convert", "-geometry", "32x32",   "$file", $s_file);
    system("convert", "-geometry", "64x64",   "$file", $m_file);
    system("convert", "-geometry", "128x128", "$file", $m_file);
}
