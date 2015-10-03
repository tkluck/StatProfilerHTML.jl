#!/usr/bin/env perl

use t::lib::Test ':spawn';
use t::lib::Slowops;

use Devel::StatProfiler::Aggregator;
use Time::HiRes qw(time);

my ($profile_dir, $template);
BEGIN { ($profile_dir, $template) = temp_profile_dir(); }

use Devel::StatProfiler -template => $template, -interval => 1000, -source => 'all_evals';

take_sample();

spawn(sub {
    take_sample();

    spawn(sub {
        take_sample();
    })->join;

    take_sample();
})->join;

spawn(sub {
    take_sample();
})->join;

spawn(sub {
    take_sample();
})->join;

Devel::StatProfiler::stop_profile();

my @files = glob "$template.*";
my ($root, $tree) = get_process_tree(@files);

is(scalar @files, 9);

my $a1s1 = Devel::StatProfiler::Aggregator->new(
    root_directory  => File::Spec::Functions::catdir($profile_dir, 'aggr1'),
    parts_directory => File::Spec::Functions::catdir($profile_dir, 'aggr1p'),
    shard           => 'shard1',
);
my $a1s2 = Devel::StatProfiler::Aggregator->new(
    root_directory  => File::Spec::Functions::catdir($profile_dir, 'aggr1'),
    parts_directory => File::Spec::Functions::catdir($profile_dir, 'aggr1p'),
    shard           => 'shard2',
);

my (%processed, @remaining);

{
    my ($first_root) = grep /\.$root\./, @files;

    $processed{$first_root} = undef;
    @remaining = grep !exists $processed{$_}, @files;

    $a1s1->process_trace_files($first_root);
    $a1s1->save_part;
}

{
    my $a1s1_can = grep $a1s1->can_process_trace_file($_), @remaining;
    my $a1s2_can = grep $a1s2->can_process_trace_file($_), @remaining;

    is($a1s1_can, 2, 'next from root process, first child');
    is($a1s2_can, 0, 'nothing to process until merge');
}

$a1s1->merge_metadata;
delete $_->{merged_metadata} for $a1s1, $a1s2;

{
    my $a1s1_can = grep $a1s1->can_process_trace_file($_), @remaining;
    my $a1s2_can = grep $a1s2->can_process_trace_file($_), @remaining;

    is($a1s1_can, 2, 'next from root process, first child');
    is($a1s2_can, 1, 'can process first child');
}

done_testing();
