#!/usr/bin/env perl

use t::lib::Test;

use Devel::StatProfiler::Reader;

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }

use Devel::StatProfiler -file => $profile_file, -interval => 1000;
my ($l1, $l2);
(eval 'eval { (caller 0)[1] }') =~ /\(eval (\d+)\)/ or die "WTF";
my $index = $1;

sub foo {
    eval <<'EOT'; BEGIN { $l2 = __LINE__ + 0 }
take_sample();
EOT
}

sub bar {
    eval <<'EOT';
sub moo {
    take_sample()
}

moo()
EOT
}

foo(); BEGIN { $l1 = __LINE__ + 0 }
bar();
eval "take_sample()";

Devel::StatProfiler::stop_profile();

my @samples = get_samples($profile_file);

eq_or_diff($samples[0][2], bless {
    line          => 1,
    file          => "(eval ${\($index + 1)})",
}, 'Devel::StatProfiler::EvalStackFrame');
eq_or_diff($samples[0][3], bless {
    line          => $l2,
    file          => __FILE__,
    package       => 'main',
    sub_name      => 'foo',
    fq_sub_name   => 'main::foo',
}, 'Devel::StatProfiler::StackFrame');
eq_or_diff($samples[0][4], bless {
    line          => $l1,
    file          => __FILE__,
}, 'Devel::StatProfiler::MainStackFrame');
eq_or_diff($samples[1][2], bless {
    line          => 2,
    file          => "(eval ${\($index + 2)})",
    package       => 'main',
    sub_name      => 'moo',
    fq_sub_name   => 'main::moo',
}, 'Devel::StatProfiler::StackFrame');
eq_or_diff($samples[1][3], bless {
    line          => 5,
    file          => "(eval ${\($index + 2)})",
}, 'Devel::StatProfiler::EvalStackFrame');
eq_or_diff($samples[2][2], bless {
    line          => 1,
    file          => "(eval ${\($index + 3)})",
}, 'Devel::StatProfiler::EvalStackFrame');

done_testing();
