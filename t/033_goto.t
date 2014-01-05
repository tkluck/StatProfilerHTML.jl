#!/usr/bin/env perl

use t::lib::Test;

use Devel::StatProfiler::Reader;

use Devel::StatProfiler -file => 'tprof.out', -interval => 1000;
my ($l1, $l2, $l3, $l4);

sub foo {
    goto &take_sample;
}

sub bar {
    foo(); BEGIN { $l4 = __LINE__ }
}

sub baz {
    goto &foo;
}

foo(); BEGIN { $l1 = __LINE__ }
bar(); BEGIN { $l2 = __LINE__ }
baz(); BEGIN { $l3 = __LINE__ }

Devel::StatProfiler::stop_profile();

my @samples = get_samples('tprof.out');

eq_or_diff($samples[0][1], bless {
    line       => $l1,
    file       => __FILE__,
    subroutine => '',
}, 'Devel::StatProfiler::StackFrame');
eq_or_diff($samples[1][1], bless {
    line       => $l4,
    file       => __FILE__,
    subroutine => 'main::bar',
}, 'Devel::StatProfiler::StackFrame');
eq_or_diff($samples[1][2], bless {
    line       => $l2,
    file       => __FILE__,
    subroutine => '',
}, 'Devel::StatProfiler::StackFrame');
eq_or_diff($samples[2][1], bless {
    line       => $l3,
    file       => __FILE__,
    subroutine => '',
}, 'Devel::StatProfiler::StackFrame');

done_testing();
