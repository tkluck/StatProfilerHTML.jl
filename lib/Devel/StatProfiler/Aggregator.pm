package Devel::StatProfiler::Aggregator;
# ABSTRACT: aggregate profiler output into one or more reports

use strict;
use warnings;

use Devel::StatProfiler::Reader;
use Devel::StatProfiler::SectionChangeReader;
use Devel::StatProfiler::Report;
use Devel::StatProfiler::Utils qw(check_serializer read_data write_data);

use File::Path ();

my $main_report_id = ['__main__'];


sub new {
    my ($class, %opts) = @_;
    my $self = bless {
        root_dir     => $opts{root_directory},
        slowops      => $opts{slowops},
        flamegraph   => $opts{flamegraph},
        serializer   => $opts{serializer} || 'storable',
        processed    => {},
        reports      => {},
        partial      => {},
    }, $class;

    check_serializer($self->{serializer});
    $self->load;

    return $self;
}

sub process_trace_files {
    my ($self, @files) = @_;

    for my $file (@files) {
        my $r = ref $file ? $file : Devel::StatProfiler::Reader->new($file);
        my $sc = Devel::StatProfiler::SectionChangeReader->new($r);
        my ($process_id, $process_ordinal) = @{$r->get_genealogy_info};
        my $state = $self->{processed}{$process_id} ||= {
            process_id   => $process_id,
            ordinal      => 0,
            report       => undef,
            reader_state => undef,
        };
        next if $process_ordinal != $state->{ordinal} + 1;

        if (my $reader_state = delete $state->{reader_state}) {
            $r->set_reader_state($reader_state);
        }

        while ($sc->read_traces) {
            last if !$sc->sections_changed && %{$sc->get_active_sections};
            my $report_keys = $self->handle_section_change($sc, $sc->get_custom_metadata);
            my $entry = $self->{partial}{"@$report_keys"} ||= {
                report_keys => $report_keys,
                report      => $self->_fresh_report,
            };
            if ($state->{report}) {
                $entry->{report}->merge($state->{report});
                $state->{report} = undef;
            }
            $entry->{report}->add_trace_file($sc);
        }

        if (!$sc->empty) {
            $state->{report} ||= $self->_fresh_report;
            $state->{report}->add_trace_file($sc);
        }
        $state->{ordinal} = $process_ordinal;
        $state->{reader_state} = $r->get_reader_state;
    }
}

sub save {
    my ($self) = @_;

    for my $entry (values %{$self->{partial}}) {
        for my $key (@{$entry->{report_keys}}) {
            $self->_merge_report($key, $entry->{report});
        }
    }

    my $state_dir = File::Spec::Functions::catdir($self->{root_dir}, '__state__');
    File::Path::mkpath($state_dir);

    for my $process_id (keys %{$self->{processed}}) {
        my $processed = $self->{processed}{$process_id};

        write_data($self->{serializer}, $state_dir, "processed.$process_id", $processed);
    }

    for my $key (keys %{$self->{reports}}) {
        my $report_dir = File::Spec::Functions::catdir($self->{root_dir}, $key);
        $self->{reports}{$key}->save($self->{root_dir}, $report_dir);
    }
}

sub load {
    my ($self) = @_;

    return unless -d $self->{root_dir};
    my $state = File::Spec::Functions::catdir($self->{root_dir}, '__state__');

    for my $file (glob File::Spec::Functions::catfile($state, 'processed.*')) {
        my $processed = read_data($self->{serializer}, $file);

        $self->{processed}{$processed->{process_id}} = $processed;
    }
}

sub merged_report {
    my ($self, $report_id) = @_;

    my $res = $self->_fresh_report;

    for my $file (glob File::Spec::Functions::catfile($self->{root_dir}, $report_id, '*')) {
        my $report = $self->_fresh_report;

        $report->load($file);
        $res->merge($report);
    }

    for my $file (glob File::Spec::Functions::catfile($self->{root_dir}, '__state__', 'genealogy.*')) {
        $res->merge_genealogy(read_data($self->{serializer}, $file));
    }

    return $res;
}

sub _merge_report {
    my ($self, $report_id, $report) = @_;

    $self->{reports}{$report_id} ||= $self->_fresh_report;
    $self->{reports}{$report_id}->merge($report);
}

sub _fresh_report {
    my ($self) = @_;

    return Devel::StatProfiler::Report->new(
        slowops    => $self->{slowops},
        flamegraph => $self->{flamegraph},
        serializer => $self->{serializer},
    );
}

sub handle_section_change {
    my ($self, $sc, $state) = @_;

    return $main_report_id;
}

1;
