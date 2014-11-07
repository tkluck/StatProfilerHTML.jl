package Devel::StatProfiler::Aggregator;
# ABSTRACT: aggregate profiler output into one or more reports

use strict;
use warnings;

use Devel::StatProfiler::Reader;
use Devel::StatProfiler::SectionChangeReader;
use Devel::StatProfiler::Report;
use Devel::StatProfiler::EvalSource;
use Devel::StatProfiler::SourceMap;
use Devel::StatProfiler::Utils qw(
    check_serializer
    read_data
    write_data
    write_data_part
);

use File::Path ();

my $MAIN_REPORT_ID = ['__main__'];


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
        source       => Devel::StatProfiler::EvalSource->new(
            serializer     => $opts{serializer},
            root_directory => $opts{root_directory},
        ),
        sourcemap    => Devel::StatProfiler::SourceMap->new(
            serializer     => $opts{serializer},
            root_directory => $opts{root_directory},
        ),
        mixed_process=> $opts{mixed_process},
        genealogy    => {},
        fetchers     => $opts{fetchers},
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
        my ($process_id, $process_ordinal, $parent_id, $parent_ordinal) =
            @{$r->get_genealogy_info};
        my $state = $self->{processed}{$process_id} ||= {
            process_id   => $process_id,
            ordinal      => 0,
            report       => undef,
            reader_state => undef,
            modified     => 0,
        };
        next if $process_ordinal != $state->{ordinal} + 1;

        $self->{genealogy}{$process_id}{$process_ordinal} = [$parent_id, $parent_ordinal];

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
        $state->{modified} = 1;

        $self->{source}->add_sources_from_reader($r);
        $self->{sourcemap}->add_sources_from_reader($r);
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

    write_data_part($self->{serializer}, $state_dir, 'genealogy', $self->{genealogy});

    for my $process_id (keys %{$self->{processed}}) {
        my $processed = $self->{processed}{$process_id};

        next unless $processed->{modified};
        write_data($self->{serializer}, $state_dir, "processed.$process_id", $processed);
    }

    for my $key (keys %{$self->{reports}}) {
        my $report_dir = File::Spec::Functions::catdir($self->{root_dir}, $key);
        # writes some genealogy and source data twice, but it's OK for now
        $self->{reports}{$key}->save($self->{root_dir}, $report_dir);
    }

    $self->{source}->save($self->{root_dir});
    $self->{sourcemap}->save($self->{root_dir});
}

sub load {
    my ($self) = @_;

    return unless -d $self->{root_dir};
    my $state = File::Spec::Functions::catdir($self->{root_dir}, '__state__');

    for my $file (glob File::Spec::Functions::catfile($state, 'processed.*')) {
        my $processed = read_data($self->{serializer}, $file);

        $processed->{modified} = 0;
        $self->{processed}{$processed->{process_id}} = $processed;
    }
}

sub merged_report {
    my ($self, $report_id) = @_;

    my $res = $self->_fresh_report(mixed_process => 1);
    my $source = Devel::StatProfiler::EvalSource->new(
        serializer     => $self->{serializer},
        root_directory => $self->{root_dir},
        genealogy      => $self->{genealogy},
    );
    my $sourcemap = Devel::StatProfiler::SourceMap->new(
        serializer     => $self->{serializer},
        root_directory => $self->{root_dir},
    );

    for my $file (glob File::Spec::Functions::catfile($self->{root_dir}, '__state__', 'genealogy.*')) {
        $res->merge_genealogy(read_data($self->{serializer}, $file));
    }

    for my $file (glob File::Spec::Functions::catfile($self->{root_dir}, '__state__', 'source.*')) {
        $source->load_and_merge($file);
    }

    for my $file (glob File::Spec::Functions::catfile($self->{root_dir}, '__state__', 'sourcemap.*')) {
        $sourcemap->load_and_merge($file);
    }

    # TODO fix this incestuous relation
    $res->{source} = $source;
    $res->{sourcemap} = $sourcemap;
    %{$self->{genealogy}} = %{$res->{genealogy}};

    # mapping eval source code requires genealogy and source map
    for my $file (glob File::Spec::Functions::catfile($self->{root_dir}, $report_id, '*')) {
        my $report = $self->_fresh_report;

        # TODO fix this incestuous relation
        $report->{source} = $source;
        $report->{sourcemap} = $sourcemap;
        $report->{genealogy} = $self->{genealogy};

        $report->load($file);
        $report->map_source;
        $res->merge($report);
    }

    return $res;
}

sub _merge_report {
    my ($self, $report_id, $report) = @_;

    $self->{reports}{$report_id} ||= $self->_fresh_report;
    $self->{reports}{$report_id}->merge($report);
}

sub _fresh_report {
    my ($self, %opts) = @_;

    return Devel::StatProfiler::Report->new(
        slowops        => $self->{slowops},
        flamegraph     => $self->{flamegraph},
        serializer     => $self->{serializer},
        sources        => 0,
        root_directory => $self->{root_dir},
        mixed_process  => $opts{mixed_process} // $self->{mixed_process},
        fetchers       => $self->{fetchers},
    );
}

sub handle_section_change {
    my ($self, $sc, $state) = @_;

    return $MAIN_REPORT_ID;
}

1;
