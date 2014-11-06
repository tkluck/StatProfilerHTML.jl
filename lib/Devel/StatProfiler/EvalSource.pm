package Devel::StatProfiler::EvalSource;

use strict;
use warnings;

use Devel::StatProfiler::Utils qw(
    check_serializer
    read_data
    read_file
    state_dir
    utf8_sha1_hex
    write_data_any
    write_file
);
use File::Path;
use File::Spec::Functions;

sub new {
    my ($class, %opts) = @_;
    my $self = bless {
        all             => {},
        seen_in_process => {},
        hashed          => {},
        serializer      => $opts{serializer} || 'storable',
        root_dir        => $opts{root_directory},
        genealogy       => $opts{genealogy},
    }, $class;

    check_serializer($self->{serializer});

    return $self;
}

sub add_sources_from_reader {
    my ($self, $r) = @_;

    my ($process_id, $process_ordinal) = @{$r->get_genealogy_info};
    my $source_code = $r->get_source_code;
    for my $name (keys %$source_code) {
        my $hash = utf8_sha1_hex($source_code->{$name});

        warn "Duplicate eval STRING source code for eval '$name'"
            if exists $self->{seen_in_process}{$process_id}{$name} &&
               $self->{seen_in_process}{$process_id}{$name} ne $hash;
        $self->{seen_in_process}{$process_id}{$name} = $hash;
        $self->{all}{$process_id}{$process_ordinal}{$name} = $hash;
        $self->{hashed}{$hash} = $source_code->{$name};
    }
}

sub _save {
    my ($self, $root_dir, $is_part) = @_;
    my $state_dir = state_dir($root_dir, $is_part);
    my $source_dir = File::Spec::Functions::catdir($root_dir, '__source__');

    File::Path::mkpath([$state_dir, $source_dir]);

    # $self->{seen_in_process} can be reconstructed fomr $self->{all}
    write_data_any($is_part, $self->{serializer}, $state_dir, 'source', $self->{all});

    for my $hash (keys %{$self->{hashed}}) {
        write_file($source_dir, $hash, 'use_utf8', $self->{hashed}{$hash});
    }
}

sub save_part { $_[0]->_save($_[1], 1) }
sub save_merged { $_[0]->_save($_[1], 0) }

sub _merge_source {
    my ($self, $all) = @_;

    for my $process_id (keys %$all) {
        for my $ordinal (keys %{$all->{$process_id}}) {
            for my $name (keys %{$all->{$process_id}{$ordinal}}) {
                my $hash = $all->{$process_id}{$ordinal}{$name};
                warn "Duplicate eval STRING source code for eval '$name'"
                    if exists $self->{seen_in_process}{$process_id}{$name} &&
                       $self->{seen_in_process}{$process_id}{$name} ne $hash;
                $self->{seen_in_process}{$process_id}{$name} = $hash;
                $self->{all}{$process_id}{$ordinal}{$name} = $hash;
            }
        }
    }
}

sub load_and_merge {
    my ($self, $file) = @_;

    $self->_merge_source(read_data($self->{serializer}, $file));
}

sub get_source_by_hash {
    my ($self, $hash) = @_;

    return $self->{hashed}{$hash} // read_file(
        File::Spec::Functions::catfile($self->{root_dir}, '__source__', $hash),
        'use_utf8',
    );
}

sub get_hash_by_name {
    my ($self, $process_id, $name) = @_;
    my ($ordinal) = sort { $b <=> $a } keys %{$self->{all}{$process_id} || {}};
    my @queue = [$process_id, $ordinal];

    while (@queue) {
        my ($p_id, $o) = @{pop @queue};

        if ($self->{genealogy}{$p_id}) {
            my ($ord) = keys %{$self->{genealogy}{$p_id}};

            push @queue, $self->{genealogy}{$p_id}{$ord}
                 if $self->{genealogy}{$p_id}{$ord} &&
                    # the root process has parent ['0000...0000', 0]
                    $self->{genealogy}{$p_id}{$ord}[1] != 0;
        }

        if ($self->{all}{$p_id}) {
            for my $ord (reverse 1..$o) {
                my $hash = $self->{all}{$p_id}{$ord} &&
                    $self->{all}{$p_id}{$ord}{$name};
                return $hash if $hash;
            }
        }
    }

    return undef;
}

sub get_source_by_name {
    my ($self, $process_id, $name) = @_;
    my $hash = $self->get_hash_by_name($process_id, $name);

    return $hash ? $self->get_source_by_hash($hash) : '';
}

1;
