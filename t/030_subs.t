#!/usr/bin/env perl

use t::lib::Test;

use Devel::StatProfiler::Reader;

use Devel::StatProfiler -file => 'tprof.out', -interval => 1000;
my ($foo, $l1, $l2, $l3);

{
    package X;

    $foo = sub {
        main::take_sample(); BEGIN { $l1 = __LINE__ }
    };
}

sub Moo::bar {
    take_sample(); BEGIN { $l2 = __LINE__ }
}

sub foo {
    take_sample(); BEGIN { $l3 = __LINE__ }
}

foo();
Moo::bar();
$foo->();

Devel::StatProfiler::stop_profile();

my @samples = get_samples('tprof.out');

eq_or_diff($samples[0][1], bless {
    line       => $l3,
    file       => __FILE__,
    subroutine => 'main::foo',
}, 'Devel::StatProfiler::StackFrame');
eq_or_diff($samples[1][1], bless {
    line       => $l2,
    file       => __FILE__,
    subroutine => 'Moo::bar',
}, 'Devel::StatProfiler::StackFrame');
eq_or_diff($samples[2][1], bless {
    line       => $l1,
    file       => __FILE__,
    subroutine => 'X::__ANON__',
}, 'Devel::StatProfiler::StackFrame');

done_testing();
