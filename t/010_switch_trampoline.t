#!/usr/bin/env perl

use t::lib::Test tests => 3;

use Devel::StatProfiler::Reader;
use Time::HiRes qw(usleep);

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }

use Devel::StatProfiler -file => $profile_file, -interval => 1000;
my ($traced, $not_traced);

for (1..100) {
    Devel::StatProfiler::disable_profile();
    usleep(10000); BEGIN { $not_traced = __LINE__ }
    Devel::StatProfiler::enable_profile();
    usleep(10000); BEGIN { $traced = __LINE__ }
}

Devel::StatProfiler::stop_profile();

my $r = Devel::StatProfiler::Reader->new($profile_file);
my ($total, %sleep_pattern);

while (my $trace = $r->read_trace) {
    my $frames = $trace->frames;

    $total += $trace->weight;

    for my $frame (grep $_->file =~ /010_switch_trampoline/, @$frames) {
        $sleep_pattern{$frame->line} += $trace->weight;
    }
}

ok(!exists $sleep_pattern{$not_traced});
ok(exists $sleep_pattern{$traced});
cmp_ok($sleep_pattern{$traced} || 0, '>=', 700);
