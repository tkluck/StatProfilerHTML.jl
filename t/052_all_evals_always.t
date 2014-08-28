#!/usr/bin/env perl

use t::lib::Test;

use Devel::StatProfiler::Reader;

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }

use Devel::StatProfiler -file => $profile_file, -interval => 1000, -source => 'all_evals_always', '-nostart';

my $first_eval_name = eval "sub f { (caller 0)[1] } f()";
my ($first_eval_n) = $first_eval_name =~ /^\(eval (\d+)\)$/;

sub _e { sprintf '(eval %d)', $_[0] }

for (1..4) {
    eval "take_sample(); take_sample()";
    eval "Time::HiRes::sleep(0.000001)";
    eval "Time::HiRes::sleep(0.000001)";
}

my $eval_with_hash_line = <<EOT;
#line 123 "eval string with #line directive"
1;
EOT

eval $eval_with_hash_line;

Devel::StatProfiler::stop_profile(); # closes the trace file

my $source = get_sources($profile_file);
my %count;

cmp_ok(scalar keys %$source, '>=', 12);

my @strange = grep !/^\(eval \d+\)$/, keys %$source;

ok(!@strange, "found unusual file names for eval");
diag("Strange eval source '$_'") for @strange;

$count{$_}++ for values %$source;

is_deeply(\%count, {
    'Time::HiRes::sleep(0.000001)' => 8,
    'take_sample(); take_sample()' => 4,
    $eval_with_hash_line           => 1,
    'sub f { (caller 0)[1] } f()'  => 1,
});

# check source is associated with the correct (eval ...) string
is($source->{_e($first_eval_n     )}, 'sub f { (caller 0)[1] } f()');
is($source->{_e($first_eval_n + 10)}, 'take_sample(); take_sample()');
is($source->{_e($first_eval_n + 11)}, 'Time::HiRes::sleep(0.000001)');
is($source->{_e($first_eval_n + 12)}, 'Time::HiRes::sleep(0.000001)');
is($source->{_e($first_eval_n + 13)}, $eval_with_hash_line);

done_testing();
