package t::lib::Test;
use 5.12.0;
use warnings;
use parent 'Test::Builder::Module';

use Test::More;
use Test::Differences;
use Time::HiRes qw(usleep);
use File::Temp ();
use File::Spec;
use Capture::Tiny qw(capture);

require feature;

our @EXPORT = (
  @Test::More::EXPORT,
  @Test::Differences::EXPORT,
  qw(take_sample get_samples temp_profile_file precision_factor run_ctests)
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

sub run_ctests {
    my (@tests) = @_;
    my $profile_file = temp_profile_file();

    for my $test (@tests) {
        my ($fh, $filename) = File::Temp::tempfile('testXXXXXX', UNLINK => 1);

        print $fh $test->{source};
        $fh->flush;

        my ($stdout, $stderr, $exit) = capture {
            system('t/callsv', '-Mblib',
                   '-MDevel::StatProfiler=-file,' . $profile_file .
                       ($test->{start} ? '' : ',-nostart'),
                   $filename, $test->{tests} ? @{$test->{tests}} : 'test');
        };

        if ($exit & 0xff) {
            fail("$test->{name} - terminated by signal");
        } else {
            is($exit >> 8, $test->{exit} // 0,  "$test->{name} - exit code is equal");
        }
        is($stdout, $test->{stdout} // '', "$test->{name} - stdout is equal");
        is($stderr, $test->{stderr} // '', "$test->{name} - stderr is equal");
    }

    done_testing();
}

1;
