#!/usr/bin/env perl

use t::lib::Test;

use Devel::StatProfiler::Report;
use Time::HiRes qw(time);

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }

use Devel::StatProfiler -file => $profile_file, -interval => 1000;
my ($l1, $l2, $l3, $l4);

my $count;
for ($count = 1000; ; $count *= 2) {
    my $start = time;
    note("Trying with $count iterations");
    1 for 1..$count;
    last if time - $start >= 0.3;
}

sub foo {
    if ($_[0] == 0) {
        1 for 1..$count; BEGIN { $l1 = __LINE__ + 0 }
        return 1;
    } else {
        return foo($_[0] - 1) + 1; BEGIN { $l2 = __LINE__ + 0 }
    }
}

sub bar {
    foo($_[0]); BEGIN { $l3 = __LINE__ + 0 }
}

bar(5);
foo(5); BEGIN { $l4 = __LINE__ + 0 }

Devel::StatProfiler::stop_profile();

my $take_sample_line = $t::lib::Test::TAKE_SAMPLE_LINE;
my $r = Devel::StatProfiler::Report->new(flamegraph => 1);
my $a = $r->{aggregate};
$r->add_trace_file($profile_file);

# sanity checking
cmp_ok($a->{files}{+__FILE__}{lines}{exclusive}[$l1] // 0, '>=', 600);
cmp_ok($a->{files}{+__FILE__}{lines}{exclusive}[$l2] // 0, '<=', 50);
cmp_ok($a->{files}{+__FILE__}{lines}{exclusive}[$l3] // 0, '<=', 50);
cmp_ok($a->{files}{+__FILE__}{lines}{exclusive}[$l4] // 0, '<=', 50);

cmp_ok($a->{files}{+__FILE__}{lines}{inclusive}[$l1] // 0, '>=', 600);
cmp_ok($a->{files}{+__FILE__}{lines}{inclusive}[$l2] // 0, '>=', 600);
cmp_ok($a->{files}{+__FILE__}{lines}{inclusive}[$l3] // 0, '>=', 300);
cmp_ok($a->{files}{+__FILE__}{lines}{inclusive}[$l4] // 0, '>=', 300);

# actual test
sub cmp_range {
    my ($min, $value, $max) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;
    cmp_ok($value, '<=', $max);
    cmp_ok($value, '>=', $min);
}

my $foo_n = 't/302_report_recursive.t:main::foo:23';
my $bar_n = 't/302_report_recursive.t:main::bar:32';
my $foo = $a->{subs}{$foo_n};
my $bar = $a->{subs}{$bar_n};

cmp_ok($bar->{exclusive}, '<=', 50);
cmp_range(300, $bar->{inclusive}, 600);
cmp_range(300, $bar->{callees}{32}{$foo_n}{inclusive}, 600);

cmp_range(600, $foo->{exclusive}, 1000);
cmp_range(600, $foo->{inclusive}, 1000);
cmp_range(600, $foo->{callees}{27}{$foo_n}{inclusive}, 1000);
cmp_range(600, $foo->{call_sites}{'t/302_report_recursive.t:27'}{inclusive}, 1000);
cmp_range(300, $foo->{call_sites}{'t/302_report_recursive.t:32'}{inclusive}, 600);
cmp_range(300, $foo->{call_sites}{'t/302_report_recursive.t:36'}{inclusive}, 600);

done_testing();
