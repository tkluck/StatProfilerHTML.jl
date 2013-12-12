package Test::Begin;

use strict;
use warnings;
use t::lib::Test;

sub import {
    take_sample();
}

take_sample();

BEGIN {
    take_sample();
}

1;
