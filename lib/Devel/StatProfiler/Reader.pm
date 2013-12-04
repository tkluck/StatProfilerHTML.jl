package Devel::StatProfiler::Reader;

use strict;
use warnings;
use autodie qw(open);

sub new {
    my ($class, $path) = @_;
    open my $fh, '<', $path;

    return bless { fh => $fh }, $class;
}

sub read_trace {
    my ($self) = @_;
    my $line = readline $self->{fh};

    return unless defined $line;

    chomp $line;
    my ($weight, @frames) = split /;/, $line;
    my $frames = [map {
        my ($type, $sub, $file, $line) = split /,/, $_;

        bless {
            subroutine => $sub,
            file       => $file,
            line       => $line,
        }, 'Devel::StatProfiler::StackFrame';
    } @frames];

    return bless {
        weight => $weight,
        frames => $frames,
    }, 'Devel::StatProfiler::StackTrace';
}

package Devel::StatProfiler::StackFrame;

sub subroutine { $_[0]->{subroutine} }
sub file { $_[0]->{file} }
sub line { $_[0]->{line} }

package Devel::StatProfiler::StackTrace;

sub weight { $_[0]->{weight} }
sub frames { $_[0]->{frames} }

1;
