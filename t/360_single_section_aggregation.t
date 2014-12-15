#!/usr/bin/env perl

use t::lib::Test;

use Devel::StatProfiler::Aggregator;
use Time::HiRes qw(time);

my ($profile_dir, $template);
BEGIN { ($profile_dir, $template) = temp_profile_dir(); }

use Devel::StatProfiler -template => $template, -interval => 1000;

my (@m, $h);
my @requests = qw(content index list detail);
BEGIN { $h = __LINE__ + 2 }
my %handlers = (
    content => sub { take_sample() },
    index   => sub { take_sample() },
    list    => sub { take_sample() },
    detail  => sub { take_sample() },
);

Devel::StatProfiler::write_custom_metadata('release', '1.3');
Devel::StatProfiler::write_custom_metadata('release_date', '2013-07-03');

for my $i (1..50) {
    my $request = $requests[rand @requests];

    Devel::StatProfiler::start_section('section');

    if ($request eq 'content') {
        $h = $h; # to force Perl into creating an extra nextstate
        take_sample(); BEGIN { $m[0] = __LINE__ }
    } elsif ($request eq 'index') {
        $h = $h; # to force Perl into creating an extra nextstate
        take_sample(); BEGIN { $m[1] = __LINE__ }
    } elsif ($request eq 'list') {
        $h = $h; # to force Perl into creating an extra nextstate
        take_sample(); BEGIN { $m[2] = __LINE__ }
    } elsif ($request eq 'detail') {
        $h = $h; # to force Perl into creating an extra nextstate
        take_sample(); BEGIN { $m[3] = __LINE__ }
    }
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

        $sc->delete_custom_metadata(['key']);
        if ($request eq 'content' || $request eq 'list') {
            return ['__main__', $request], {
                release         => $metadata->{release},
            };
        } else {
            return ['__main__'], {
                release         => $metadata->{release},
                release_date    => $metadata->{release_date},
            };
        }
    }
}

my @files = glob "$template.*";
my $process_id;

my ($main1, $content1, $list1) = map Devel::StatProfiler::Report->new(mixed_process => 1), 1..3;
$main1->add_trace_file($_) for @files;
$content1->add_trace_file(t::lib::Test::FilteredReader->new($_, 'content')) for @files;
$list1->add_trace_file(t::lib::Test::FilteredReader->new($_, 'list')) for @files;

$main1->add_metadata({release_date => '2013-07-03'});
$_->add_metadata({release => '1.3'}) for $main1, $content1, $list1;
$_->add_metadata({tag => 'test-1.3'}) for $main1, $content1, $list1;
# no need to finalize the report for comparison

my $a1 = TestAggregator->new(
    root_directory => File::Spec::Functions::catdir($profile_dir, 'aggr1'),
    shard          => 'shard1',
);
$a1->add_global_metadata({tag => 'test-1.3'});
for my $file (@files) {
    my $r = Devel::StatProfiler::Reader->new($file);
    ($process_id) = @{$r->get_genealogy_info};
    for (;;) {
        my $sr = t::lib::Test::SingleReader->new($r);
        $a1->process_trace_files($sr);
        last if $sr->done;
    }
}
$a1->save_part;
my ($main2, $content2, $list2) = map $a1->merge_report($_), qw(
    __main__ content list
);
# no need to finalize the report for comparison

for my $file (@files) {
    my $r = Devel::StatProfiler::Reader->new($file);
    for (;;) {
        my $sr = t::lib::Test::SingleReader->new($r);
        my $a = TestAggregator->new(
            root_directory => File::Spec::Functions::catdir($profile_dir, 'aggr2'),
            shard          => 'shard1',
        );
        $a->add_global_metadata({tag => 'test-1.3'});
        $a->load;
        $a->process_trace_files($sr);
        $a->save_part;
        last if $sr->done;
    }
}
my $a2 = Devel::StatProfiler::Aggregator->new(
    root_directory => File::Spec::Functions::catdir($profile_dir, 'aggr2'),
    shard          => 'shard1',
);
my ($main3, $content3, $list3) = map $a2->merge_report($_), qw(
    __main__ content list
);
# no need to finalize the report for comparison

# we test source code in another test
delete @{$_}{qw(source sourcemap genealogy root_dir shard)}, delete @{$_->{metadata}}{qw(shard root_dir)}
    for $main1, $content1, $list1,
        $main2, $content2, $list2,
        $main3, $content3, $list3;

# Storable and number stringification
numify($_)
    for $main1, $content1, $list1,
        $main2, $content2, $list2,
        $main3, $content3, $list3;

eq_or_diff($main2, $main1);
eq_or_diff($content2, $content1);
eq_or_diff($list2, $list1);

eq_or_diff($main3, $main1);
eq_or_diff($content3, $content1);
eq_or_diff($list3, $list1);

for my $main ($main1, $main2, $main3) {
    eq_or_diff($main->metadata, {
        tag             => 'test-1.3',
        release         => '1.3',
        release_date    => '2013-07-03'
    });
}

for my $content ($content1, $content2, $content3) {
    my $lines = $content->{aggregate}{files}{+__FILE__}{lines}{inclusive};

    for my $i (0 .. 3) {
        if ($i == 0) {
            ok($lines->[$h + $i], "sample for $requests[$i] handler is there");
            ok($lines->[$m[$i]], "sample for $requests[$i] caller is there");
        } else {
            ok(!$lines->[$h + $i], "sample for $requests[$i] handler is not there");
            ok(!$lines->[$m[$i]], "sample for $requests[$i] caller is not there");
        }
    }

    eq_or_diff($content->metadata, {
        tag             => 'test-1.3',
        release         => '1.3',
    });
}

for my $content ($list1, $list2, $list3) {
    my $lines = $content->{aggregate}{files}{+__FILE__}{lines}{inclusive};

    for my $i (0 .. 3) {
        if ($i == 2) {
            ok($lines->[$h + $i], "sample for $requests[$i] handler is there");
            ok($lines->[$m[$i]], "sample for $requests[$i] caller is there");
        } else {
            ok(!$lines->[$h + $i], "sample for $requests[$i] handler is not there");
            ok(!$lines->[$m[$i]], "sample for $requests[$i] caller is not there");
        }
    }

    eq_or_diff($content->metadata, {
        tag             => 'test-1.3',
        release         => '1.3',
    });
}

done_testing();
