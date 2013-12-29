#!/usr/bin/perl

use 5.10.0;
use warnings;

my @data = map { { x => rand(100), y => rand(200), z => rand(300) } } 1..1000000;
my ($tx, $tyz);

sub accumulate {
    my ($entry) = @_;

    $tx += $entry->{x};
    $tyz += $entry->{y} + $entry->{z};
}

my $count = 0;
for my $entry (@data) {
    if ($count % 2) {
        accumulate($entry);
    } else {
        $tx += $entry->{x};
        $tyz += $entry->{y} + $entry->{z};
    }
    ++$count;
}

# print $tx / @data, ' ', $tyz / @data, "\n";
