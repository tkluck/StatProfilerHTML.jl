#!/usr/bin/env perl

use t::lib::Test ':visual';

use Devel::StatProfiler::Report;
use Devel::StatProfiler::NameMap;
use Time::HiRes qw(usleep);

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }
my $output_dir = File::Spec->catdir(File::Basename::dirname($profile_file), 'report');

use Devel::StatProfiler -file => $profile_file, -interval => 1000, -source => 'traced_evals';

{
    no warnings 'redefine';
    eval <<'EOT' or die;
sub foo {
    usleep(50000);
}

foo();
EOT

    eval <<'EOT' or die;
sub foo {
    usleep(50000);
}

foo();
EOT

    eval <<'EOT' or die;
usleep(55000);
EOT

    eval <<'EOT' or die;
foo();
EOT

}

foo();
foo();

Devel::StatProfiler::write_inc_path;
Devel::StatProfiler::stop_profile();

my $r = Devel::StatProfiler::Report->new(
    mapper        => Devel::StatProfiler::NameMap->new(
        source => Devel::StatProfiler::EvalSource->new,
    ),
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

=item Subroutine, file list and flame graph contain only 3 eval entries

=item All lists contain the same eval entries

=item One of the 3 eval entries has roughly twice the samples as the others

=back

=head1 FILE PAGE

Click the eval entry with more samples

=over 4

=item Source code is

    sub foo {
        usleep(50000);
    }

    foo();

and the link points to the line with the sub C<foo> call

=item The first line lists two callers for the eval

=item Both C<eval> callers are the lines in main where the code is C<eval()>d

=item Sub C<foo> has four callers

=over 4

=item The current C<eval>, at line 5

=item A single-line C<eval>, at line 1

=item Two consecutive lines in the main file

=back

=back

Click the C<Time::HiRes::usleep> entry

=over 4

=item It has two callers

=item Sub C<foo> in the previously-examined file, at line 2

=item A single-line C<eval>, at line 1

=back
