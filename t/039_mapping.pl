#!/usr/bin/env perl

use t::lib::Test;

use Devel::StatProfiler::Reader;

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }

use Devel::StatProfiler -file => $profile_file, -interval => 1000;
my ($l1, $l2, $l3, $l4, $l5);
my ($s1, $s2, $s3, $s4);

my @odd = map {
    take_sample(), $s1++ unless $s1; BEGIN { $l1 = __LINE__ + 0 }
    take_sample(), $s1++ if $s1 == 1;
    $_ * 2 + 1
} 1 .. 10;

my @even = grep {
    take_sample(), $s2++ unless $s2; BEGIN { $l2 = __LINE__ + 0 }
    take_sample(), $s2++ if $s2 == 1;
    $_ & 1 == 0
} 1 .. 10;

my @sorted1 = sort {
    take_sample(), $s3++ unless $s3; BEGIN { $l3 = __LINE__ + 0 }
    take_sample(), $s3++ if $s3 == 1;
    $a cmp $b
} qw(e d c b a);

sub compare {
    take_sample(), $s4++ unless $s4; BEGIN { $l4 = __LINE__ + 0 }
    $a cmp $b;
}

my @sorted2 = sort compare qw(e d c b a); BEGIN { $l5 = __LINE__ + 0 }

Devel::StatProfiler::stop_profile();

my @samples = get_samples($profile_file);


eq_or_diff($samples[0][2], bless {
    line          => $l1 - 1,
    file          => __FILE__,
}, 'Devel::StatProfiler::MainStackFrame');
eq_or_diff($samples[1][2], bless {
    line          => $l1 + 1,
    file          => __FILE__,
}, 'Devel::StatProfiler::MainStackFrame');

eq_or_diff($samples[2][2], bless {
    line          => $l2 - 1,
    file          => __FILE__,
}, 'Devel::StatProfiler::MainStackFrame');
eq_or_diff($samples[3][2], bless {
    line          => $l2 + 1,
    file          => __FILE__,
}, 'Devel::StatProfiler::MainStackFrame');

eq_or_diff($samples[4][2], bless {
    line          => $l3 - 1,
    file          => __FILE__,
}, 'Devel::StatProfiler::MainStackFrame');
eq_or_diff($samples[5][2], bless {
    line          => $l3 + 1,
    file          => __FILE__,
}, 'Devel::StatProfiler::MainStackFrame');

eq_or_diff($samples[6][2], bless {
    line          => $l4,
    first_line    => $l4,
    file          => __FILE__,
    package       => 'main',
    sub_name      => 'compare',
    fq_sub_name   => 'main::compare',
}, 'Devel::StatProfiler::StackFrame');
eq_or_diff($samples[6][3], bless {
    line          => $l5,
    file          => __FILE__,
}, 'Devel::StatProfiler::MainStackFrame');

done_testing();
