#!/usr/bin/env perl

use t::lib::Test ':visual';
use t::lib::Slowops;

use Devel::StatProfiler::Report;
use Time::HiRes qw(time);

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }
my $output_dir = File::Spec->catdir(File::Basename::dirname($profile_file), 'report');

use Devel::StatProfiler -file => $profile_file, -interval => 1000;

my $anon1 = sub {
    take_sample() for 1..10;
};

my $anon2 = sub {
    take_sample() for 1..30;
};

$anon1->();
$anon2->();

Devel::StatProfiler::stop_profile();

my $r = Devel::StatProfiler::Report->new(
    slowops    => [qw(ftdir unstack)],
    flamegraph => 1,
    sources    => 1,
);
$r->add_trace_file($profile_file);

$r->output($output_dir);

visual_test($output_dir, ['MAIN PAGE', 'FILE PAGE']);

__END__

=head1 MAIN PAGE

=over 4

=item Subroutine list and flame graph contain two C<__ANON__> entries

=item One of the two C<__ANON__> entries has roughly 3 times the
samples of the other

=item Subroutine links work

=back
