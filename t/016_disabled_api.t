#!/usr/bin/env perl

use t::lib::Test tests => 6;

use Devel::StatProfiler::Reader;
use Time::HiRes qw(usleep);

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }

use Devel::StatProfiler -template => $profile_file, '-nostart';

Devel::StatProfiler::write_custom_metadata("key", "value");
ok(1, "not crashed");

Devel::StatProfiler::start_section("section");
ok(1, "not crashed");

Devel::StatProfiler::end_section("some other section");
ok(1, "not crashed");

cmp_ok(Devel::StatProfiler::get_precision(), ">=", 0, "not crashed");

# retrurns true because it's using the trampoline
ok(Devel::StatProfiler::is_running(), "not crashed");

ok(!-f $profile_file, "did not create the profile file");


