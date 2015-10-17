#!/usr/bin/env perl

use t::lib::Test;

use Devel::StatProfiler::Reader;

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }

use Devel::StatProfiler -file => $profile_file, -interval => 1000;
my ($l1, $l2, $l3);
(eval 'eval { (caller 0)[1] }') =~ /\(eval (\d+)\)/ or die "WTF";
my $index = $1;

sub foo {
    BEGIN { $l2 = __LINE__ + 0 } # Can't be moved on the next line (5.14 bug)
    eval <<'EOT';
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

eval "BEGIN { take_sample() }"; BEGIN { $l3 = __LINE__ + 0 }

Devel::StatProfiler::stop_profile();

my @samples = get_samples($profile_file);
my $process_id = get_process_id($profile_file);

eq_or_diff($samples[0][2], bless {
    line          => 1,
    file          => "qeval:$process_id/(eval ${\($index + 1)})",
}, 'Devel::StatProfiler::EvalStackFrame');
eq_or_diff($samples[0][3], bless {
    line          => $l2 + 1,
    first_line    => $l2 + 1,
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
    first_line    => 2,
    file          => "qeval:$process_id/(eval ${\($index + 2)})",
    package       => 'main',
    sub_name      => 'moo',
    fq_sub_name   => 'main::moo',
}, 'Devel::StatProfiler::StackFrame');
eq_or_diff($samples[1][3], bless {
    line          => 5,
    file          => "qeval:$process_id/(eval ${\($index + 2)})",
}, 'Devel::StatProfiler::EvalStackFrame');
eq_or_diff($samples[2][2], bless {
    line          => 1,
    file          => "qeval:$process_id/(eval ${\($index + 3)})",
}, 'Devel::StatProfiler::EvalStackFrame');
eq_or_diff($samples[3][2], bless {
    line          => 1,
    first_line    => 1,
    file          => "qeval:$process_id/(eval ${\($index + 4)})",
    package       => 'main',
    sub_name      => 'BEGIN',
    fq_sub_name   => 'main::BEGIN',
}, 'Devel::StatProfiler::StackFrame');
eq_or_diff($samples[3][3], bless {
    line          => $l3,
    file          => __FILE__,
}, 'Devel::StatProfiler::MainStackFrame');

done_testing();
