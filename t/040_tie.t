#!/usr/bin/env perl

use t::lib::Test;

use Devel::StatProfiler::Reader;
use Devel::StatProfiler::Test;

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }

use Devel::StatProfiler -file => $profile_file, -interval => 1000;

my ($l1, $l2);

my ($tied, %tied);

tie $tied, 'Devel::StatProfiler::Test::TiedScalar';
tie %tied, 'Devel::StatProfiler::Test::TiedHash';

my $v1 = $tied; BEGIN { $l1 = __LINE__ + 0 }
my $v2 = $tied{50000}; BEGIN { $l2 = __LINE__ + 0 }

Devel::StatProfiler::stop_profile();

my @samples = get_samples($profile_file);

eq_or_diff($samples[0][0], bless {
    file          => '',
    first_line    => -1,
    fq_sub_name   => 'Time::HiRes::usleep',
    line          => -1,
    package       => 'Time::HiRes',
    sub_name      => 'usleep',
}, 'Devel::StatProfiler::StackFrame');
eq_or_diff($samples[0][1], bless {
    file          => 't/lib/Devel/StatProfiler/Test.pm',
    first_line    => 17,
    fq_sub_name   => 'Devel::StatProfiler::Test::TiedScalar::FETCH',
    line          => 17,
    package       => 'Devel::StatProfiler::Test::TiedScalar',
    sub_name      => 'FETCH',
}, 'Devel::StatProfiler::StackFrame');
eq_or_diff($samples[0][2], bless {
    line          => $l1,
    file          => __FILE__,
}, 'Devel::StatProfiler::MainStackFrame');

eq_or_diff($samples[1][0], bless {
    file          => '',
    first_line    => -1,
    fq_sub_name   => 'Devel::StatProfiler::Test::TiedHash::FETCH',
    line          => -1,
    package       => 'Devel::StatProfiler::Test::TiedHash',
    sub_name      => 'FETCH',
}, 'Devel::StatProfiler::StackFrame');
eq_or_diff($samples[1][1], bless {
    line          => $l2,
    file          => __FILE__,
}, 'Devel::StatProfiler::MainStackFrame');

done_testing();
