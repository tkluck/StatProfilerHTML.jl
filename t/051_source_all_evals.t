#!/usr/bin/env perl

use t::lib::Test;

use Devel::StatProfiler::Reader;

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }

use Devel::StatProfiler -file => $profile_file, -interval => 1000, -source => 'all_evals';

for (1..4) {
    eval "take_sample(); take_sample()";
    eval "Time::HiRes::sleep(0.000001)";
    eval "Time::HiRes::sleep(0.000001)";
}

Devel::StatProfiler::stop_profile();

my @samples = get_samples($profile_file);
my $source = get_sources($profile_file);
my %count;

is(@samples, 8);
cmp_ok(scalar keys %$source, '>=', 12);

for my $sample (@samples) {
    ok(exists $source->{$sample->[2]->file}, 'source code is there');
    like($source->{$sample->[2]->file}, qr/take_sample/, 'source code is legit');
}

$count{$_}++ for values %$source;

is_deeply(\%count, {
    'Time::HiRes::sleep(0.000001)' => 8,
    'take_sample(); take_sample()' => 4,
});

done_testing();
