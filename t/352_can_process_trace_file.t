#!/usr/bin/env perl

use t::lib::Test;
use t::lib::Slowops;

use Devel::StatProfiler::Aggregator;
use Time::HiRes qw(time);

my ($profile_dir, $template);
BEGIN { ($profile_dir, $template) = temp_profile_dir(); }

use Devel::StatProfiler -template => $template, -interval => 1000, -maxsize => 300;

for (my $count = 1000; ; $count *= 2) {
    my $start = time;
    note("Trying with $count iterations");
    t::lib::Slowops::foo($count);
    -d '.' for 1..$count;
    last if time - $start >= 0.5;
}

Devel::StatProfiler::stop_profile();

my @files = glob "$template.*";
my $process_id;

my $a1 = Devel::StatProfiler::Aggregator->new(
    root_directory  => File::Spec::Functions::catdir($profile_dir, 'aggr1'),
    parts_directory => File::Spec::Functions::catdir($profile_dir, 'aggr1p'),
    shard           => 'shard1',
    slowops         => [qw(ftdir unstack)],
);
for my $file (@files) {
    die "can_process_trace_file() incorrectly returned false"
        unless $a1->can_process_trace_file($file);
    $a1->process_trace_files($file);
    die "can_process_trace_file() incorrectly returned true"
        if $a1->can_process_trace_file($file);
}
$a1->save_part;
my $r1 = $a1->merge_report('__main__');

my $a2 = Devel::StatProfiler::Aggregator->new(
    root_directory  => File::Spec::Functions::catdir($profile_dir, 'aggr2'),
    parts_directory => File::Spec::Functions::catdir($profile_dir, 'aggr2p'),
    shard           => 'shard1',
    slowops         => [qw(ftdir unstack)],
);
for my $file (@files) {
    die "can_process_trace_file() incorrectly returned false"
        unless $a2->can_process_trace_file($file);
    $a2->process_trace_files($file);
    die "can_process_trace_file() incorrectly returned true"
        if $a2->can_process_trace_file($file);
}
# files are not reprocessed (wrong ordinal)
for my $file (@files) {
    die "can_process_trace_file() incorrectly returned true"
        if $a2->can_process_trace_file($file);
    $a2->process_trace_files($file);
    die "can_process_trace_file() incorrectly returned true"
        if $a2->can_process_trace_file($file);
}
$a2->save_part;
my $r2 = $a2->merge_report('__main__');

eq_or_diff($r1->{aggregate}, $r2->{aggregate});

ok(!$a1->can_process_trace_file("$template.__not_existing__"),
   "can_process_trace_file() is false for non-existing files");
ok(1, 'can_process_trace_file() did not die');

done_testing();
