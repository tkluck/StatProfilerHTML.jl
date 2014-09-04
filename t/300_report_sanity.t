#!/usr/bin/env perl

use t::lib::Test;

use Devel::StatProfiler::Report;

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }

use Devel::StatProfiler -file => $profile_file, -interval => 1000;
my ($foo, $l1, $l2, $l3);

BEGIN { Time::HiRes::sleep(0.05); }

{
    package X;

    $foo = sub {
        main::take_sample(); BEGIN { $l1 = __LINE__ + 0 }
    };
}

sub Moo::bar {
    take_sample(); BEGIN { $l2 = __LINE__ + 0 }
}

sub foo {
    take_sample(); BEGIN { $l3 = __LINE__ + 0 }
}

foo();
Moo::bar();
$foo->();

Devel::StatProfiler::stop_profile();

my $take_sample_line = $t::lib::Test::TAKE_SAMPLE_LINE;
my $r = Devel::StatProfiler::Report->new(flamegraph => 1);
my $a = $r->{aggregate};
$r->add_trace_file($profile_file);
$r->finalize;

# sanity checking
my %file_map = map { $_ => [keys $a->{file_map}{$_}] }
                   qw(main X Moo t::lib::Test);
eq_or_diff(\%file_map, {
    'main'         => [__FILE__],
    'X'            => [__FILE__],
    'Moo'          => [__FILE__],
    't::lib::Test' => ['t/lib/Test.pm'],
});
eq_or_diff([sort grep !m{^/}, keys $a->{files}],
           ['', __FILE__, 't/lib/Test.pm']);

### start setup

# Time::HiRes
my $time_hires = $a->{files}{''};
my ($usleep) = grep $_->{name} eq 'Time::HiRes::usleep',
                    @{$time_hires->{subs}{-1}};

# current file
my $me = $a->{files}{__FILE__ . ''};
my $moo = $me->{subs}{$l2}[0];
use Data::Dumper;
my ($main) = grep $_->{package} eq '',
             map  @$_,
                  values %{$me->{subs}};

# t/lib/Test.pm
my $test_pm = $a->{files}{'t/lib/Test.pm'};
my $take_sample = $test_pm->{subs}{$take_sample_line}[0];

### end setup
### start all subroutines

# subroutine map
is($a->{subs}{__FILE__ . ':Moo::bar'}, $moo);
is($a->{subs}{'(unknown):Time::HiRes::usleep'}, $usleep);
is($a->{subs}{'t/lib/Test.pm:t::lib::Test::take_sample'}, $take_sample);
is($a->{subs}{__FILE__ . ':main'}, $main);

### end all subroutines
### start subroutine attributes

# Time::HiRes basic attributes
is($usleep->{name}, 'Time::HiRes::usleep');
is($usleep->{package}, 'Time::HiRes');
is($usleep->{start_line}, -1);
is($usleep->{kind}, 1);
is($usleep->{file}, '');
cmp_ok($usleep->{exclusive}, '>=', 20 / precision_factor);
cmp_ok($usleep->{inclusive}, '==', $usleep->{exclusive});

# the only usleep call site is from take_sample
eq_or_diff([sort keys %{$usleep->{call_sites}}], ["t/lib/Test.pm:$take_sample_line"]);
{
    my $cs = $usleep->{call_sites}{"t/lib/Test.pm:$take_sample_line"};
    is($cs->{caller}, $take_sample->{uq_name});
    is($cs->{exclusive}, $usleep->{exclusive});
    is($cs->{inclusive}, $usleep->{inclusive});
    is($cs->{file}, 't/lib/Test.pm');
    is($cs->{line}, $take_sample_line);
}

# take_sample basic attributes
is($take_sample->{name}, 't::lib::Test::take_sample');
is($take_sample->{package}, 't::lib::Test');
is($take_sample->{start_line}, $take_sample_line);
is($take_sample->{kind}, 0);
is($take_sample->{file}, 't/lib/Test.pm');
cmp_ok($take_sample->{exclusive}, '<', 10 / precision_factor);
cmp_ok($take_sample->{inclusive}, '>=', 20 / precision_factor);

# three call sites for take_sample
eq_or_diff([sort keys %{$take_sample->{call_sites}}],
           [map __FILE__ . ':' . $_, ($l1, $l2, $l3)]);

# Moo::bar call site for take_sample
{
    my $cs = $take_sample->{call_sites}{__FILE__ . ':' . $l2};
    is($cs->{caller}, $moo->{uq_name});
    cmp_ok($cs->{exclusive}, '<=', 5 / precision_factor);
    cmp_ok($cs->{inclusive}, '>=', 5 / precision_factor);
    is($cs->{file}, __FILE__);
    is($cs->{line}, $l2);
}

### end subroutine attributes
### start file attributes

# t/lib/Test.pm
is($test_pm->{name}, 't/lib/Test.pm');
is($test_pm->{basename}, 'Test.pm');
is($test_pm->{report}, 'Test-pm-b9b148b22b2161075314-line.html');
cmp_ok($test_pm->{exclusive}, '<=', 5 / precision_factor);
# WTF cmp_ok($test_pm->{inclusive}, '>=', 20);
cmp_ok($test_pm->{lines}{inclusive}[$take_sample_line], '>=', 20 / precision_factor);

# callees
{
    my $ca = $test_pm->{lines}{callees}{$take_sample_line}[0];

    cmp_ok($ca->{inclusive}, '>=', 20 / precision_factor);
    # WTF cmp_ok($ca->{esclusive}, '<=', 5);
    is($ca->{callee}, $usleep->{uq_name});
}

#subs
is($test_pm->{subs}{$take_sample_line}[0], $take_sample);

### end file attributes

### start flamegraph

my @traces = qw(
    MAIN;main::foo;t::lib::Test::take_sample;Time::HiRes::usleep
    MAIN;X::__ANON__;t::lib::Test::take_sample;Time::HiRes::usleep
    main::BEGIN;Time::HiRes::sleep
    MAIN;Moo::bar;t::lib::Test::take_sample;Time::HiRes::usleep
);

for my $trace (@traces) {
    ok(exists $a->{flames}{$trace});
}

### end flamegraph

done_testing();
