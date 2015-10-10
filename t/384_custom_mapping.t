#!/usr/bin/env perl

use t::lib::Test;

use Devel::StatProfiler::Aggregator;
use Devel::StatProfiler::NameMap;
use Time::HiRes qw(usleep);

my ($profile_dir, $template);
BEGIN { ($profile_dir, $template) = temp_profile_dir(); }

use Devel::StatProfiler -template => $template, -interval => 1000, -source => 'all_evals';

# the original example used Sub::Name, but this is close enough
#line 15
sub foo_1 { take_sample() }
#line 15
sub foo_2 { take_sample() }
#line 15
sub foo_3 { take_sample() }

#line 22
sub bar {
    take_sample();
}

foo_1();
foo_2();
foo_3();
bar();

Devel::StatProfiler::stop_profile();

my ($profile_file) = glob "$template.*";

my $r1 = Devel::StatProfiler::Report->new(sources => 1);
$r1->add_trace_file($profile_file);
my $a1 = $r1->{aggregate};

my $map = Devel::StatProfiler::NameMap->new(
    names => {
        'main' => {
            'bar'   => 'foo',
            'foo_'  => 'foo_*',
        },
    },
);
my $r2 = Devel::StatProfiler::Report->new(sources => 1, mapper => $map);
$r2->add_trace_file($profile_file);
my $a2 = $r2->{aggregate};

my $main1 = $a1->{files}{'t/384_custom_mapping.t'};
my $main2 = $a2->{files}{'t/384_custom_mapping.t'};

# per-file subs
eq_or_diff($main1->{subs}{15}, {
    't/384_custom_mapping.t:main::foo_3:15' => undef,
    't/384_custom_mapping.t:main::foo_1:15' => undef,
    't/384_custom_mapping.t:main::foo_2:15' => undef,
});
eq_or_diff($main2->{subs}{15}, {
    't/384_custom_mapping.t:main::foo_*:15' => undef,
});

eq_or_diff($main1->{subs}{23}, {
    't/384_custom_mapping.t:main::bar:23' => undef,
});
eq_or_diff($main2->{subs}{23}, {
    't/384_custom_mapping.t:main::foo:23' => undef,
});

# subs
ok(exists $a1->{subs}{'t/384_custom_mapping.t:main::foo_1:15'});
ok(exists $a1->{subs}{'t/384_custom_mapping.t:main::foo_2:15'});
ok(exists $a1->{subs}{'t/384_custom_mapping.t:main::foo_3:15'});
ok(exists $a1->{subs}{'t/384_custom_mapping.t:main::bar:23'});

ok(exists $a2->{subs}{'t/384_custom_mapping.t:main::foo_*:15'});
ok(exists $a2->{subs}{'t/384_custom_mapping.t:main::foo:23'});

# callees
my $inclusive_main_foo_3 = $a1->{subs}{'t/384_custom_mapping.t:main'}{callees}{28}{'t/384_custom_mapping.t:main::foo_3:15'}{inclusive};

eq_or_diff($a1->{subs}{'t/384_custom_mapping.t:main'}{callees}{28}, {
    't/384_custom_mapping.t:main::foo_3:15' => {
        'inclusive' => $inclusive_main_foo_3,
        'callee'    => 't/384_custom_mapping.t:main::foo_3:15',
    },
});

eq_or_diff($a2->{subs}{'t/384_custom_mapping.t:main'}{callees}{28}, {
    't/384_custom_mapping.t:main::foo_*:15' => {
        'inclusive' => $inclusive_main_foo_3,
        'callee'    => 't/384_custom_mapping.t:main::foo_*:15',
    },
});

# call sites
eq_or_diff([sort keys %{$a1->{subs}{'t/384_custom_mapping.t:main::foo_3:15'}{call_sites}}], [
    't/384_custom_mapping.t:28',
]);

eq_or_diff([sort keys %{$a2->{subs}{'t/384_custom_mapping.t:main::foo_*:15'}{call_sites}}], [
    't/384_custom_mapping.t:26',
    't/384_custom_mapping.t:27',
    't/384_custom_mapping.t:28',
]);

done_testing();
