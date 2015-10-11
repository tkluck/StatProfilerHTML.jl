package Devel::StatProfiler::NameMap;

use strict;
use warnings;

sub new {
    my ($class, %opts) = @_;
    my $self = bless {
        source      => $opts{source},
        names       => $opts{names},
    }, $class;

    for my $package (keys %{$self->{names}}) {
        my @prefixes = sort { length($b) <=> length($a) }
                            keys %{$self->{names}{$package}};
        my $rx = '^(' . join('|', map "\Q$_\E", @prefixes) . ')';

        $self->{rx}{$package} = qr/$rx/;
    }

    return $self;
}

sub map_sub {
    my ($self, $package, $name) = @_;
    return $name unless my $rx = $self->{rx}{$package};

    return $name =~ m{$rx} ? $self->{names}{$package}{$1} : $name;
}

sub map_eval_id {
    my ($self, $process_id, $ordinal, $eval_id) = @_;
    return "(eval $eval_id)" unless my $hash = $self->{source}->get_hash_by_name(
        $process_id, "(eval $eval_id)", # TODO add lookup by id
    );

    return "eval:$hash";
}

sub map_eval_name {
    my ($self, $process_id, $ordinal, $eval_name) = @_;
    return $eval_name unless my $hash = $self->{source}->get_hash_by_name(
        $process_id, $eval_name, # TODO add lookup by id
    );

    return "eval:$hash";
}

sub update_genealogy {
    my ($self, $process_id, $process_ordinal, $parent_id, $parent_ordinal) = @_;

    $self->{source} && $self->{source}->update_genealogy(
        $process_id, $process_ordinal, $parent_id, $parent_ordinal,
    );
}

sub can_map_eval { !!$_[0]->{source} }
sub can_map_sub  { !!$_[0]->{rx} }
sub can_map      { !!$_[0]->{rx} || !!$_[0]->{source} }

1;
