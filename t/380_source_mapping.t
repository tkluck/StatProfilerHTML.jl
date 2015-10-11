#!/usr/bin/env perl

use t::lib::Test;

use Devel::StatProfiler::Aggregator;
use Devel::StatProfiler::NameMap;
use Time::HiRes qw(usleep);

my ($profile_dir, $template);
BEGIN { ($profile_dir, $template) = temp_profile_dir(); }

use Devel::StatProfiler -template => $template, -interval => 1000, -source => 'all_evals';

use Test::LineMap;

eval <<'EOT'; # not mapped
usleep(50000);
EOT

eval <<'EOT';
#line 10 first-eval
usleep(50000);
EOT

eval <<'EOT';
usleep(50000);
#line 20 second-eval
usleep(50000);
EOT

Devel::StatProfiler::stop_profile();

my ($profile_file) = glob "$template.*";

my $r1 = Devel::StatProfiler::Report->new(sources => 1);
$r1->add_trace_file($profile_file);
$r1->_fetch_source('t/lib/Test.pm'); # does not contain #line directives
$r1->_fetch_source('t/lib/Test/LineMap.pm');

my $r2 = Devel::StatProfiler::Report->new(sources => 1);
$r2->add_trace_file($profile_file);

my $a1 = Devel::StatProfiler::Aggregator->new(
    root_directory  => File::Spec::Functions::catdir($profile_dir, 'aggr1'),
    parts_directory => File::Spec::Functions::catdir($profile_dir, 'aggr1p'),
    shard           => 'shard1',
);
$a1->process_trace_files($profile_file);
$a1->save_part;
my $r3 = $a1->merge_report('__main__');

my $a2 = Devel::StatProfiler::Aggregator->new(
    root_directory  => File::Spec::Functions::catdir($profile_dir, 'aggr1'),
    parts_directory => File::Spec::Functions::catdir($profile_dir, 'aggr1p'),
    shard           => 'shard1',
);
$a2->merge_metadata;
my $r4 = $a2->merge_report('__main__');

my $a3 = Devel::StatProfiler::Aggregate->new(
    mapper        => Devel::StatProfiler::NameMap->new(
        source => Devel::StatProfiler::EvalSource->new,
    ),
    root_directory  => File::Spec::Functions::catdir($profile_dir, 'aggr1'),
    shards          => ['shard1'],
);
my $r5 = $a3->merged_report('__main__');

my %eval_map = (
    'eval:6b3cd1d74ca85645e1b7441e303697abb2167799' => [
        [1, 'eval:6b3cd1d74ca85645e1b7441e303697abb2167799', 1],
        [3, 'second-eval', 20],
        [4, undef, 4],
    ],
    'eval:6ff7e35277e7400744f567ed096bec957a590b44' => [
        [2, 'first-eval', 10],
        [3, undef, 3],
    ],
);

my %full_map = (
    %eval_map,
    't/lib/Test/LineMap.pm' => [
        [1, 't/lib/Test/LineMap.pm', 1],
        [9, 'one-file.pm', 40],
        [13, 'other-file.pm', 30],
        [17, 'one-file.pm', 20],
        [21, 'other-file.pm', 40],
        [23, undef, 23],
    ]
);

eq_or_diff($r1->{sourcemap}{map}, \%full_map);
eq_or_diff($r2->{sourcemap}{map}, \%eval_map);
eq_or_diff($r3->{sourcemap}{map}, \%eval_map);
eq_or_diff($r4->{sourcemap}{map}, \%eval_map);
eq_or_diff($r5->{sourcemap}{map}, \%eval_map);

done_testing();
