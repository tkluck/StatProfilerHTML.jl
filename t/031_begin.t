#!/usr/bin/env perl

use t::lib::Test;

use Devel::StatProfiler::Reader;

use Devel::StatProfiler -file => 'tprof.out', -interval => 1000;
my ($foo, $l1, $l2, $l3);

BEGIN {
    take_sample();
}

use Test::Begin;

Devel::StatProfiler::stop_profile();

my ($begin, $use_begin, $use_init, $use_import) = my @samples = get_samples('tprof.out');

is(@$begin, 3);
is($begin->[2]->subroutine, 'main::BEGIN');

is(@$use_begin, 4);
is($use_begin->[2]->subroutine, 'Test::Begin::BEGIN');
is($use_begin->[2]->file, 't/lib/Test/Begin.pm');
is($use_begin->[3]->file, 't/031_begin.t');
is($use_begin->[3]->subroutine, 'main::BEGIN');

is(@$use_init, 4);
is($use_init->[2]->subroutine, '');
is($use_init->[2]->file, 't/lib/Test/Begin.pm');
is($use_begin->[3]->file, 't/031_begin.t');
is($use_init->[3]->subroutine, 'main::BEGIN');

is(@$use_import, 4);
is($use_import->[2]->subroutine, 'Test::Begin::import');
is($use_import->[2]->file, 't/lib/Test/Begin.pm');
is($use_begin->[3]->file, 't/031_begin.t');
is($use_import->[3]->subroutine, 'main::BEGIN');

done_testing();
