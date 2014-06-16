#!/usr/bin/env perl
use t::lib::Test;

use Devel::StatProfiler::Reader;
use Time::HiRes qw(usleep);

my ($profile_dir, $template);
BEGIN { ($profile_dir, $template) = temp_profile_dir(); }

use Devel::StatProfiler -template => $template, -interval => 1000, -source => 'all_evals', -maxsize => 300;

for (1..10) {
  usleep(10000); # 10ms
  Devel::StatProfiler::write_custom_metadata(foo => "bar") if $_ == 3;
}

Devel::StatProfiler::stop_profile();

my @files = glob "$template.*";

cmp_ok(scalar @files, '>', 1, 'got more than one trace file');

my $meta;

for my $profile_file (@files) {
    my $r = Devel::StatProfiler::Reader->new($profile_file);

    while (my $trace = $r->read_trace) {
        if ($trace->metadata_changed) {
            if (!$meta) {
                $meta = $trace->metadata;
            } else {
                die "Causal failure: multiple metadata changes"
            }
        }
    }
}

eq_or_diff($meta, { foo => 'bar' });

done_testing();
