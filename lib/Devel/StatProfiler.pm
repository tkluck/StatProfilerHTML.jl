package Devel::StatProfiler;
# ABSTRACT: low-overhead sampling code profiler

use 5.14.0;
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
    -source   => 1,
    -maxsize  => 1,
);

my %source_args = (
    none                => 0,
    traced_evals        => 1,
    all_evals           => 2,
    all_evals_always    => 3,
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
        } elsif ($arg eq '-maxsize') {
            set_max_output_file_size($value);
        } elsif ($arg eq '-source') {
            _croak("Invalid value for -source option") unless exists $source_args{$value};
            set_save_source($source_args{$value});
        }
    }

    if (@exporter) {
        require Exporter;
        Exporter::export_to_level(__PACKAGE__, $package, @exporter);
    }

    _install();
}

sub _set_profiler_state {
    srand $_[0]; # the srand is replaced with runloop.cpp:set_profiler_state
}

sub disable_profile { _set_profiler_state(0) }
sub enable_profile  { _set_profiler_state(1) }
sub restart_profile { _set_profiler_state(2) }
sub stop_profile    { _set_profiler_state(3) }

sub save_source {
  my ($value) = @_;
  _croak("Invalid value for save_source option") unless exists $source_args{$value};
  set_save_source($source_args{$value});
}

sub guarded_section {
  my ($section_name) = @_;
  require Devel::StatProfiler::SectionGuard;
  return Devel::StatProfiler::SectionGuard->new(section_name => $section_name);
}

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

=head2 Options

Options can be passed either on the command line:

    perl -MDevel::StatProfiler=-interval,1000,-template,/tmp/profile/statprof.out

or by loading the profiler directly from the profiled program

   use Devel::StatProfiler -interval => 1000, -template => '/tmp/profile/statprof.out';

=head3 -template <path> (default: statprof.out)

Sets the base name used for the output file.  The full filename is
obtained by appending a dot followed by a random string to the
template path.  This ensures that subsequent profiler runs don't
overwrite the same output file.

=head3 -nostart

Don't start profiling when the module is loaded.  To start the profile
call C<enable_profile()>.

=head3 -interval <microsecs> (default 10000)

Sets the sampling interval, in microseconds.

=head3 -maxsize <size> (default 10MB)

After the trace file grows bigger than this size, start a new one with
a bigger ordinal.

=head3 -source <strategy> (default 'none')

Sets which source code is saved in the profile

=over 4

=item none

No source code is saved in the profile file.

=item traced_evals

Only the source code for eval()s that have at least one sample
B<during evaluation> is saved.  This does B<NOT> include eval()s that
define subroutines that are sampled after the eval() ends.

=item all_evals

The source code for all eval()s is saved in the profile file.

=item all_evals_always

The source code for all eval()s is saved in the profile file, even
when profiling is disabled.

=back

=head3 -depth <stack depth> (default 20)

Sets the maximum number of stack frames saved for each sample.

=head3 -file <path>

In general, using C<-template> above is the preferred option, since
C<-file> will not work when using C<fork()> or threads.

Sets the exact file path used for profile output file; if the file is
already present, it's overwritten.

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

=head2 changing profiler state

Calling C<enable_profile>, C<disable_profile>, C<restart_profile> and
C<stop_profile> from an inner runloop (including but not limited to
from C<use>, C<require>, C<sort> blocks, callbacks invoked from XS
code) can have confusing results: runloops started afterwards will
honor the new state, outer runloops will not.

Unfortunately there is no way to detect the situaltion at the moment.

=head2 source code and C<#line> directives

The parsing of C<#line> directive used to map logical lines to
physical lines uses heuristics, and they can obviously fail.

Files that contain C<#line> directives and have no samples taken in
the part of the file outside the part mapped by C<#line> directives
will not be found.

=head2 first line of subs

The first line of subs is found by searching for the sub definition in
the code. Needless to say, this is fragile.
