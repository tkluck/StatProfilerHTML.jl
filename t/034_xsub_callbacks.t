#!/usr/bin/env perl

use t::lib::Test;

use Devel::StatProfiler::Reader;

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }

use Devel::StatProfiler -file => $profile_file, -interval => 1000;
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

my @samples = get_samples($profile_file);

my ($sub) = grep $_->[2]->line == $l1, @samples;
my ($block) = grep $_->[2]->line == $l2, @samples;

eq_or_diff($sub->[2], bless {
    file          => __FILE__,
    line          => $l1,
    package       => 'main',
    sub_name      => 'odd',
    fq_sub_name   => 'main::odd',
}, 'Devel::StatProfiler::StackFrame');
eq_or_diff($sub->[3], bless {
    file          => __FILE__,
    line          => $l4,
}, 'Devel::StatProfiler::MainStackFrame');

eq_or_diff($block->[2], bless {
    file          => __FILE__,
    line          => $l2,
    package       => 'main',
    sub_name      => '__ANON__',
    fq_sub_name   => 'main::__ANON__',
}, 'Devel::StatProfiler::StackFrame');
eq_or_diff($block->[3], bless {
    file          => __FILE__,
    line          => $l3,
}, 'Devel::StatProfiler::MainStackFrame');

done_testing();
