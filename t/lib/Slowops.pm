package t::lib::Slowops;

use strict;
use warnings;

sub foo {
    -d '.' for 1..$_[0];
}

1;
