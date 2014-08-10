#!/usr/bin/env perl

use t::lib::Test ':visual';

use Devel::StatProfiler::Report;
use Time::HiRes qw(usleep);
use Pod::Usage;

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }
my $output_dir = File::Spec->catdir(File::Basename::dirname($profile_file), 'report');

use Devel::StatProfiler -file => $profile_file, -interval => 1000;

eval sprintf <<'EOT',
usleep(50000);

sub foo {
    usleep(50000);
}

foo();
%s#line 400 "inside the eval"%s
usleep(50000);

sub bar {
    usleep(50000);
}

bar();
EOT
    ("\n" x 40) x 2;

use Test::LineMap;

Devel::StatProfiler::stop_profile();

my $r = Devel::StatProfiler::Report->new(
    slowops    => [qw(ftdir unstack)],
    flamegraph => 1,
    sources    => 1,
);
$r->add_trace_file($profile_file);
$r->_file('t/lib/Test/LineMap.pm'); # ensure we read the file
$r->map_source;

$r->output($output_dir);

pod2usage(-msg      => "Open the report at $output_dir with a browser, press return when finished",
          -verbose  => 99,
          -sections => ['MAIN PAGE', 'FILE PAGE'],
          -exitval  => 'NOEXIT');

readline(STDIN);

__END__

=head1 MAIN PAGE

=over 4

=item Subroutine and file list contain entries for

=over 4

=item A string eval (pointing to a 100-line file, mostly empty)

=item "Inside the eval" (pointing to the same file above)

=item one-file.pm, other-file.pm, pointing to F<t/lib/Test/LineMap.pm>

=back

=back

=head1 FILE PAGE

Click C<main::foo> report from the main page

=over 4

=item It links to a line near the top of a ~100 lines file

=item There is a single caller, and the link points to the same file

=item Scrolling down there is a C<#line> directive and after that line numbers change

=back

Click C<main::bar> report from the main page

=over 4

=item It links to a line near the bottom of a ~100 lines file

=item The line number is around 400

=item There is a single caller, and the link points to the same file

=back

Click F<one-file.pm> report in the file list

=over 4

=item The link works and the lines with samples match the C<usleep()> calls

=back

=back
