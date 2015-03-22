#!/usr/bin/env perl

use t::lib::Test;
use t::lib::Slowops;

use Devel::StatProfiler::Report;
use Time::HiRes qw(time);

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }

my $LONG_STR = " X" x 1000000;

use Devel::StatProfiler -file => $profile_file, -interval => 1000;
my ($l1);

for (my $count = precision_factor == 1 ? 10000 : 20000; ; $count *= 2) {
    my $start = time;
    note("Trying with $count iterations");
    t::lib::Slowops::foo($count);
    -d '.' && $LONG_STR =~ s/ $// for 1..$count; BEGIN { $l1 = __LINE__ + 0 }
    last if time - $start >= 0.5;
}

Devel::StatProfiler::stop_profile();

my $slowops_foo_line = 9;
my $r = Devel::StatProfiler::Report->new(
    slowops => [qw(ftdir subst)],
);
my $a = $r->{aggregate};
$r->add_trace_file($profile_file);
$r->finalize;

# sanity checking
ok($a->{subs}{__FILE__ . ':CORE::ftdir'});
ok($a->{subs}{__FILE__ . ':CORE::subst'});
ok($a->{subs}{'t/lib/Slowops.pm:CORE::ftdir'});
ok($a->{subs}{'t/lib/Slowops.pm:CORE::subst'});

### start checking we have one ftdir instance per file
my ($ftdir_main) = grep $_->{name} eq 'CORE::ftdir',
                   map  $a->{subs}{$_},
                        keys %{$a->{files}{+__FILE__}{subs}{-2}};
my ($ftdir_so)   = grep $_->{name} eq 'CORE::ftdir',
                   map  $a->{subs}{$_},
                        keys %{$a->{files}{'t/lib/Slowops.pm'}{subs}{-2}};

is($ftdir_main, $a->{subs}{__FILE__ . ':CORE::ftdir'});
is($ftdir_so,   $a->{subs}{'t/lib/Slowops.pm:CORE::ftdir'});
is($ftdir_main->{kind}, 2);
is($ftdir_so->{kind}, 2);
isnt($ftdir_main, $ftdir_so);

### end checking we have one ftdir instance per file
### start checking op-sub call sites

{
    my $cs = $ftdir_so->{call_sites}{"t/lib/Slowops.pm:$slowops_foo_line"};

    is($cs->{caller}, 't/lib/Slowops.pm:t::lib::Slowops::foo:' . $slowops_foo_line);
    is($cs->{file}, 't/lib/Slowops.pm');
    is($cs->{line}, $slowops_foo_line);
    is($cs->{inclusive}, $cs->{exclusive});
}

### end  checking op-sub call sites

done_testing();
