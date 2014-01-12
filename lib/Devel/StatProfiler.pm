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
    -depth    => 1,
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
        } elsif ($arg eq '-depth') {
            set_stack_collection_depth($value);
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

=head1 CAVEATS

=head2 goto &subroutine

With a sampling profiler there is no reliable way to track the C<goto
&foo> construct, hence the profile data for this code

    sub foo {
        # 100 milliseconds of computation
    }

    sub bar {
        # 100 milliseconds of computation, then
        goto &foo;
    }

    bar() for 1..100000; # foo.pl, line 10

will report that the code at F<foo.pl> line 10 has spent approximately
the same time in calling C<foo> and C<bar>, and will report C<foo> as
being called from the main program rather than from C<bar>.

=head2 XSUBs with callbacks

Since XSUBs don't have a Perl-level stack frame, Perl code called from
XSUBs is reported as if called from the source line calling the XSUB.

Additionally, the exclusive time for the XSUB incorrectly includes the
time spent in callbacks.

=head2 XSUBs and overload

If an object has an overloaded C<&{}> operator (code dereference)
returning an XSUB as the code reference, the overload might be called
twice in some situations.
