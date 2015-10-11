#!/usr/bin/env perl

use t::lib::Test;

use Devel::StatProfiler::Reader;

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }

use Devel::StatProfiler -file => $profile_file, -interval => 1000;
my ($l1, $l2, $l3, $l4, $l5, $l6, $l7);

sub foo {
    take_sample(); BEGIN { $l2 = __LINE__ + 0 }
}

sub bar {
    eval {
        foo(); BEGIN { $l4 = __LINE__ + 0 }

        take_sample(); BEGIN { $l5 = __LINE__ + 0 }

        eval {
            take_sample(); BEGIN { $l6 = __LINE__ + 0 }
        };

        1;
    } or do { BEGIN { $l3 = __LINE__ + 0 }
        print STDERR "Something went wrong\n";
    };
}

foo(); BEGIN { $l1 = __LINE__ + 0 }
bar();

eval {
    take_sample(); BEGIN { $l7 = __LINE__ + 0 }
    1;
};

Devel::StatProfiler::stop_profile();

my @samples = get_samples($profile_file);

for my $sample (@samples) {
    my $main_count = () = grep ref($_) eq 'Devel::StatProfiler::MainStackFrame', @$sample;
    my $eval_count = () = grep ref($_) eq 'Devel::StatProfiler::EvalStackFrame', @$sample;

    is($eval_count, 0, "there are no eval frames");
    is($main_count, 1, "there is a single main stack frame");
    is(ref($sample->[-1]), 'Devel::StatProfiler::MainStackFrame',
       "... and it is the bottom frame");
}

eq_or_diff($samples[0][-2], bless {
    line          => $l2,
    first_line    => $l2,
    file          => __FILE__,
    file_pretty   => __FILE__,
    package       => 'main',
    sub_name      => 'foo',
    fq_sub_name   => 'main::foo',
}, 'Devel::StatProfiler::StackFrame');
eq_or_diff($samples[0][-1], bless {
    line          => $l1,
    file          => __FILE__,
    file_pretty   => __FILE__,
}, 'Devel::StatProfiler::MainStackFrame');

eq_or_diff($samples[1][-3], bless {
    line          => $l2,
    first_line    => $l2,
    file          => __FILE__,
    file_pretty   => __FILE__,
    package       => 'main',
    sub_name      => 'foo',
    fq_sub_name   => 'main::foo',
}, 'Devel::StatProfiler::StackFrame');
eq_or_diff($samples[1][-2], bless {
    line          => $l4,
    first_line    => $l3,
    file          => __FILE__,
    file_pretty   => __FILE__,
    package       => 'main',
    sub_name      => 'bar',
    fq_sub_name   => 'main::bar',
}, 'Devel::StatProfiler::StackFrame');
eq_or_diff($samples[1][-1], bless {
    line          => $l1 + 1,
    file          => __FILE__,
    file_pretty   => __FILE__,
}, 'Devel::StatProfiler::MainStackFrame');

eq_or_diff($samples[2][-2], bless {
    line          => $l5,
    first_line    => $l3,
    file          => __FILE__,
    file_pretty   => __FILE__,
    package       => 'main',
    sub_name      => 'bar',
    fq_sub_name   => 'main::bar',
}, 'Devel::StatProfiler::StackFrame');
eq_or_diff($samples[2][-1], bless {
    line          => $l1 + 1,
    file          => __FILE__,
    file_pretty   => __FILE__,
}, 'Devel::StatProfiler::MainStackFrame');

eq_or_diff($samples[3][-2], bless {
    line          => $l6,
    first_line    => $l3,
    file          => __FILE__,
    file_pretty   => __FILE__,
    package       => 'main',
    sub_name      => 'bar',
    fq_sub_name   => 'main::bar',
}, 'Devel::StatProfiler::StackFrame');
eq_or_diff($samples[3][-1], bless {
    line          => $l1 + 1,
    file          => __FILE__,
    file_pretty   => __FILE__,
}, 'Devel::StatProfiler::MainStackFrame');

eq_or_diff($samples[4][-1], bless {
    line          => $l7,
    file          => __FILE__,
    file_pretty   => __FILE__,
}, 'Devel::StatProfiler::MainStackFrame');

#use Data::Dumper; print Dumper(\@samples);
done_testing();
