#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 5;

use_ok('Devel::StatProfiler', '-nostart');
use_ok('Devel::StatProfiler::Reader');
use_ok('Devel::StatProfiler::Report');
use_ok('Devel::StatProfiler::Aggregate');
use_ok('Devel::StatProfiler::Aggregator');
