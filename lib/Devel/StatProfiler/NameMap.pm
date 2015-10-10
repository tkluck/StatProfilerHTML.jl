package Devel::StatProfiler::NameMap;

use strict;
use warnings;

sub new {
    my ($class, %opts) = @_;
    my $self = bless {
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

sub can_map_sub  { !!$_[0]->{rx} }

1;
