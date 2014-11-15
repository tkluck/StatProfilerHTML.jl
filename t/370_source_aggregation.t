#!/usr/bin/env perl

use t::lib::Test ':spawn';
use t::lib::Slowops;

use Devel::StatProfiler::Aggregator;
use Time::HiRes qw(time);

my ($profile_dir, $template);
BEGIN { ($profile_dir, $template) = temp_profile_dir(); }

use Devel::StatProfiler -template => $template, -interval => 1000, -source => 'all_evals';

eval "1 # in parent process"; # N

spawn(sub {
    eval "1 # in child before spawn"; # N + 1

    spawn(sub {
        eval "1 # in grandchild"; # N + 2
    })->join;

    eval "";
    eval "1 # in child, after spawn"; # N + 3
})->join;

eval ""; eval "";
eval "1 # in parent, after spawn"; # N + 4

Devel::StatProfiler::stop_profile();

my @files = glob "$template.*";

my $r1 = Devel::StatProfiler::Report->new(
    sources       => 1,
    mixed_process => 1,
);
$r1->add_trace_file($_) for @files;
# no need to finalize the report for comparison

my $a1 = Devel::StatProfiler::Aggregator->new(
    root_directory => File::Spec::Functions::catdir($profile_dir, 'aggr1'),
    shard          => 'shard1',
    mixed_process  => 1,
);
$a1->process_trace_files(@files);
$a1->save_part;
my $r2 = $a1->merge_report('__main__');
# no need to finalize the report for comparison

my $a2 = Devel::StatProfiler::Aggregator->new(
    root_directory => File::Spec::Functions::catdir($profile_dir, 'aggr1'),
    shard          => 'shard1',
);
my $r3 = $a2->merge_report('__main__');
# no need to finalize the report for comparison

my ($parent_id) = grep $r1->{genealogy}{$_}{1}[0] eq "00" x 24,
                       keys %{$r1->{genealogy}};
my ($child_id) = grep $r1->{genealogy}{$_}{1}[0] eq $parent_id,
                      keys %{$r1->{genealogy}};
my ($grandchild_id) = grep $r1->{genealogy}{$_}{1}[0] eq $child_id,
                           keys %{$r1->{genealogy}};

my $rs1 = $r1->{source};
my $rs2 = $r2->{source};
my $rs3 = $r3->{source};

my ($first_eval_name) = keys %{$rs1->{all}{$parent_id}{1}};
my ($first_eval_n) = $first_eval_name =~ /^\(eval (\d+)\)$/;

my @hashes = keys %{$rs1->{hashed}};

is(scalar @hashes, 6);

eq_or_diff($rs2->{seen_in_process}, $rs1->{seen_in_process});
eq_or_diff($rs2->{all}, $rs1->{all});
eq_or_diff($rs2->{genealogy}, $rs1->{genealogy});

eq_or_diff($rs3->{seen_in_process}, $rs1->{seen_in_process});
eq_or_diff($rs3->{all}, $rs1->{all});
eq_or_diff($rs3->{genealogy}, $rs1->{genealogy});

for my $rs ($rs1, $rs2, $rs3) {
    for my $hash (@hashes) {
        is($rs->get_source_by_hash($hash), $rs1->{hashed}{$hash},
           "Source code for $hash");
    }
}

sub _e { sprintf '(eval %d)', $_[0] }

for my $rs ($rs1, $rs2, $rs3) {
    # same process
    is($rs->get_source_by_name($parent_id, _e($first_eval_n)),
       '1 # in parent process', 'direct hit');
    is($rs->get_source_by_name($parent_id, _e($first_eval_n + 1)),
       '', 'direct hit, empty source');
    is($rs->get_source_by_name($parent_id, _e($first_eval_n + 2)),
       '', 'direct hit, empty source');
    is($rs->get_source_by_name($parent_id, _e($first_eval_n + 3)),
       '1 # in parent, after spawn', 'direct hit');
    is($rs->get_source_by_name($parent_id, _e($first_eval_n)),
       '1 # in parent process', 'same process, subsequent ordinal');
    is($rs->get_source_by_name($child_id, _e($first_eval_n + 3)),
       '1 # in child, after spawn', 'same process, subsequent ordinal');
    is($rs->get_source_by_name($grandchild_id, _e($first_eval_n + 2)),
       '1 # in grandchild', 'same process, subsequent ordinal');

    # same process but previous ordinal
    is($rs->get_source_by_name($parent_id, _e($first_eval_n + 4)),
       '', 'same process, previous ordinal');

    # follow genealogy, found in ancestor
    is($rs->get_source_by_name($child_id, _e($first_eval_n)),
       '1 # in parent process', 'parent process');
    is($rs->get_source_by_name($grandchild_id, _e($first_eval_n)),
       '1 # in parent process', 'grandparent process');

    # in ancestor, but after spawn point
    is($rs->get_source_by_name($child_id, _e($first_eval_n + 4)),
       '', 'after spawn point');
    is($rs->get_source_by_name($grandchild_id, _e($first_eval_n + 4)),
       '', 'after spawn point');
    is($rs->get_source_by_name($grandchild_id, _e($first_eval_n + 3)),
       '', 'after spawn point');
}

done_testing();
