package t::lib::Test;
use 5.12.0;
use warnings;
use parent 'Test::Builder::Module';

use Test::More;
use Test::Differences;
use Time::HiRes qw(usleep);
use File::Temp ();
use File::Spec;

require feature;

our @EXPORT = (
  @Test::More::EXPORT,
  @Test::Differences::EXPORT,
  qw(take_sample get_samples temp_profile_file precision_factor)
);

sub import {
    unshift @INC, 't/lib';

    strict->import;
    warnings->import;
    feature->import(':5.12');

    goto &Test::Builder::Module::import;
}

sub temp_profile_file {
    state $debugging = $ENV{DEBUG};
    state $tmpdir = File::Temp::tempdir(CLEANUP => !$debugging);
    my $file = File::Temp::mktemp(File::Spec->catfile($tmpdir, "tprof.outXXXXXXXX"));
    if ($debugging) {
        say "# Temporary profiling output file: '$file'";
    }
    return $file;
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
        next unless $frames->[0]->fq_sub_name eq 'Time::HiRes::usleep';

        push @samples, $frames;
    }

    return @samples;
}

sub precision_factor {
    my $precision = Devel::StatProfiler::get_precision();

    if ($precision < 900) {
        return 1;
    }
    return int(($precision / 1000) + 0.5) * 2;
}

1;
