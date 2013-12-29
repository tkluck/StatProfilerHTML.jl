#!/usr/bin/perl

use 5.10.0;
use warnings;

sub foo {
    my $x = 1;

    for (1..1e3) {
        $x = $x + $x - $x - $x + 1;
    }

    return $x
}

my $y;

for (1..2e3) {
    $y += foo();
}
