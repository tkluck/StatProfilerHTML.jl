#!/usr/bin/env perl

use t::lib::Test tests => 3;

use Devel::StatProfiler::Reader;
use Time::HiRes qw(usleep);

use Devel::StatProfiler -file => 'tprof.out', -interval => 1000, -nostart;
my ($traced, $not_traced);

for (1..100) {
    Devel::StatProfiler::disable_profile();
    usleep(10000); BEGIN { $not_traced = __LINE__ }
    Devel::StatProfiler::enable_profile();
    usleep(10000); BEGIN { $traced = __LINE__ }
}

Devel::StatProfiler::stop_profile();

my $r = Devel::StatProfiler::Reader->new('tprof.out');
my ($total, %sleep_pattern);

while (my $trace = $r->read_trace) {
    my $frames = $trace->frames;

    $total += $trace->weight;

    for my $frame (grep $_->file =~ /011_switch_no_trampoline/, @$frames) {
        $sleep_pattern{$frame->line} += $trace->weight;
    }
}

ok(!exists $sleep_pattern{$not_traced});
ok(exists $sleep_pattern{$traced});
cmp_ok($sleep_pattern{$traced} || 0, '>=', 700);
