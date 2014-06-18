#!/usr/bin/env perl

use t::lib::Test;
use t::lib::Slowops;

use Devel::StatProfiler::Report;
use Time::HiRes qw(time);

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }

use Devel::StatProfiler -file => $profile_file, -interval => 1000;

for (my $count = 10000; ; $count *= 2) {
    my $start = time;
    note("Trying with $count iterations");
    t::lib::Slowops::foo($count);
    -d '.' for 1..$count;
    last if time - $start >= 0.5;
}

Devel::StatProfiler::stop_profile();

my ($process_id);

my $r1 = Devel::StatProfiler::Report->new(
    flamegraph => 1,
    slowops    => [qw(ftdir unstack)],
);
$r1->add_trace_file($profile_file);
# no need to finalize the report for comparison

my $r2 = Devel::StatProfiler::Report->new(
    flamegraph => 1,
    slowops    => [qw(ftdir unstack)],
);
my $r = Devel::StatProfiler::Reader->new($profile_file);
($process_id) = @{$r->get_genealogy_info};

for (;;) {
    my $sr = t::lib::Test::SingleReader->new($r);
    my $t = Devel::StatProfiler::Report->new(
        flamegraph => 1,
        slowops    => [qw(ftdir unstack)],
    );
    $t->add_trace_file($sr);
    $r2->merge($t);
    last if $sr->done;
}
# no need to finalize the report for comparison

# we fake the ordinals in t::lib::Test::SingleReader
$_->{genealogy}{$process_id} = { 1 => $_->{genealogy}{$process_id}{1} }
    for $r1, $r2;

eq_or_diff($r2, $r1);
done_testing();
