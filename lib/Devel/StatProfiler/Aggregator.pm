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
    state_dir
    state_file
    write_data
    write_data_part
);

use File::Path ();

my $MAIN_REPORT_ID = ['__main__'];


sub shards {
    my ($class, $root_dir) = @_;
    my $state_dir = state_dir({root_dir => $root_dir});
    my @files = glob File::Spec::Functions::catfile($state_dir, 'shard.*');

    return map m{[/\\]shard\.([^/\\]+)$}, @files;
}

sub new {
    my ($class, %opts) = @_;
    my $genealogy = {};
    my $self = bless {
        root_dir     => $opts{root_directory},
        shard        => $opts{shard},
        shards       => $opts{shards},
        slowops      => $opts{slowops},
        flamegraph   => $opts{flamegraph},
        serializer   => $opts{serializer} || 'storable',
        processed    => {},
        reports      => {},
        partial      => {},
        source       => Devel::StatProfiler::EvalSource->new(
            serializer     => $opts{serializer},
            root_directory => $opts{root_directory},
            shard          => $opts{shard},
            genealogy      => $genealogy,
        ),
        sourcemap    => Devel::StatProfiler::SourceMap->new(
            serializer     => $opts{serializer},
            root_directory => $opts{root_directory},
            shard          => $opts{shard},
        ),
        mixed_process=> $opts{mixed_process},
        genealogy    => $genealogy,
        parts        => [],
        fetchers     => $opts{fetchers},
    }, $class;

    check_serializer($self->{serializer});
    $self->load;

    return $self;
}

sub can_process_trace_file {
    my ($self, @files) = @_;

    return grep {
        my $r = ref $_ ? $_ : Devel::StatProfiler::Reader->new($_);
        my ($process_id, $process_ordinal, $parent_id, $parent_ordinal) =
            @{$r->get_genealogy_info};
        my $state = $self->{processed}{$process_id} // { ordinal => 0 };

        $process_ordinal == $state->{ordinal} + 1;
    } @files;
}

