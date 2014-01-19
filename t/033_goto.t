#!/usr/bin/env perl

use t::lib::Test;

use Devel::StatProfiler::Reader;

use Devel::StatProfiler -file => 'tprof.out', -interval => 1000;
my ($l1, $l2, $l3, $l4);

sub foo {
    goto &take_sample;
}

sub bar {
    foo(); BEGIN { $l4 = __LINE__ + 0 }
}

sub baz {
    goto &foo;
}

foo(); BEGIN { $l1 = __LINE__ + 0 }
bar(); BEGIN { $l2 = __LINE__ + 0 }
baz(); BEGIN { $l3 = __LINE__ + 0 }

Devel::StatProfiler::stop_profile();

my @samples = get_samples('tprof.out');

eq_or_diff($samples[0][2], bless {
    line          => $l1,
    file          => __FILE__,
    package       => '',
    sub_name      => '',
    fq_sub_name   => '',
}, 'Devel::StatProfiler::StackFrame');
eq_or_diff($samples[1][2], bless {
    line          => $l4,
    file          => __FILE__,
    package       => 'main',
    sub_name      => 'bar',
    fq_sub_name   => 'main::bar',
}, 'Devel::StatProfiler::StackFrame');
eq_or_diff($samples[1][3], bless {
    line          => $l2,
    file          => __FILE__,
    package       => '',
    sub_name      => '',
    fq_sub_name   => '',
}, 'Devel::StatProfiler::StackFrame');
eq_or_diff($samples[2][2], bless {
    line          => $l3,
    file          => __FILE__,
    package       => '',
    sub_name      => '',
    fq_sub_name   => '',
}, 'Devel::StatProfiler::StackFrame');

done_testing();
