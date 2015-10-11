#!/usr/bin/env perl

use t::lib::Test;

use Devel::StatProfiler::Reader;

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }

use Devel::StatProfiler -file => $profile_file, -interval => 1000;
my ($l1);

do 'do.pl'; BEGIN { $l1 = __LINE__ + 0 }

Devel::StatProfiler::stop_profile();

my @samples = get_samples($profile_file);

eq_or_diff($samples[0][2], bless {
    line          => 2,
    first_line    => 2,
    file          => 't/lib/do.pl',
    file_pretty   => 't/lib/do.pl',
    package       => 'main',
    sub_name      => 'moo',
    fq_sub_name   => 'main::moo',
}, 'Devel::StatProfiler::StackFrame');
eq_or_diff($samples[0][3], bless {
    line          => 5,
    file          => 't/lib/do.pl',
    file_pretty   => 't/lib/do.pl',
}, 'Devel::StatProfiler::MainStackFrame');
eq_or_diff($samples[0][4], bless {
    line          => $l1,
    file          => __FILE__,
    file_pretty   => __FILE__,
}, 'Devel::StatProfiler::MainStackFrame');

eq_or_diff($samples[1][2], bless {
    line          => 6,
    file          => 't/lib/do.pl',
    file_pretty   => 't/lib/do.pl',
}, 'Devel::StatProfiler::MainStackFrame');
eq_or_diff($samples[1][3], bless {
    line          => $l1,
    file          => __FILE__,
    file_pretty   => __FILE__,
}, 'Devel::StatProfiler::MainStackFrame');

done_testing();
