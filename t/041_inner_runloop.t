#!/usr/bin/env perl

use t::lib::Test;

use Devel::StatProfiler::Reader;
use Devel::StatProfiler::Test;

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }

use Devel::StatProfiler -file => $profile_file, -interval => 1000;

my ($l1);

my ($tied, %tied);

tie $tied, 'Devel::StatProfiler::Test::TiedScalar';

my $v1 = $tied; BEGIN { $l1 = __LINE__ + 0 }

Devel::StatProfiler::stop_profile();

my @traces = get_traces($profile_file, {
    sassign => 1,
});

eq_or_diff($traces[0]->frames->[1], bless {
    file          => 't/lib/Devel/StatProfiler/Test.pm',
    first_line    => 17,
    fq_sub_name   => 'Devel::StatProfiler::Test::TiedScalar::FETCH',
    line          => 17,
    package       => 'Devel::StatProfiler::Test::TiedScalar',
    sub_name      => 'FETCH',
}, 'Devel::StatProfiler::StackFrame');
eq_or_diff($traces[0]->frames->[2], bless {
    file          => __FILE__,
    line          => $l1,
}, 'Devel::StatProfiler::MainStackFrame');

cmp_ok($traces[0]->weight, '>=', 40);
cmp_ok($traces[1]->weight, '<', 10)
    if @traces > 1;

done_testing();
