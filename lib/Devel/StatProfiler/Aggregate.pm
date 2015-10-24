package Devel::StatProfiler::Aggregate;
# ABSTRACT: profile aggregation result

use strict;
use warnings;

use Devel::StatProfiler::Report;
use Devel::StatProfiler::EvalSource;
use Devel::StatProfiler::SourceMap;
use Devel::StatProfiler::Metadata;
use Devel::StatProfiler::Utils qw(
    check_serializer
    state_dir
    write_data
);

use File::Glob qw(bsd_glob);


sub shards {
    my ($class, $root_dir) = @_;
    my $state_dir = state_dir({root_dir => $root_dir});
    my @files = bsd_glob File::Spec::Functions::catfile($state_dir, 'shard.*');

    return map m{[/\\]shard\.([^/\\]+)$}, @files;
}

sub new {
    my ($class, %opts) = @_;
    my $self = bless {
        root_dir     => $opts{root_directory},
        shard        => $opts{shard},
        shards       => $opts{shards} || [$opts{shard}],
        flamegraph   => $opts{flamegraph},
        serializer   => $opts{serializer} || 'storable',
        source       => undef,
        sourcemap    => undef,
        metadata     => undef,
        genealogy    => undef,
        last_sample  => undef,
        fetchers     => $opts{fetchers},
        now          => time,
        timebox      => $opts{timebox},
    }, $class;

    check_serializer($self->{serializer});

    return $self;
}

sub merged_report {
    my ($self, $report_id, $map_source) = @_;

    $self->_load_all_metadata;

    my $res = $self->_fresh_report(mixed_process => 1);

    # TODO fix this incestuous relation
    $res->{source} = $self->{source};
    $res->{sourcemap} = $self->{sourcemap};
    $res->{genealogy} = $self->{genealogy};

    my $first = 1;
    for my $shard (@{$self->{shards}}) {
        my $data_glob = File::Spec::Functions::catfile($self->{root_dir}, $report_id, "report.*.$shard");
        my $metadata = File::Spec::Functions::catfile($self->{root_dir}, $report_id, "metadata.$shard");

        for my $data (bsd_glob $data_glob) {
            my $report = $first ? $res : $self->_fresh_report;

            $report->load($data);
            $res->merge($report) if !$first && $report->{tick}; # TODO add accessor
            $first = 0;
        }
        if (-f $metadata) {
            $res->load_and_merge_metadata($metadata);
        }
    }

    $res->add_metadata($self->global_metadata);
    $res->map_source if $map_source;

    return $res;
}

sub merged_report_metadata {
    my ($self, $report_id) = @_;

    $self->_load_metadata;

    my $res = Devel::StatProfiler::Metadata->new(
        serializer     => $self->{serializer},
        root_directory => $self->{root_dir},
        shard          => $self->{shard},
    );

    for my $shard (@{$self->{shards}}) {
        my $metadata = File::Spec::Functions::catfile($self->{root_dir}, $report_id, "metadata.$shard");

        if (-f $metadata) {
            $res->load_and_merge($metadata);
        }
    }

    $res->add_entries($self->global_metadata);

    return $res;
}

sub _fresh_report {
    my ($self, %opts) = @_;

    return Devel::StatProfiler::Report->new(
        flamegraph     => $self->{flamegraph},
        serializer     => $self->{serializer},
        sources        => 0,
        root_directory => $self->{root_dir},
        shard          => $self->{shard},
        mixed_process  => $opts{mixed_process} // $self->{mixed_process},
        fetchers       => $self->{fetchers},
        suffix         => $opts{suffix} // '',
    );
}

sub _all_reports {
    my ($self, @dirs) = @_;
    my @reports = grep {
        $_ eq '__main__' || $_ !~ /^__/
    } map  File::Basename::basename($_),
      grep -d $_,
      map  bsd_glob($_ . '/*'),
           @dirs;
    my %uniq; @uniq{@reports} = ();

    return keys %uniq;
}

sub all_reports { my ($self) = @_; return $self->_all_reports($self->{root_dir}) }
sub all_unmerged_reports { my ($self) = @_; return $self->_all_reports($self->{parts_dir}) }

sub discard_expired_process_data {
    my ($self, $expiration) = @_;

    $self->_load_all_metadata;

    my @shards = __PACKAGE__->shards($self->{root_dir});
    my $aggregator = __PACKAGE__->new(
        root_directory => $self->{root_dir},
        shards         => \@shards,
        serializer     => $self->{serializer},
    );

    $aggregator->_load_all_metadata;

    my $last_sample = $aggregator->{last_sample};
    my $genealogy = $aggregator->{genealogy};

    my @queue = keys %{$self->{last_sample}};
    while (@queue) {
        my %updated;

        for my $process_id (@queue) {
            my $parent = $genealogy->{$process_id}{1};
            my $parent_id = $parent->[0];

            unless ($parent_id) {
                # warn "Broken genealogy: '$process_id' has no parent";
                next;
            }
            next if $parent_id eq "00" x 24;
            $updated{$parent_id} = undef;
            $last_sample->{$parent_id} = $last_sample->{$process_id}
                if ($last_sample->{$parent_id} // 0) < $last_sample->{$process_id};
        }

        @queue = keys %updated;
    }

    for my $process_id (keys %$genealogy) {
        next if ($last_sample->{$process_id} // 0) > $expiration;

        # garbage-collect process-related metadata, under the
        # assumption that if that neither the process nor its childs
        # produced any samples in the given timeframe, they are "dead"
        delete $self->{genealogy}{$process_id};
        delete $self->{last_sample}{$process_id};
        $self->{source}->delete_process($process_id);
    }

    # TODO Garbage-collect eval source code

    write_data($self, state_dir($self), 'genealogy', $self->{genealogy})
        if $self->{genealogy};
    write_data($self, state_dir($self), 'last_sample', $self->{last_sample})
        if $self->{last_sample};
    $self->{source}->save_merged;
}

sub report_names {
    my ($self) = @_;
    my @dirs = grep $_ ne '__state__' && $_ ne '__source__',
        map  File::Basename::basename($_),
        grep -d $_,
        bsd_glob File::Spec::Functions::catfile($self->{root_dir}, '*');

    return \@dirs;
}

# temporary during refactoring
*_load_all_metadata = \&Devel::StatProfiler::Aggregator::_load_all_metadata;
*_load_metadata = \&Devel::StatProfiler::Aggregator::_load_metadata;
*_load_genealogy = \&Devel::StatProfiler::Aggregator::_load_genealogy;
*_load_last_sample = \&Devel::StatProfiler::Aggregator::_load_last_sample;
*_load_source = \&Devel::StatProfiler::Aggregator::_load_source;
*_load_sourcemap = \&Devel::StatProfiler::Aggregator::_load_sourcemap;
*_merge_genealogy = \&Devel::StatProfiler::Aggregator::_merge_genealogy;
*_merge_last_sample = \&Devel::StatProfiler::Aggregator::_merge_last_sample;

*global_metadata = \&Devel::StatProfiler::Aggregator::global_metadata;

1;
