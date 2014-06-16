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

my ($meta, $r);

for my $profile_file (@files) {
    $r = Devel::StatProfiler::Reader->new($profile_file);

    while (my $trace = $r->read_trace) {
        ok(!$r->is_stream_ended, 'stream has not ended yet (file not ended)');
        if ($trace->metadata_changed) {
            if (!$meta) {
                $meta = $trace->metadata;
            } else {
                die "Causal failure: multiple metadata changes"
            }
        }
    }

    ok($r->is_file_ended, 'file has ended now (end of any file)');
    if ($profile_file eq $files[-1]) {
        ok($r->is_stream_ended, 'stream has ended now (end of last file)');
    } else {
        ok(!$r->is_stream_ended, 'stream has not ended yet (end of intermediate file)');
    }
}

eq_or_diff($meta, { foo => 'bar' });

done_testing();
