#!/usr/bin/env perl

use t::lib::Test;

use Devel::StatProfiler::Reader;

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }

use Devel::StatProfiler -file => $profile_file, -interval => 1000;
use Time::HiRes qw(usleep);

{
    package Tied;

    sub TIESCALAR {
        return bless \my $self, __PACKAGE__;
    }

    sub FETCH {
        return \&main::usleep;
    }
}

{
    package Overloaded;

    use overload '&{}' => \&_cv;

    sub new {
        return bless \my $self, __PACKAGE__;
    }

    sub _cv {
        return \&main::usleep;
    }
}

my ($l1, $l2, $l3, $l4, $l5);
my $ref = \&usleep;
my $overload = Overloaded->new;
my $tie;

# tries to exercise the major branches in get_cv_from_sv
tie $tie, 'Tied';
usleep(10000); BEGIN { $l1 = __LINE__ }
$ref->(10000); BEGIN { $l2 = __LINE__ }
{
    no strict 'refs';
    &{"usleep"}(10000); BEGIN { $l3 = __LINE__ }
}
$tie->(10000); BEGIN { $l4 = __LINE__ }
$overload->(10000); BEGIN { $l5 = __LINE__; }

Devel::StatProfiler::stop_profile();

my @samples = get_samples($profile_file);

my $xsub = bless {
    line          => -1,
    first_line    => -1,
    file          => '',
    package       => 'Time::HiRes',
    sub_name      => 'usleep',
    fq_sub_name   => 'Time::HiRes::usleep',
}, 'Devel::StatProfiler::StackFrame';

eq_or_diff($samples[0][0], $xsub);
is($samples[0][1]->line, $l1);
eq_or_diff($samples[1][0], $xsub);
is($samples[1][1]->line, $l2);
eq_or_diff($samples[2][0], $xsub);
is($samples[2][1]->line, $l3);
eq_or_diff($samples[3][0], $xsub);
is($samples[3][1]->line, $l4);
eq_or_diff($samples[4][0], $xsub);
is($samples[4][1]->line, $l5);

done_testing();
