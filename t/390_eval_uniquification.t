#!/usr/bin/env perl

use t::lib::Test;

use Devel::StatProfiler::Report;
use Time::HiRes qw(usleep);
use Storable;

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }

use Devel::StatProfiler -file => $profile_file, -interval => 1000;

my $first_eval_name = eval "sub f { (caller 0)[1] } f()";
my ($first_eval_n) = $first_eval_name =~ /^\(eval (\d+)\)$/;

sub _e { sprintf '(eval %d)', $_[0] }

sub bar {
    usleep(50000);
}

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
}

bar();

Devel::StatProfiler::stop_profile();

my $r1 = Devel::StatProfiler::Report->new(
    sources       => 1,
    flamegraph    => 1,
);
$r1->add_trace_file($profile_file);
# no need to finalize the report for comparison

my $r2 = Storable::dclone($r1);
$r2->map_source;

my $a1 = $r1->{aggregate};
my $a2 = $r2->{aggregate};

## test files

{
    my $f1 = $a1->{files};
    my $f2 = $a2->{files};

    my $f1e1 = $f1->{_e($first_eval_n + 1)};
    my $f1e2 = $f1->{_e($first_eval_n + 2)};
    my $f2e1 = $f2->{'eval:61da06e799e66a5e0a0240bf058e28bd8c8322c8'};

    is($f1e1->{name}, _e($first_eval_n + 1));
    is($f1e2->{name}, _e($first_eval_n + 2));
    ok($f2e1->{name} eq _e($first_eval_n + 1) ||
       $f2e1->{name} eq _e($first_eval_n + 2));

    for my $i (0 .. 5) {
        is($f2e1->{lines}{inclusive}[$i] // 0,
           ($f1e1->{lines}{inclusive}[$i] // 0) + ($f1e2->{lines}{inclusive}[$i] // 0));
    }
}

## test subs

{
    my $s1 = $a1->{subs};
    my $s2 = $a2->{subs};

    my $s1e1foo = $s1->{_e($first_eval_n + 1) . ':main::foo:2'};
    my $s1e2foo = $s1->{_e($first_eval_n + 2) . ':main::foo:2'};
    my $s2e1foo = $s2->{'eval:61da06e799e66a5e0a0240bf058e28bd8c8322c8:main::foo:2'};

    is($s2e1foo->{exclusive}, $s1e1foo->{exclusive} + $s1e2foo->{exclusive});
    is($s2e1foo->{inclusive}, $s1e1foo->{inclusive} + $s1e2foo->{inclusive});

    {
        my $s1cs1 = $s1e1foo->{call_sites}{_e($first_eval_n + 1) . ':5'};
        my $s1cs2 = $s1e2foo->{call_sites}{_e($first_eval_n + 2) . ':5'};
        my $s2cs = $s2e1foo->{call_sites}{'eval:61da06e799e66a5e0a0240bf058e28bd8c8322c8:5'};

        is($s2cs->{caller}, 'eval:61da06e799e66a5e0a0240bf058e28bd8c8322c8:eval');
        is($s2cs->{file}, 'eval:61da06e799e66a5e0a0240bf058e28bd8c8322c8');
        is($s2cs->{inclusive}, $s1cs1->{inclusive} + $s1cs2->{inclusive});
        is($s2cs->{exclusive}, $s1cs1->{exclusive} + $s1cs2->{exclusive});
   }

    {
        my $s1c1 = $s1e1foo->{callees}{2}{'(unknown):Time::HiRes::usleep'};
        my $s1c2 = $s1e2foo->{callees}{2}{'(unknown):Time::HiRes::usleep'};
        my $s2c = $s2e1foo->{callees}{2}{'(unknown):Time::HiRes::usleep'};

        is($s2c->{inclusive}, $s1c1->{inclusive} + $s1c2->{inclusive});
   }
}

{
    my $s1 = $a1->{subs};
    my $s2 = $a2->{subs};

    my $s1e1foo = $s1->{_e($first_eval_n + 1) . ':eval'};
    my $s1e2foo = $s1->{_e($first_eval_n + 2) . ':eval'};
    my $s2e1foo = $s2->{'eval:61da06e799e66a5e0a0240bf058e28bd8c8322c8:eval'};

    is($s2e1foo->{exclusive}, $s1e1foo->{exclusive} + $s1e2foo->{exclusive});
    is($s2e1foo->{inclusive}, $s1e1foo->{inclusive} + $s1e2foo->{inclusive});

    ok($s1e1foo->{call_sites}{'t/390_eval_uniquification.t:25'});
    ok($s1e2foo->{call_sites}{'t/390_eval_uniquification.t:33'});
    eq_or_diff($s2e1foo->{call_sites}{'t/390_eval_uniquification.t:25'},
               $s1e1foo->{call_sites}{'t/390_eval_uniquification.t:25'});
    eq_or_diff($s2e1foo->{call_sites}{'t/390_eval_uniquification.t:33'},
               $s1e2foo->{call_sites}{'t/390_eval_uniquification.t:33'});

    {
        my $s1c1 = $s1e1foo->{callees}{5}{_e($first_eval_n + 1) . ':main::foo:2'};
        my $s1c2 = $s1e2foo->{callees}{5}{_e($first_eval_n + 2) . ':main::foo:2'};
        my $s2c = $s2e1foo->{callees}{5}{'eval:61da06e799e66a5e0a0240bf058e28bd8c8322c8:main::foo:2'};

        is($s2c->{callee}, 'eval:61da06e799e66a5e0a0240bf058e28bd8c8322c8:main::foo:2');
        is($s2c->{inclusive}, $s1c1->{inclusive} + $s1c2->{inclusive});
    }
}

## test file_map

{
    my $f1 = $a1->{file_map};
    my $f2 = $a2->{file_map};

    is(scalar keys %{$f1->{main}}, 3);
    is(scalar keys %{$f2->{main}}, 2);

    is($f2->{main}{'eval:61da06e799e66a5e0a0240bf058e28bd8c8322c8'},
       $f1->{main}{_e($first_eval_n + 1)} + $f1->{main}{_e($first_eval_n + 2)});
}

done_testing();
