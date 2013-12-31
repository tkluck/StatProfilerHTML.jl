#!/usr/bin/env perl

use t::lib::Test;

use Devel::StatProfiler::Reader;

use Devel::StatProfiler -file => 'tprof.out', -interval => 1000;
use List::Util qw(first);

my ($l1, $l2, $l3, $l4);

sub odd {
    take_sample(); BEGIN { $l1 = __LINE__ + 0 }
    return $_ & 1;
}

my $three = first \&odd, qw(2 4 6 8 10 12 14 16 3); BEGIN { $l4 = __LINE__ + 0 }
my $five = first {
    take_sample(); BEGIN { $l2 = __LINE__ + 0 }
    return $_ & 1;
} qw(2 4 6 5); BEGIN { $l3 = __LINE__ + 0 }

Devel::StatProfiler::stop_profile();

my @samples = get_samples('tprof.out');

my ($sub) = grep $_->[2]->line == $l1, @samples;
my ($block) = grep $_->[2]->line == $l2, @samples;

eq_or_diff($sub->[2], bless {
    file       => __FILE__,
    line       => $l1,
    subroutine => 'main::odd',
}, 'Devel::StatProfiler::StackFrame');
eq_or_diff($sub->[3], bless {
    file       => __FILE__,
    line       => $l4,
    subroutine => '',
}, 'Devel::StatProfiler::StackFrame');

eq_or_diff($block->[2], bless {
    file       => __FILE__,
    line       => $l2,
    subroutine => 'main::__ANON__',
}, 'Devel::StatProfiler::StackFrame');
eq_or_diff($block->[3], bless {
    file       => __FILE__,
    line       => $l3,
    subroutine => '',
}, 'Devel::StatProfiler::StackFrame');

done_testing();
