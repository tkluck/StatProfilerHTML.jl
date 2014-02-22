#!/usr/bin/env perl

use t::lib::Test;

use Devel::StatProfiler::Aggregator;
use Time::HiRes qw(time);

my ($profile_dir, $template);
BEGIN { ($profile_dir, $template) = temp_profile_dir(); }

use Devel::StatProfiler -template => $template, -interval => 1000;

my @requests = qw(content index list detail);
my %handlers = (
    content => sub { take_sample() },
    index   => sub { take_sample() },
    list    => sub { take_sample() },
    detail  => sub { take_sample() },
);

for my $i (1..50) {
    my $request = $requests[rand @requests];

    Devel::StatProfiler::start_section('section');

    take_sample();
    $handlers{$request}->();

    Devel::StatProfiler::write_custom_metadata('key', $request);
    Devel::StatProfiler::end_section('section');
}

Devel::StatProfiler::stop_profile();

{
    package TestAggregator;

    use parent 'Devel::StatProfiler::Aggregator';

    sub handle_section_change {
        my ($self, $sc, $metadata) = @_;
        my $request = $metadata->{key} || 'unknown';

        $sc->clear_custom_metadata;
        if ($request eq 'content' || $request eq 'list') {
            return ['__main__', $request];
        } else {
            return ['__main__'];
        }
    }
}

my @files = glob "$template.*";

my ($main1, $content1, $list1) = map Devel::StatProfiler::Report->new, 1..3;
$main1->add_trace_file($_) for @files;
$content1->add_trace_file(t::lib::Test::FilteredReader->new($_, 'content')) for @files;
$list1->add_trace_file(t::lib::Test::FilteredReader->new($_, 'list')) for @files;
# no need to finalize the report for comparison

my $a1 = TestAggregator->new(
    root_directory => File::Spec::Functions::catdir($profile_dir, 'aggr1'),
);
for my $file (@files) {
    my $r = Devel::StatProfiler::Reader->new($file);
    for (;;) {
        my $sr = t::lib::Test::SingleReader->new($r);
        $a1->process_trace_files($sr);
        last if $sr->done;
    }
}
$a1->save;
my ($main2, $content2, $list2) = map $a1->merged_report($_), qw(
    __main__ content list
);
# no need to finalize the report for comparison

for my $file (@files) {
    my $r = Devel::StatProfiler::Reader->new($file);
    for (;;) {
        my $sr = t::lib::Test::SingleReader->new($r);
        my $a = TestAggregator->new(
            root_directory => File::Spec::Functions::catdir($profile_dir, 'aggr2'),
        );
        $a->load;
        $a->process_trace_files($sr);
        $a->save;
        last if $sr->done;
    }
}
my $a2 = Devel::StatProfiler::Aggregator->new(
    root_directory => File::Spec::Functions::catdir($profile_dir, 'aggr2'),
);
my ($main3, $content3, $list3) = map $a2->merged_report($_), qw(
    __main__ content list
);
# no need to finalize the report for comparison

eq_or_diff($main2, $main1);
eq_or_diff($content2, $content1);
eq_or_diff($list2, $list1);

eq_or_diff($main3, $main1);
eq_or_diff($content3, $content1);
eq_or_diff($list3, $list1);

done_testing();