sub process_trace_files {
    my ($self, @files) = @_;

    for my $file (@files) {
        my $r = ref $file ? $file : Devel::StatProfiler::Reader->new($file);
        my $sc = Devel::StatProfiler::SectionChangeReader->new($r);
        my ($process_id, $process_ordinal, $parent_id, $parent_ordinal) =
            @{$r->get_genealogy_info};
        next if $process_ordinal > 1 && !$self->{processed}{$process_id};
        my $state = $self->{processed}{$process_id} ||= {
            process_id   => $process_id,
            ordinal      => 0,
            report       => undef,
            reader_state => undef,
            modified     => 0,
            ended        => 0,
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
        $state->{ended} = $r->is_stream_ended;

        $self->{source}->add_sources_from_reader($r);
        $self->{sourcemap}->add_sources_from_reader($r);
    }
}

sub save_part {
    my ($self) = @_;

    for my $entry (values %{$self->{partial}}) {
        for my $key (@{$entry->{report_keys}}) {
            $self->_merge_report($key, $entry->{report});
        }
    }

    my $state_dir = state_dir($self);
    my $parts_dir = state_dir($self, 1);
    File::Path::mkpath([$state_dir, $parts_dir]);

    write_data_part($self, $parts_dir, 'genealogy', $self->{genealogy});

    for my $process_id (keys %{$self->{processed}}) {
        my $processed = $self->{processed}{$process_id};

        next unless $processed->{modified};
        write_data($self, $state_dir, "processed.$process_id", $processed);
    }

    $self->{source}->save_part;
    $self->{sourcemap}->save_part;

    for my $key (keys %{$self->{reports}}) {
        my $report_dir = File::Spec::Functions::catdir(
            $self->{root_dir}, $key, 'parts',
        );
        # writes some genealogy and source data twice, but it's OK for now
        $self->{reports}{$key}->save_part($report_dir);
    }

    my $shard_marker = File::Spec::Functions::catfile($state_dir, "shard.$self->{shard}");
    unless (-f $shard_marker) {
        open my $fh, '>', $shard_marker;
    }
}

sub load {
    my ($self) = @_;

    return unless -d $self->{root_dir} && $self->{shard};
    my $processed_glob = state_file($self, 0, 'processed.%') =~ s{%}{*}r;

    for my $file (glob $processed_glob) {
        my $processed = read_data($self->{serializer}, $file);

        $processed->{modified} = 0;
        $self->{processed}{$processed->{process_id}} = $processed;
    }
}

sub _merge_genealogy {
    my ($self, $genealogy) = @_;

    for my $process_id (keys %$genealogy) {
        my $item = $genealogy->{$process_id};

        @{$self->{genealogy}{$process_id}}{keys %$item} = values %$item;
    }
}

sub _load_metadata {
    my ($self, $parts) = @_;

    return if %{$self->{genealogy}};

    my $source = $self->{source} = Devel::StatProfiler::EvalSource->new(
        serializer     => $self->{serializer},
        root_directory => $self->{root_dir},
        shard          => $self->{shard},
        genealogy      => $self->{genealogy},
    );
    my $sourcemap = $self->{sourcemap} = Devel::StatProfiler::SourceMap->new(
        serializer     => $self->{serializer},
        root_directory => $self->{root_dir},
        shard          => $self->{shard},
    );

    my (@genealogy_merged, @source_merged, @sourcemap_merged);
    for my $shard ($self->{shard} ? ($self->{shard}) : @{$self->{shards}}) {
        my $info = {root_dir => $self->{root_dir}, shard => $shard};
        push @genealogy_merged, state_file($info, 0, 'genealogy');
        push @source_merged, state_file($info, 0, 'source');
        push @sourcemap_merged, state_file($info, 0, 'sourcemap');
    }

    my @genealogy_parts = $parts ? glob state_file($self, 1, 'genealogy.*') : ();
    my @source_parts = $parts ? glob state_file($self, 1, 'source.*') : ();
    my @sourcemap_parts = $parts ? glob state_file($self, 1, 'sourcemap.*') : ();

    for my $file (grep -f $_, (@genealogy_parts, @genealogy_merged)) {
        $self->_merge_genealogy(read_data($self->{serializer}, $file));
    }

    for my $file (grep -f $_, (@source_parts, @source_merged)) {
        $source->load_and_merge($file);
    }

    for my $file (grep -f $_, (@sourcemap_parts, @sourcemap_merged)) {
        $sourcemap->load_and_merge($file);
    }

    push @{$self->{parts}}, @genealogy_parts, @source_parts, @sourcemap_parts;
}

sub merge_metadata {
    my ($self) = @_;

    $self->_load_metadata('parts');

    write_data($self, state_dir($self), 'genealogy', $self->{genealogy});
    $self->{source}->save_merged;
    $self->{sourcemap}->save_merged;

    for my $part (@{$self->{parts}}) {
        unlink $part;
    }
}

sub merge_report {
    my ($self, $report_id) = @_;

    $self->_load_metadata('parts');

    my @parts = glob File::Spec::Functions::catfile($self->{root_dir}, $report_id, 'parts', "*.$self->{shard}.*");
    my $res = $self->_fresh_report(mixed_process => 1);

    # TODO fix this incestuous relation
    $res->{source} = $self->{source};
    $res->{sourcemap} = $self->{sourcemap};
    $res->{genealogy} = $self->{genealogy};

    for my $file (@parts) {
        my $report = $self->_fresh_report;

        $report->load($file);
        $res->merge($report);
    }

    my $report_dir = File::Spec::Functions::catdir($self->{root_dir}, $report_id);
    $res->save_aggregate($report_dir);

    for my $part (@parts) {
        unlink $part;
    }

    return $res;
}

sub merged_report {
    my ($self, $report_id, $map_source) = @_;

    $self->_load_metadata;

    my $res = $self->_fresh_report(mixed_process => 1);

    # TODO fix this incestuous relation
    $res->{source} = $self->{source};
    $res->{sourcemap} = $self->{sourcemap};
    $res->{genealogy} = $self->{genealogy};

    my $first = 1;
    for my $shard (@{$self->{shards}}) {
        my $file = File::Spec::Functions::catfile($self->{root_dir}, $report_id, "report.$shard");

        if (-f $file) {
            my $report = $first ? $res : $self->_fresh_report;

            $report->load($file);
            $res->merge($report) if !$first && $report->{tick}; # TODO add accessor
        }
        $first = 0;
    }

    $res->map_source if $map_source;

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
        shard          => $self->{shard},
        mixed_process  => $opts{mixed_process} // $self->{mixed_process},
        fetchers       => $self->{fetchers},
    );
}

sub report_names {
    my ($self) = @_;
    my @dirs = grep $_ ne '__state__' && $_ ne '__source__',
        map  File::Basename::basename($_),
        grep -d $_,
        glob File::Spec::Functions::catfile($self->{root_dir}, '*');

    return \@dirs;
}

sub handle_section_change {
    my ($self, $sc, $state) = @_;

    return $MAIN_REPORT_ID;
}

1;
