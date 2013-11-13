#!perl -w
use strict;
use Test::More tests => 15;

use_ok('Imager');
use_ok('Imager::Font');
use_ok('Imager::Color');
use_ok('Imager::Color::Float');
use_ok('Imager::Color::Table');
use_ok('Imager::Matrix2d');
use_ok('Imager::ExtUtils');
use_ok('Imager::Expr');
use_ok('Imager::Expr::Assem');
use_ok('Imager::Font::BBox');
use_ok('Imager::Font::Wrap');
use_ok('Imager::Fountain');
use_ok('Imager::Regops');
use_ok('Imager::Test');
use_ok('Imager::Transform');
