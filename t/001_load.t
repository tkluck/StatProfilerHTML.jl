#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 3;

use_ok('Devel::StatProfiler', '-nostart');
use_ok('Devel::StatProfiler::Reader');
use_ok('Devel::StatProfiler::Report');
