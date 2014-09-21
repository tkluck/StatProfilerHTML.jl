#!/usr/bin/env perl

use t::lib::Test;

use Devel::StatProfiler::Reader;

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }

use Devel::StatProfiler -file => $profile_file, -interval => 1000;
my ($foo, $l1, $l2, $l3);

BEGIN {
    take_sample();
}

use Test::Begin;

Devel::StatProfiler::stop_profile();

my ($begin, $use_begin, $use_init, $use_import) = my @samples = get_samples($profile_file);

is(@$begin, 3);
is($begin->[2]->fq_sub_name, 'main::BEGIN');
is($begin->[2]->first_line, 14);

is(@$use_begin, 4);
is($use_begin->[2]->fq_sub_name, 'Test::Begin::BEGIN');
is($use_begin->[2]->file, 't/lib/Test/Begin.pm');
is($use_begin->[2]->first_line, 14);
is($use_begin->[3]->file, __FILE__);
is($use_begin->[3]->fq_sub_name, 'main::BEGIN');
is($use_begin->[3]->first_line, 17);

is(@$use_init, 4);
is($use_init->[2]->fq_sub_name, '');
is($use_init->[2]->file, 't/lib/Test/Begin.pm');
is($use_init->[3]->file, __FILE__);
is($use_init->[3]->fq_sub_name, 'main::BEGIN');
is($use_init->[3]->first_line, 17);

is(@$use_import, 4);
is($use_import->[2]->fq_sub_name, 'Test::Begin::import');
is($use_import->[2]->file, 't/lib/Test/Begin.pm');
is($use_import->[2]->first_line, 8);
is($use_import->[3]->file, __FILE__);
is($use_import->[3]->fq_sub_name, 'main::BEGIN');
is($use_import->[3]->first_line, 17);

done_testing();
