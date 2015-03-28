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
        shard           => $opts{shard},
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
        $self->{all}{$process_id}{$process_ordinal}{sparse}{$name} = $hash;
        $self->{hashed}{$hash} = $source_code->{$name};
    }
}

# this tries to optimize for the case where we dumped all evals, the number
# of evals is unlikely to be an issue when we only dump traced ones
sub _pack_data {
    my ($self) = @_;
    my $all = $self->{all};

    for my $process_id (keys %$all) {
        ORDINAL: for my $ordinal (keys %{$all->{$process_id}}) {
            my $first = $all->{$process_id}{$ordinal}{first};
            my $next = $first && $first + length($all->{$process_id}{$ordinal}{packed}) / 20;

            # files are processed in sequential order, and either we have all the
            # evals handed to us in order, or we have holes in the sequence
            # (depending on save_source mode)
            next if $first && !exists $all->{$process_id}{$ordinal}{sparse}{"(eval $next)"};
            my @indices = sort { $a <=> $b }
                          map  { /^\(eval ([0-9]+)\)$/ ? ($1) : () }
                               keys %{$all->{$process_id}{$ordinal}{sparse}};
            my $curr;
            if (!$first) {
                for my $index (@indices) {
                    if (!$first) {
                        $first = $index;
                        $next = $first + 1;
                    } elsif ($next == $index) {
                        ++$next
                    } else {
                        # not contiguous, bail out
                        next ORDINAL;
                    }
                }
                $all->{$process_id}{$ordinal}{first} = $curr = $first;
            } else {
                $curr = $next;
            }

            for my $name (@indices) {
                my $hash = delete $all->{$process_id}{$ordinal}{sparse}{"(eval $curr)"};
                $all->{$process_id}{$ordinal}{packed} .= pack "H*", $hash;
                ++$curr;
            }
        }
    }
}

sub _save {
    my ($self, $is_part) = @_;
    my $state_dir = state_dir($self, $is_part);
    my $source_dir = File::Spec::Functions::catdir($self->{root_dir}, '__source__');

    File::Path::mkpath([$state_dir, $source_dir]);

    $self->_pack_data;

    # $self->{seen_in_process} can be reconstructed fomr $self->{all}
    write_data_any($is_part, $self, $state_dir, 'source', $self->{all});

    for my $hash (keys %{$self->{hashed}}) {
        my $source_subdir = File::Spec::Functions::catdir(
            $source_dir,
            substr($hash, 0, 2),
            substr($hash, 2, 2),
        );

        File::Path::mkpath([$source_subdir]);
        write_file($source_subdir, substr($hash, 4), 'use_utf8', $self->{hashed}{$hash})
            unless -e File::Spec::Functions::catfile($source_subdir, substr($hash, 4));
    }
}

sub save_part { $_[0]->_save(1) }
sub save_merged { $_[0]->_save(0) }

sub _merge_source {
    my ($self, $all) = @_;

    for my $process_id (keys %$all) {
        for my $ordinal (keys %{$all->{$process_id}}) {
            my $entry = $all->{$process_id}{$ordinal};
            my $self_entry = $self->{all}{$process_id}{$ordinal} //= {};

            for my $name (keys %{$entry->{sparse} //
                                     # backwards compatibility
                                     $entry}) {
                my $hash = $entry->{sparse}{$name} //
                    # backwards compatibility
                    $entry->{$name};
                warn "Duplicate eval STRING source code for eval '$name'"
                    if exists $self->{seen_in_process}{$process_id}{$name} &&
                       $self->{seen_in_process}{$process_id}{$name} ne $hash;
                $self->{seen_in_process}{$process_id}{$name} = $hash;
                $self_entry->{sparse}{$name} = $hash;
            }

            if ($entry->{first}) {
                # this is a bit silly: first we construct a sparse map
                # out of the packed entry, then we re-pack it; still
                # it's more straightforward to code than the alternative,
                # and it should not hurt speed too much
                for my $i (0 .. length($entry->{packed}) / 20 - 1) {
                    my $name = "(eval " . ($entry->{first} + $i) . ")";
                    my $hash = unpack "H*", substr $entry->{packed}, $i * 20, 20;

                    warn "Duplicate eval STRING source code for eval '$name'"
                        if exists $self->{seen_in_process}{$process_id}{$name} &&
                            $self->{seen_in_process}{$process_id}{$name} ne $hash;
                    $self->{seen_in_process}{$process_id}{$name} = $hash;
                    $self_entry->{sparse}{$name} = $hash;
                }
            }
        }
    }

    $self->_pack_data;
}

sub load_and_merge {
    my ($self, $file) = @_;

    $self->_merge_source(read_data($self->{serializer}, $file));
}

sub get_source_by_hash {
    my ($self, $hash) = @_;

    return $self->{hashed}{$hash} // read_file(
        File::Spec::Functions::catfile(
            $self->{root_dir},
            '__source__',
            substr($hash, 0, 2),
            substr($hash, 2, 2),
            substr($hash, 4)
        ),
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
                if (my $entry = $self->{all}{$p_id}{$ord}) {
                    my $hash = $entry->{sparse}{$name};
                    return $hash if $hash;
                    if ($name =~ /^\(eval ([0-9]+)\)$/ &&
                            $entry->{first} &&
                            $1 >= $entry->{first} &&
                            $1 < $entry->{first} + length($entry->{packed}) / 20) {
                        return unpack 'H*', substr(
                            $entry->{packed},
                            ($1 - $entry->{first}) * 20,
                            20,
                        );
                    }
                }
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
