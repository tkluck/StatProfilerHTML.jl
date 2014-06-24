#!/usr/bin/env perl

use t::lib::Test;
use t::lib::Slowops;

use Devel::StatProfiler::Aggregator;
use Time::HiRes qw(time);

my ($profile_dir, $template);
BEGIN { ($profile_dir, $template) = temp_profile_dir(); }

use Devel::StatProfiler -template => $template, -interval => 1000;

for (my $count = 10000; ; $count *= 2) {
    my $start = time;
    note("Trying with $count iterations");
    t::lib::Slowops::foo($count);
    -d '.' for 1..$count;
    last if time - $start >= 0.5;
}

Devel::StatProfiler::stop_profile();

my @files = glob "$template.*";
my $process_id;

my $r1 = Devel::StatProfiler::Report->new(
    slowops => [qw(ftdir unstack)],
);
$r1->add_trace_file($_) for @files;
# no need to finalize the report for comparison

my $a1 = Devel::StatProfiler::Aggregator->new(
    root_directory => File::Spec::Functions::catdir($profile_dir, 'aggr1'),
    slowops => [qw(ftdir unstack)],
);
for my $file (@files) {
    my $r = Devel::StatProfiler::Reader->new($file);
    ($process_id) = @{$r->get_genealogy_info};
    for (;;) {
        my $sr = t::lib::Test::SingleReader->new($r);
        $a1->process_trace_files($sr);
        last if $sr->done;
    }
}
$a1->save;
my $r2 = $a1->merged_report('__main__');
# no need to finalize the report for comparison

for my $file (@files) {
    my $r = Devel::StatProfiler::Reader->new($file);
    for (;;) {
        my $sr = t::lib::Test::SingleReader->new($r);
        my $a = Devel::StatProfiler::Aggregator->new(
            root_directory => File::Spec::Functions::catdir($profile_dir, 'aggr2'),
            slowops => [qw(ftdir unstack)],
        );
        $a->process_trace_files($sr);
        $a->save;
        last if $sr->done;
    }
}
my $a2 = Devel::StatProfiler::Aggregator->new(
    root_directory => File::Spec::Functions::catdir($profile_dir, 'aggr2'),
    slowops => [qw(ftdir unstack)],
);
my $r3 = $a2->merged_report('__main__');
# no need to finalize the report for comparison

# we fake the ordinals in t::lib::Test::SingleReader
$_->{genealogy}{$process_id} = { 1 => $_->{genealogy}{$process_id}{1} }
    for $r1, $r2, $r3;

# we test source code in another test
delete $_->{source} for $r1, $r2, $r3;
delete $_->{process_id} for $r1, $r2, $r3;

eq_or_diff($r2, $r1);
eq_or_diff($r3, $r1);
done_testing();
