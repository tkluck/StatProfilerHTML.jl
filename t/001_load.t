#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 4;

use_ok('Devel::StatProfiler', '-nostart');
use_ok('Devel::StatProfiler::Reader');
use_ok('Devel::StatProfiler::Report');
use_ok('Devel::StatProfiler::Aggregator');
