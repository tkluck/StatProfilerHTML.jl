#!/usr/bin/env perl

use if $] < 5.018, 'Test::More' => skip_all => 'lexical subs not available';

use t::lib::Test;

no warnings "experimental::lexical_subs";
use feature 'lexical_subs';

use Devel::StatProfiler::Reader;

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }

use Devel::StatProfiler -file => $profile_file, -interval => 1000;
my ($l1, $l2, $l3, $l4, $l5);

our sub baz {
    take_sample(); BEGIN { $l1 = __LINE__ + 0 }
}

{
    package X;

    baz();
}

sub bar {
    foo(); BEGIN { $l4 = __LINE__ + 0 }

    my sub foo {
        take_sample(); BEGIN { $l2 = __LINE__ + 0 }
    }

    foo(); BEGIN { $l5 = __LINE__ + 0 }
}

sub foo {
    take_sample(); BEGIN { $l3 = __LINE__ + 0 }
}

foo();
bar();
baz();

Devel::StatProfiler::stop_profile();

my @samples = get_samples($profile_file);

eq_or_diff($samples[0][2], bless {
    line          => $l1,
    first_line    => $l1,
    file          => __FILE__,
    file_pretty   => __FILE__,
    package       => 'main',
    sub_name      => 'baz',
    fq_sub_name   => 'main::baz',
}, 'Devel::StatProfiler::StackFrame');

eq_or_diff($samples[1][2], bless {
    line          => $l3,
    first_line    => $l3,
    file          => __FILE__,
    file_pretty   => __FILE__,
    package       => 'main',
    sub_name      => 'foo',
    fq_sub_name   => 'main::foo',
}, 'Devel::StatProfiler::StackFrame');

eq_or_diff($samples[2][2], bless {
    line          => $l3,
    first_line    => $l3,
    file          => __FILE__,
    file_pretty   => __FILE__,
    package       => 'main',
    sub_name      => 'foo',
    fq_sub_name   => 'main::foo',
}, 'Devel::StatProfiler::StackFrame');
eq_or_diff($samples[2][3], bless {
    line          => $l4,
    first_line    => $l4,
    file          => __FILE__,
    file_pretty   => __FILE__,
    package       => 'main',
    sub_name      => 'bar',
    fq_sub_name   => 'main::bar',
}, 'Devel::StatProfiler::StackFrame');

eq_or_diff($samples[3][2], bless {
    line          => $l2,
    first_line    => $l2,
    file          => __FILE__,
    file_pretty   => __FILE__,
    package       => $] >= 5.021004 ? 'main' : '__ANON__',
    sub_name      => $] >= 5.021004 ? 'foo' : '(unknown)',
    fq_sub_name   => $] >= 5.021004 ? 'main::foo' :'__ANON__::(unknown)',
}, 'Devel::StatProfiler::StackFrame');
eq_or_diff($samples[3][3], bless {
    line          => $l5,
    first_line    => $l4,
    file          => __FILE__,
    file_pretty   => __FILE__,
    package       => 'main',
    sub_name      => 'bar',
    fq_sub_name   => 'main::bar',
}, 'Devel::StatProfiler::StackFrame');

eq_or_diff($samples[4][2], bless {
    line          => $l1,
    first_line    => $l1,
    file          => __FILE__,
    file_pretty   => __FILE__,
    package       => 'main',
    sub_name      => 'baz',
    fq_sub_name   => 'main::baz',
}, 'Devel::StatProfiler::StackFrame');

done_testing();
