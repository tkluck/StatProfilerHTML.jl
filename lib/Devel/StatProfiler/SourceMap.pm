package Devel::StatProfiler::SourceMap;

use strict;
use warnings;

use Devel::StatProfiler::Utils qw(
    check_serializer
    read_data
    state_dir
    utf8_sha1_hex
    write_data_any
);
use File::Path;
use File::Spec::Functions;

sub new {
    my ($class, %opts) = @_;
    my $self = bless {
        map             => {},
        reverse_map     => {},
        current_map     => undef,
        current_file    => undef,
        current_mapping => undef,
        ignore_mapping  => 0,
        root_dir        => $opts{root_directory},
        shard           => $opts{shard},
        serializer      => $opts{serializer} || 'storable',
    }, $class;

    check_serializer($self->{serializer});

    return $self;
}

sub start_file_mapping {
    my ($self, $physical_file) = @_;
    die "Causal failure for '$physical_file'" if $self->{current_map};

    if ($self->{map}{$physical_file}) {
        $self->{ignore_mapping} = 1;
        return;
    }

    $self->{ignore_mapping} = 0;
    $self->{current_map} = [1, $physical_file, 1];
    $self->{current_file} = $physical_file;
    $self->{current_mapping} = [$self->{current_map}];
}

sub end_file_mapping {
    my ($self, $physical_line) = @_;
    my ($current_map, $current_file, $current_mapping) =
        @{$self}{qw(current_map current_file current_mapping)};
    $self->{current_map} = $self->{current_file} = $self->{current_mapping} = undef;

    return if $self->{ignore_mapping};

    return if $current_map &&
        $current_map->[0] == 1 &&
        $current_map->[1] eq $current_file &&
        $current_map->[2] == 1;

    for my $entry (@$current_mapping) {
        $self->{reverse_map}{$entry->[1]}{$current_file} = 1;
    }

    # add last line
    push @$current_mapping, [$physical_line + 1, undef, $physical_line + 1];

    $self->{map}{$current_file} = $current_mapping;
}

sub add_file_mapping {
    my ($self, $physical_line, $mapped_file, $mapped_line) = @_;
    return if $self->{ignore_mapping};

    die "Causal failure for '$self->{current_file}'" unless $self->{current_map};

    my ($st, $en) = (substr($mapped_file, 0, 1), substr($mapped_file, -1, 1));
    if ($st eq $en && ($st eq '"' || $st eq "'")) {
        $mapped_file = substr($mapped_file, 1, -1);
    }

    if ($physical_line == $self->{current_map}[0] + 1) {
        $self->{current_map} = [$physical_line, $mapped_file, 0 + $mapped_line];
        $self->{current_mapping}->[-1] = $self->{current_map};
    } else {
        $self->{current_map} = [$physical_line, $mapped_file, 0 + $mapped_line];
        push @{$self->{current_mapping}}, $self->{current_map};
    }
}

sub add_sources_from_reader {
    my ($self, $r) = @_;

    my $source_code = $r->get_source_code;
    for my $name (keys %$source_code) {
        next unless $source_code->{$name} =~ /^#line\s+\d+\s+/m;

        my $eval_name = 'eval:' . utf8_sha1_hex($source_code->{$name});

        next if $self->{map}{$eval_name};

        $self->start_file_mapping($eval_name);

        while ($source_code->{$name} =~ /^#line\s+(\d+)\s+(.+?)$/mg) {
            my $line = substr($source_code->{$name}, 0, pos($source_code->{$name})) =~ tr/\n/\n/;
            $self->add_file_mapping($line + 2, $2, $1);
        }

        # a\nb\n -> 2 newlines, 2 lines, a\nb -> 1 newline, still 2 lines
        $self->end_file_mapping($source_code->{$name} =~ tr/\n/\n/ +
                                    (substr($source_code->{$name}, -1) ne "\n"));
    }
}

sub _save {
    my ($self, $state_dir, $is_part) = @_;

    $state_dir //= state_dir($self);
    File::Path::mkpath($state_dir);

    write_data_any($is_part, $self, $state_dir, 'sourcemap', $self->{map})
        if %{$self->{map}};
}

sub save_part { $_[0]->_save($_[1], 1) }
sub save_merged { $_[0]->_save(undef, 0) }

sub load_and_merge {
    my ($self, @files) = @_;

    $self->_load_and_merge($_) for @files;
}

sub _load_and_merge {
    my ($self, $file) = @_;
    my $data = read_data($self->{serializer}, $file);

    for my $key (keys %$data) {
        $self->{map}{$key} = $data->{$key};

        for my $entry (@{$data->{$key}}) {
            $self->{reverse_map}{$entry->[1]}{$key} = 1
                if $entry->[1]; # skip sentinel entry for last line
        }
    }
}

sub get_mapping {
    my ($self, $file) = @_;

    return $self->{map}{$file};
}

sub get_reverse_mapping {
    my ($self, $file) = @_;

    $file = $2 if $file =~ m{^qeval:([0-9a-f]+)/(.+)$};

    return unless $self->{reverse_map}{$file};
    return (keys %{$self->{reverse_map}{$file}})[0];
}

1;
