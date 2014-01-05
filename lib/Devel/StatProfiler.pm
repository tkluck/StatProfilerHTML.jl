package Devel::StatProfiler;
# ABSTRACT: low-overhead sampling code profiler

use strict;
use warnings;

use XSLoader;

# VERSION

XSLoader::load(__PACKAGE__);

my %args = (
    -interval => 1,
    -file     => 1,
    -template => 1,
    -nostart  => 0,
);

sub _croak {
    require Carp;
    goto &Carp::croak;
}

sub import {
    my ($package, @args) = @_;
    my @exporter;

    while (my $arg = shift @args) {
        my $value;

        if ($arg !~ /^-/) {
            push @exporter, $arg;
            next;
        } elsif (!exists $args{$arg}) {
            _croak("Invalid option '$arg'");
        } elsif ($args{$arg}) {
            _croak("Option '$arg' requires a value") unless @args;
            $value = shift @args;
        }

        if ($arg eq '-interval') {
            set_sampling_interval($value);
        } elsif ($arg eq '-file') {
            set_output_file($value, 0);
        } elsif ($arg eq '-template') {
            set_output_file($value, 1);
        } elsif ($arg eq '-nostart') {
            set_enabled(0);
        }
    }

    if (@exporter) {
        require Exporter;
        Exporter::export_to_level(__PACKAGE__, $package, @exporter);
    }

    _install();
}

sub _set_profiler_state {
    srand $_[0]; # the srand is replaced with runloop.c:switch_runloop
}

sub disable_profile { _set_profiler_state(0) }
sub enable_profile  { _set_profiler_state(1) }
sub restart_profile { _set_profiler_state(2) }
sub stop_profile    { _set_profiler_state(3) }

1;

__END__

=head1 SYNOPSIS

  # profile (needs multiple runs, with representative data/distribution!)
  perl -MDevel::StatProfiler foo.pl input1.txt
  perl -MDevel::StatProfiler foo.pl input2.txt
  perl -MDevel::StatProfiler foo.pl input3.txt
  perl -MDevel::StatProfiler foo.pl input1.txt

  # prepare a report from profile data
  statprofilehtml

=head1 DESCRIPTION

Devel::StatProfiler is a sampling (or statistical) code profiler.

Rather than measuring the exact time spent in a statement (or
subroutine), the profiler interrupts the program at fixed intervals
(10 milliseconds by default) and takes a stack trace.  Given a
sufficient number of samples this provides a good indication of where
the program is spending time and has a relatively low overhead (around
3-5% increased runtime).
