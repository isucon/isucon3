package GoodTestFont;
use strict;
use vars '@ISA';

# this doesn't do enough to be a font

sub new {
  my ($class, %opts) = @_;

  return bless \%opts, $class; # as long as it's true
}

1;
