#!/usr/bin/env perl
use t::lib::Test tests => 4;

use Devel::StatProfiler::Reader;

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }

use Devel::StatProfiler -file => $profile_file;
Devel::StatProfiler::write_custom_metadata(foo => "bar");
Devel::StatProfiler::write_custom_metadata(bar => 1);
Devel::StatProfiler::write_custom_metadata(foo => "baz");
Devel::StatProfiler::stop_profile();

my $r = Devel::StatProfiler::Reader->new($profile_file);
ok($r->get_format_version() >= 1, "format version >= 1");
ok(defined($r->get_source_tick_duration), "tick duration defined");
ok(defined($r->get_source_stack_sample_depth), "stack sample depth defined");

# Read all traces to build meta data hash
while (my $trace = $r->read_trace) { }

my $meta_data = $r->get_custom_metadata();
is_deeply($meta_data, {foo => "baz", bar => 1}, "Custom meta data comes out correctly");

