package t::lib::Test;

use strict;
use warnings;
use parent 'Test::Builder::Module';

use Test::More;
use Test::Differences;
use Time::HiRes qw(usleep);

require feature;

our @EXPORT = (
  @Test::More::EXPORT,
  @Test::Differences::EXPORT,
  qw(take_sample get_samples)
);

sub import {
    unshift @INC, 't/lib';

    strict->import;
    warnings->import;
    feature->import(':5.12');

    goto &Test::Builder::Module::import;
}

sub take_sample {
    # tests run with 1ms sample, use 10 times that
    usleep(10000);
}

sub get_samples {
    my ($file) = @_;
    my $r = Devel::StatProfiler::Reader->new($file);
    my @samples;;

    while (my $trace = $r->read_trace) {
        my $frames = $trace->frames;
        next unless @$frames;
        next unless $frames->[0]->subroutine eq 'Time::HiRes::usleep';

        push @samples, $frames;
    }

    return @samples;
}

1;
