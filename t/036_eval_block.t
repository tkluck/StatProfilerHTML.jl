#!/usr/bin/env perl

use t::lib::Test;

use Devel::StatProfiler::Reader;

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }

use Devel::StatProfiler -file => $profile_file, -interval => 1000;
my ($l1, $l2);

sub foo {
    take_sample(); BEGIN { $l2 = __LINE__ + 0 }
}

sub bar {
    eval {
        foo();

        take_sample();

        1;
    } or do {
        print STDERR "Something went wrong\n";
    };
}

foo(); BEGIN { $l1 = __LINE__ + 0 }
bar();

eval {
    take_sample();
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

done_testing();
