#!/usr/bin/env perl

use t::lib::Test tests => 6;

use Devel::StatProfiler::Reader;
use Time::HiRes qw(usleep);

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }

use Devel::StatProfiler -file => $profile_file, -interval => 1000;
my ($sleepy, $s_100, $s_500, $s_200);

sub sleepy {
    usleep($_[0]); BEGIN { $sleepy = __LINE__ }
}

for (1..3000) {
    sleepy(300); BEGIN { $s_100 = __LINE__ }
    sleepy(500); BEGIN { $s_500 = __LINE__ }
    sleepy(200); BEGIN { $s_200 = __LINE__ }
}

Devel::StatProfiler::stop_profile();

my $r = Devel::StatProfiler::Reader->new($profile_file);

my ($total, %sleep_pattern);

while (my $trace = $r->read_trace) {
    my $frames = $trace->frames;

    $total += $trace->weight;

    for my $frame (grep $_->file =~ /003_sanity/, @$frames) {
        $sleep_pattern{$frame->line} += $trace->weight;
    }
}

sub cmp_ratio {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my ($fraction, $total, $ratio, $tolerance, $desc) = @_;
    my ($min, $max) = ($ratio - $ratio * $tolerance, $ratio + $ratio * $tolerance);
    my $got_ratio = $fraction / $total;
    $desc ||= "$fraction/$total is around $ratio";

    if (!ok($got_ratio >= $min && $got_ratio <= $max, $desc)) {
        diag("$got_ratio is not within $tolerance tolerance from $ratio");
    }
}

cmp_ok($total, '>=', 3200, 'total sample count is in a sane range');
cmp_ok($total, '<=', 3600, 'total sample count is in a sane range');

cmp_ratio($sleep_pattern{$sleepy}, $total, 1, .10);
cmp_ratio($sleep_pattern{$s_100}, $total, 3/10, .15);
cmp_ratio($sleep_pattern{$s_500}, $total, 5/10, .15);
cmp_ratio($sleep_pattern{$s_200}, $total, 2/10, 25);
