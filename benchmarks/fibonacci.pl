#!/usr/bin/perl

use 5.10.0;
use warnings;

use Memoize qw(memoize);

sub fib1 {
    my ($n) = @_;

    return $n if $n < 2;
    return fib1($n -1) + fib1($n - 2);
}

sub fib2 {
    my ($n) = @_;
    my ($r1, $r2) = (1, 1);

    while ($n > 1) {
        my $next = $r1 + $r2;
        $r1 = $r2;
        $r2 = $next;
        --$n;
    }

    return $r1;
}

my %c;

sub fib3 {
    no warnings 'recursion';

    my ($n) = @_;
    return $n if $n < 2;
    return $c{$n} if exists $c{$n};
    return $c{$n} = fib3($n -1) + fib3($n - 2);
}

for (1..28) {
    fib1($_);
}

for (1..3000) {
    fib2($_);
}

for (1..1200) {
    %c = ();
    fib3($_);
}
