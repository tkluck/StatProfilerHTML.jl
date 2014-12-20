#!/usr/bin/env perl

use t::lib::Test ':visual';
use t::lib::Slowops;

use Devel::StatProfiler::Report;
use Time::HiRes qw(time);

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }
my $output_dir = File::Spec->catdir(File::Basename::dirname($profile_file), 'report');

use Devel::StatProfiler -file => $profile_file, -interval => 1000;

use Test::Begin;

eval <<'EOT'; # extra __END__ token to check source code fetching
__END__
EOT

for (my $count = 10000; ; $count *= 2) {
    my $start = time;
    note("Trying with $count iterations");
    t::lib::Slowops::foo($count);
    -d '.' for 1..$count;
    last if time - $start >= 0.5;
}

Devel::StatProfiler::write_inc_path;
Devel::StatProfiler::stop_profile();

my $r = Devel::StatProfiler::Report->new(
    slowops    => [qw(ftdir unstack)],
    flamegraph => 1,
    sources    => 1,
);
$r->add_trace_file($profile_file);

$r->output($output_dir);

visual_test($output_dir, ['MAIN PAGE', 'FILE PAGE', 'FLAME GRAPH']);

__END__

=head1 MAIN PAGE

=over 4

=item Subroutine and file list are sorted by exclusive sample count

=item Subroutine list contains opcodes, XSUBs and normal subs

=item Subroutine links work

=over 4

=item C<t::lib::Test::take_sample>

The link points to the sub definition line, detailing number of
samples and list of callers.

=item C<Test::Begin::BEGIN>

The link points to the sub definition line, detailing number of
samples and list of callers.

=item C<Time::HiRes::usleep>

=item C<CORE::ftdir>

=back

=item File links work

=item There is an "(unknown)" link for C<Time::HiRes> XSUBs

=item "All subs" link works

=item "All files" link works

=back

=head1 FILE PAGE

Click F<Test.pm> report from the main page, scroll down to C<take_sample>

=over 4

=item Exclusive samples are close to 0, inclusive are not

=item Three callers and one callee are reported

=item Links to callers and callees work correctly

=back

Click F<t/900_visual_report.t> report from the main page

=over 4

=item Check the source code is not truncated after the C<eval>

=item Check the last line of the source code is the C<__END__> token

=back

=head1 FLAME GRAPH

=over 4

=item C<CORE::ftdir> is reported as called by both main and foo()

=item The flame graph contains a tile for C<t/900_visual_report.t:main>

=item The items in the flame graph are clickable (check the four subs above)

=back
