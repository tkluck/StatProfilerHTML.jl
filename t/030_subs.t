#!/usr/bin/env perl

use t::lib::Test;

use Devel::StatProfiler::Reader;

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }

use Devel::StatProfiler -file => $profile_file, -interval => 1000;
my ($foo, $l1, $l2, $l3);

{
    package X;

    $foo = sub {
        my $x; # some dummy statement
        main::take_sample(); BEGIN { $l1 = __LINE__ + 0 }
    };
}

sub Moo::bar {
    take_sample(); BEGIN { $l2 = __LINE__ + 0 }
}

sub foo {
    take_sample(); BEGIN { $l3 = __LINE__ + 0 }
}

foo();
Moo::bar();
$foo->();

Devel::StatProfiler::stop_profile();

my @samples = get_samples($profile_file);

eq_or_diff($samples[0][2], bless {
    line          => $l3,
    first_line    => $l3,
    file          => __FILE__,
    package       => 'main',
    sub_name      => 'foo',
    fq_sub_name   => 'main::foo',
}, 'Devel::StatProfiler::StackFrame');
eq_or_diff($samples[1][2], bless {
    line          => $l2,
    first_line    => $l2,
    file          => __FILE__,
    package       => 'Moo',
    sub_name      => 'bar',
    fq_sub_name   => 'Moo::bar',
}, 'Devel::StatProfiler::StackFrame');
eq_or_diff($samples[2][2], bless {
    line          => $l1,
    first_line    => $l1 - 1,
    file          => __FILE__,
    package       => 'X',
    sub_name      => '__ANON__',
    fq_sub_name   => 'X::__ANON__',
}, 'Devel::StatProfiler::StackFrame');

done_testing();
