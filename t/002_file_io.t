#!/usr/bin/env perl
use t::lib::Test;

use Devel::StatProfiler::Reader;
use Time::HiRes qw(usleep);

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }
my $src = "# " . ("FILLER " x 100000) . "\n" . "usleep(1000) for 1..10;\n";

use Devel::StatProfiler -file => $profile_file, -interval => 1000, -source => 'all_evals';

usleep(1000) for 1..10; # 10ms
Devel::StatProfiler::write_custom_metadata(foo => "bar");
SCOPE: {
  my $section = Devel::StatProfiler::guarded_section("MySection");
  isa_ok($section, "Devel::StatProfiler::SectionGuard");
  usleep(1000) for 1..10; # 10ms
  my $section2 = Devel::StatProfiler::guarded_section("MySection2");
  isa_ok($section2, "Devel::StatProfiler::SectionGuard");
  Devel::StatProfiler::write_custom_metadata(bar => 1);
  usleep(1000) for 1..10; # 10ms
}
eval $src;
Devel::StatProfiler::write_custom_metadata(foo => "baz");
usleep(1000*10) for 1..10; # 100ms
Devel::StatProfiler::stop_profile();

my $r = Devel::StatProfiler::Reader->new($profile_file);
ok($r->get_format_version() >= 1, "format version >= 1");
ok(defined($r->get_source_tick_duration), "tick duration defined");
ok(defined($r->get_source_stack_sample_depth), "stack sample depth defined");

# Read all traces to build meta data hash
my $expected_final_meta = {foo => "baz", bar => 1};
my %incr_meta;
my %valid_sections = qw(MySection 1 MySection2 1);
my $any_sections = 0;
while (my $trace = $r->read_trace) {
    my $meta = $trace->{metadata};
    if ($meta) {
        $incr_meta{$_} = $meta->{$_} for keys %$meta;
    }
    my $sections = $trace->{active_sections};
    is(ref($sections), "HASH", "active_sections is hash");
    if (keys %$sections) {
      is(scalar(grep exists($valid_sections{$_}), keys %$sections),
         scalar(keys %$sections), "Found sections and sections are recognized");
      $any_sections = 1;
    }
}
is($any_sections, 1, "Found sections in output");
is_deeply(\%incr_meta, $expected_final_meta, "Incremental meta data parsing works");

my $meta_data = $r->get_custom_metadata();
is_deeply($meta_data, $expected_final_meta, "Complete custom meta data comes out correctly");

my $sources = $r->get_source_code;
cmp_ok(scalar keys %$sources, '>=', 1, 'got some eval source code');
ok((grep $_ eq $src, values %$sources), 'got the source code for long eval');

done_testing();
