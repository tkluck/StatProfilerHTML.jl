#!/usr/bin/env perl

use t::lib::Test;
use t::lib::Slowops;

use Devel::StatProfiler::Aggregator;
use Time::HiRes qw(time);

my ($profile_dir, $template);
BEGIN { ($profile_dir, $template) = temp_profile_dir(); }

use Devel::StatProfiler -template => $template, -interval => 1000;

for (my $count = 1000; ; $count *= 2) {
    my $start = time;
    note("Trying with $count iterations");
    t::lib::Slowops::foo($count);
    -d '.' for 1..$count;
    last if time - $start >= 0.5;
}

Devel::StatProfiler::stop_profile();

my @files = glob "$template.*";
my ($process_id, $samples);

my $r1 = Devel::StatProfiler::Report->new(
    slowops => [qw(ftdir unstack)],
);
$r1->add_trace_file($_) for @files;

my $a1 = Devel::StatProfiler::Aggregator->new(
    root_directory  => File::Spec::Functions::catdir($profile_dir, 'aggr1'),
    shard           => 'shard1',
    slowops         => [qw(ftdir unstack)],
);
for my $file (@files) {
    my $r = Devel::StatProfiler::Reader->new($file);
    ($process_id) = @{$r->get_genealogy_info};
    for (;;) {
        my $sr = t::lib::Test::SingleReader->new($r);
        $a1->process_trace_files($sr);
        ++$samples;
        last if $sr->done;
    }
}
$a1->save_part;
my $r2 = $a1->merge_report('__main__');

my $a2 = Devel::StatProfiler::Aggregator->new(
    root_directory  => File::Spec::Functions::catdir($profile_dir, 'aggr2'),
    shard           => 'shard1',
    slowops         => [qw(ftdir unstack)],
    timebox         => 1,
);
my $sample_split = int($samples / 2);
my $sample_count;
for my $file (@files) {
    my $r = Devel::StatProfiler::Reader->new($file);
    for (;;) {
        my $sr = t::lib::Test::SingleReader->new($r);
        $a2->process_trace_files($sr);
        if ($sample_count++ == $sample_split) {
            $a2->save_part;
            $a2->merge_report('__main__');
            sleep 2; # different box
            $a2 = Devel::StatProfiler::Aggregator->new(
                root_directory  => File::Spec::Functions::catdir($profile_dir, 'aggr2'),
                shard           => 'shard1',
                slowops         => [qw(ftdir unstack)],
                timebox         => 1,
            );
        }
        last if $sr->done;
    }
}
$a2->save_part;
$a2->merge_report('__main__');

my $a3 = Devel::StatProfiler::Aggregate->new(
    root_directory  => File::Spec::Functions::catdir($profile_dir, 'aggr2'),
    shard           => 'shard1',
);
#$a3->merge_metadata;
my $r3 = $a3->merged_report('__main__');

my $a4 = Devel::StatProfiler::Aggregate->new(
    root_directory  => File::Spec::Functions::catdir($profile_dir, 'aggr2'),
    shard           => 'shard1',
    timebox         => 1,
);
# only to check that the in-place rewrite logic works
$a4->discard_expired_process_data(time + 3600);
my $r4 = $a4->merged_report('__main__');

# we fake the ordinals in t::lib::Test::SingleReader
$_->{genealogy}{$process_id} = { 1 => $_->{genealogy}{$process_id}{1} }
    for $r1, $r2, $r3, $r4;

# Storable and number stringification
numify($_) for $r2, $r3, $r4;

# we test source code in another test
delete @{$_}{qw(source sourcemap process_id genealogy root_dir parts_dir shard suffix slowops)}, delete @{$_->{metadata}}{qw(shard root_dir)}
    for $r1, $r2, $r3, $r4;

eq_or_diff($r2, $r1);
eq_or_diff($r3, $r1);
eq_or_diff($r4, $r1);
done_testing();
