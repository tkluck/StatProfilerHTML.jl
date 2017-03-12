#!/usr/bin/env perl
use t::lib::Test;

use Devel::StatProfiler::EvalSourceStorage;
use Devel::StatProfiler::Utils qw(
    utf8_sha1_hex
);
use File::Glob qw(bsd_glob);

my $profile_dir;
BEGIN { ($profile_dir) = temp_profile_file(); }

my $storage1_dir = "$profile_dir/storage1";

mkdir $storage1_dir;
my $storage1 = Devel::StatProfiler::EvalSourceStorage->new(
    base_dir => $storage1_dir,
);

my %sources1;
for my $i (1 .. 20) {
    my $source = "$i" x 100_000;
    my $hash = utf8_sha1_hex($source);

    $sources1{$hash} = $source;
    $storage1->add_source_string($hash, $source);
}

{
    my $source = "....";
    my $hash = utf8_sha1_hex($source);

    $sources1{$hash} = $source;
    $storage1->add_source_string($hash, $source);
}

note("Check getting unpacked sources");
eq_or_diff(scalar @{$storage1->{pack_files}}, 0);
cmp_ok(scalar @{[bsd_glob("$storage1_dir/*")]}, '>=', 1);
for my $hash (sort keys %sources1) {
    eq_or_diff($storage1->get_source_by_hash($hash), $sources1{$hash});
}

note("Check getting packed sources");
$storage1->pack_files(1);
eq_or_diff(scalar @{$storage1->{pack_files}}, 0, 'manifest not loaded yet');
cmp_ok(scalar @{[bsd_glob("$storage1_dir/*")]}, '==', 1);

for my $hash (sort keys %sources1) {
    eq_or_diff($storage1->get_source_by_hash($hash), $sources1{$hash});
}

eq_or_diff(scalar @{$storage1->{pack_files}}, 2, 'manifest loaded');

done_testing();
