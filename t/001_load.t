#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 2;

use_ok('Devel::StatProfiler', '-nostart');
use_ok('Devel::StatProfiler::Reader');
