package Devel::StatProfiler;
# ABSTRACT: fill me in...

use strict;
use warnings;

use XSLoader;

# VERSION

XSLoader::load(__PACKAGE__);

my %args = (
    -interval => 1,
    -file     => 1,
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
            set_output_file($value);
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
