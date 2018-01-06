#!/usr/bin/env perl
# PODNAME: statprofilehtml
# ABSTRACT: generate Devel::StatProfiler HTML report

use 5.12.0;
use warnings;

BEGIN {
    die "Please pass the share directory as the first argument" unless @ARGV == 1;
    $Devel::StatProfiler::SHARE_DIR = shift @ARGV;
}

use Devel::StatProfiler::Report;
use Devel::StatProfiler::Reader;
use Devel::StatProfiler::Reader::Text;

my $outdir = 'statprof';

my $report = Devel::StatProfiler::Report->new(
    flamegraph      => 1,
    sources         => 1,
    mixed_process   => 1,
);

my $r = Devel::StatProfiler::Reader::Text->new(\*STDIN);
$report->add_trace_file($r);

my $diagnostics = $report->output($outdir);

for my $diagnostic (@$diagnostics) {
    print STDERR $diagnostic, "\n";
}

package Devel::StatProfiler;

our $SHARE_DIR;
