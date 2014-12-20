package Devel::StatProfiler::Metadata;

use strict;
use warnings;

use Devel::StatProfiler::Utils qw(
    check_serializer
    read_data
    state_dir
    write_data_any
);
use File::Path;

sub new {
    my ($class, %opts) = @_;
    my $self = bless {
        metadata        => {},
        serializer      => $opts{serializer} || 'storable',
        root_dir        => $opts{root_directory},
        shard           => $opts{shard},
    }, $class;

    check_serializer($self->{serializer});

    return $self;
}

sub add_entry {
    my ($self, $key, $value) = @_;

    $self->{metadata}{$key} = $value;
}

sub set_at_inc {
    my ($self, $value) = @_;

    $self->add_entry("\x00at_inc", [split /\x00/, $value]);
}

sub _save {
    my ($self, $dir, $is_part) = @_;

    return unless %{$self->{metadata}};

    $dir //= state_dir($self, $is_part);
    File::Path::mkpath([$dir]);

    write_data_any($is_part, $self, $dir, 'metadata', $self->{metadata});
}

sub save_report_part { $_[0]->_save($_[1], 1) }
sub save_report_merged { $_[0]->_save($_[1], 0) }
sub save_part { $_[0]->_save(undef, 1) }
sub save_merged { $_[0]->_save(undef, 0) }

sub load_and_merge {
    my ($self, $file) = @_;

    $self->{metadata} = {
        %{$self->{metadata}},
        %{read_data($self->{serializer}, $file)},
    };
}

sub merge {
    my ($self, $report) = @_;

    $self->{metadata} = {
        %{$self->{metadata}},
        %{$report->{metadata}},
    };
}

sub get {
    my ($self) = @_;

    return { %{$self->{metadata}} };
}

sub get_at_inc {
    my ($self, $value) = @_;

    $self->{metadata}{"\x00at_inc"} // [];
}

1;
