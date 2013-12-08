package t::lib::Test;

use strict;
use warnings;
use parent 'Test::Builder::Module';

use Test::More;

require feature;

our @EXPORT = (
  @Test::More::EXPORT,
);

sub import {
    unshift @INC, 't/lib';

    strict->import;
    warnings->import;
    feature->import(':5.12');

    goto &Test::Builder::Module::import;
}

1;
