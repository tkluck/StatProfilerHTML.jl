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
use Pod::Usage;
use Config;
use if $Config{usethreads}, 'threads';

require feature;

our @EXPORT = (
  @Test::More::EXPORT,
  @Test::Differences::EXPORT,
  qw(
        take_sample
        get_samples
        get_sources
        temp_profile_file
        temp_profile_dir
        precision_factor
        run_ctests
        spawn
        visual_test
  )
);

our $TAKE_SAMPLE_LINE;

sub import {
    unshift @INC, 't/lib';

    strict->import;
    warnings->import;
    feature->import(':5.12');

    if ((grep /^:fork$/, @_) && !$Config{d_fork}) {
        @_ = ('Test::More', 'skip_all', "fork() not available");
    }
    if ((grep /^:threads$/, @_) && !$Config{usethreads}) {
        @_ = ('Test::More', 'skip_all', "threads not available");
    }
    if ((grep /^:spawn$/, @_) && !$Config{usethreads} && !$Config{d_fork}) {
        @_ = ('Test::More', 'skip_all', "neither fork nor threads available");
    }
    if ((grep /^:visual$/, @_) && (!@ARGV || $ARGV[0] ne '-visual')) {
        @_ = ('Test::More', 'skip_all', "run with perl -Mblib $0 -visual");
    }

    @_ = grep !/^:(?:fork|threads|spawn|visual)$/, @_;

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

sub temp_profile_dir {
    state $debugging = $ENV{DEBUG};
    my $tmpdir = File::Temp::tempdir(CLEANUP => !$debugging);
    my $file = File::Spec->catfile($tmpdir, "tprof.out");
    if ($debugging) {
        say "# Temporary profiling output file: '$file'";
    }
    return ($tmpdir, $file);
}

sub take_sample {
    usleep(5000 * precision_factor()); BEGIN { $TAKE_SAMPLE_LINE = __LINE__ }
}

my $IS_DISTRIBUTION = $ENV{IS_DISTRIBUTION} // -f 'META.json';
if ($IS_DISTRIBUTION) {
    require Devel::StatProfiler;

    Devel::StatProfiler::Test::test_enable();
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

sub get_sources {
    my ($file) = @_;
    my $r = Devel::StatProfiler::Reader->new($file);

    1 while $r->read_trace;

    return $r->get_source_code;
}

sub precision_factor {
    my $precision = Devel::StatProfiler::get_precision();

    if ($precision < 900) {
        return 1;
    }
    return int(($precision / 1000) + 0.5) * 2;
}

sub visual_test {
    my ($output_dir, $sections) = @_;

    pod2usage(-msg      => "Manual test:\n",
              -verbose  => 99,
              -sections => $sections,
              -exitval  => 'NOEXIT');

    my $report = File::Spec::Functions::catfile($output_dir, 'index.html');

    eval {
        require Browser::Open;

        print "Report in $output_dir opened in default browser, press return when finished\n\n";

        Browser::Open::open_browser($report);

        1;
    } or do {
        print "Open the report $report with a browser, press return when finished\n\n";
    };

    readline(STDIN);
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

sub spawn {
    my ($sub, @args) = @_;

    if ($Config{usethreads}) {
        return threads->create($sub);
    } elsif ($Config{d_fork}) {
        my $pid = fork();

        if ($pid == -1) {
            die "Fork failed: $!";
        } elsif ($pid == 0) {
            $sub->(@args);

            exit 0;
        } else {
            return t::lib::Test::ForkSpawn->new($pid);
        }
    } else {
        die "Neither fork() nor threads available";
    }
}

package t::lib::Test::ForkSpawn;

sub new {
    my ($class, $pid) = @_;

    return bless {
        pid => $pid,
    }, $class;
}

sub join {
    my ($self) = @_;

    die "waitpid() error: $!"
        if waitpid($self->{pid}, 0) != $self->{pid};
}

package t::lib::Test::SingleReader;

sub new {
    my ($class, $reader) = @_;

    $reader->clear_custom_metadata;
    %{$reader->get_active_sections} = ();

    return bless {
        reader  => $reader,
        trace   => undef,
        read    => 0,
    }, $class;
}

sub get_source_tick_duration { $_[0]->{reader}->get_source_tick_duration }
sub get_source_stack_sample_depth { $_[0]->{reader}->get_source_stack_sample_depth }
sub get_source_perl_version { $_[0]->{reader}->get_source_perl_version }
sub get_active_sections { $_[0]->{reader}->get_active_sections }
sub get_custom_metadata { $_[0]->{reader}->get_custom_metadata }
sub clear_custom_metadata { $_[0]->{reader}->clear_custom_metadata }
sub get_source_code { $_[0]->{reader}->get_source_code }
sub get_reader_state { $_[0]->{reader}->get_reader_state }
sub set_reader_state { $_[0]->{reader}->set_reader_state($_[1]) }
sub is_stream_ended { $_[0]->{reader}->is_stream_ended }

sub done { !$_[0]->{trace} }

sub read_trace {
    my ($self) = @_;
    return if $self->{read};
    $self->{read} = 1;
    return $self->{trace} ||= $self->{reader}->read_trace;
}

# horrible, horrible hack
sub get_genealogy_info {
    state %ordinals;

    my ($self) = @_;

    return $self->{genealogy} ||= do {
        my ($process_id, $process_ordinal, $parent_id, $parent_ordinal) =
            @{$self->{reader}->get_genealogy_info};

        [$process_id, ++$ordinals{$self->{reader}}, $parent_id, $parent_ordinal];
    };
}

package t::lib::Test::FilteredReader;

sub new {
    my ($class, $file, $meta_value) = @_;

    return bless {
        reader  => Devel::StatProfiler::Reader->new($file),
        queue   => [],
        value   => $meta_value,
    }, $class;
}

sub get_source_tick_duration { $_[0]->{reader}->get_source_tick_duration }
sub get_source_stack_sample_depth { $_[0]->{reader}->get_source_stack_sample_depth }
sub get_source_perl_version { $_[0]->{reader}->get_source_perl_version }
sub get_genealogy_info { $_[0]->{reader}->get_genealogy_info }
sub get_custom_metadata { $_[0]->{reader}->get_custom_metadata }
sub get_source_code { $_[0]->{reader}->get_source_code }

sub read_trace {
    my ($self) = @_;
    return shift @{$self->{queue}} if @{$self->{queue}};

    my $r = $self->{reader};
    my @queue;
    while (my $trace = $r->read_trace) {
        push @queue, $trace;
        if ($trace->sections_changed) {
            if (%{$r->get_custom_metadata} &&
                    $self->{value} eq $r->get_custom_metadata->{key}) {
                $self->{queue} = \@queue;
                $r->clear_custom_metadata;
                return shift @{$self->{queue}};
            }
            $r->clear_custom_metadata;
            @queue = ();
        }
    }

    return;
}

1;
