package Devel::StatProfiler::Reader;
# ABSTRACT: read profiler output

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
    my $topmost_op = pop @frames;

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
        op_name => $topmost_op,
    }, 'Devel::StatProfiler::StackTrace';
}

package Devel::StatProfiler::StackFrame;

sub id { $_[0]->{id} }
sub subroutine { $_[0]->{subroutine} }
sub file { $_[0]->{file} }
sub line { $_[0]->{line} }
sub kind { $_[0]->{line} == -2 ? 2 :
           $_[0]->{line} == -1 ? 1 :
                                 0 }

package Devel::StatProfiler::StackTrace;

sub weight { $_[0]->{weight} }
sub frames { $_[0]->{frames} }
sub op_name { $_[0]->{op_name} }

1;
