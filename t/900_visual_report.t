#!/usr/bin/env perl

use t::lib::Test ':visual';
use t::lib::Slowops;

use Devel::StatProfiler::Report;
use Time::HiRes qw(time);
use Pod::Usage;

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }
my $output_dir = File::Spec->catdir(File::Basename::dirname($profile_file), 'report');

use Devel::StatProfiler -file => $profile_file, -interval => 1000;

use Test::Begin;

for (my $count = 10000; ; $count *= 2) {
    my $start = time;
    note("Trying with $count iterations");
    t::lib::Slowops::foo($count);
    -d '.' for 1..$count;
    last if time - $start >= 0.5;
}

Devel::StatProfiler::stop_profile();

my $r = Devel::StatProfiler::Report->new(
    slowops    => [qw(ftdir unstack)],
    flamegraph => 1,
    sources    => 1,
);
$r->add_trace_file($profile_file);

$r->output($output_dir);

pod2usage(-msg      => "Open the report at $output_dir with a browser, press return when finished",
          -verbose  => 99,
          -sections => ['MAIN PAGE', 'FILE PAGE'],
          -exitval  => 'NOEXIT');

readline(STDIN);

__END__

=head1 MAIN PAGE

=over 4

=item Subroutine and file list are sorted by exclusive sample count

=item Subroutine list contains opcodes, XSUBs and normal subs

=item In the flame graph, ftdir is reported as called by both main and foo()

=item Subroutine links work

=over 4

=item C<t::lib::Test::take_sample>

=item C<Time::HiRes::usleep>

=item C<CORE::ftdir>

=item C<Test::Begin::BEGIN>

=back

=item File links work

=item There is an "(unknown)" link for C<Time::HiRes> XSUBs

=item "All subs" link works

=back

=head1 FILE PAGE

Click F<Test.pm> report from the main page, scroll down to C<take_sample>

=over 4

=item Exclusive samples are close to 0, inclusive are not

=item Three callers and one callee are reported

=item Links to callers and callees work correctly

=back
