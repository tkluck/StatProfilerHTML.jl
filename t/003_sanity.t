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

if (precision_factor == 1) {
    my ($s_100_a, $s_500_a, $s_200_a);
    for (1..3000) {
        sleepy(300); BEGIN { $s_100_a = __LINE__ }
        sleepy(500); BEGIN { $s_500_a = __LINE__ }
        sleepy(200); BEGIN { $s_200_a = __LINE__ }
    }
    ($s_100, $s_500, $s_200) = ($s_100_a, $s_500_a, $s_200_a);
} else {
    my ($s_100_b, $s_500_b, $s_200_b);
    for (1..30) {
        sleepy(3000 * precision_factor); BEGIN { $s_100_b = __LINE__ }
        sleepy(5000 * precision_factor); BEGIN { $s_500_b = __LINE__ }
        sleepy(2000 * precision_factor); BEGIN { $s_200_b = __LINE__ }
    }
    ($s_100, $s_500, $s_200) = ($s_100_b, $s_500_b, $s_200_b);
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

if (precision_factor == 1) {
    cmp_ok($total, '>=', 2900, 'total sample count is in a sane range');
    cmp_ok($total, '<=', 3800, 'total sample count is in a sane range');
} else {
    cmp_ok($total, '>=', 290 * precision_factor, 'total sample count is in a sane range');
    cmp_ok($total, '<=', 380 * precision_factor, 'total sample count is in a sane range');
}

cmp_ratio($sleep_pattern{$sleepy}, $total, 1, .10);
cmp_ratio($sleep_pattern{$s_100}, $total, 3/10, .15);
cmp_ratio($sleep_pattern{$s_500}, $total, 5/10, .15);
cmp_ratio($sleep_pattern{$s_200}, $total, 2/10, 25);
