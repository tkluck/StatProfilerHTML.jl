#!/usr/bin/env perl

use t::lib::Test ':fork', tests => 15;

use Devel::StatProfiler::Reader;
use Time::HiRes qw(usleep);

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }

use Devel::StatProfiler -template => $profile_file, -interval => 1000;
my ($l1, $l2, $l3);

usleep(50000); BEGIN { $l1 = __LINE__ }

Devel::StatProfiler::stop_profile();
my @first = grep !/_$/, glob $profile_file . '*';

usleep(50000); BEGIN { $l2 = __LINE__ }

Devel::StatProfiler::enable_profile();

usleep(50000); BEGIN { $l3 = __LINE__ }

Devel::StatProfiler::stop_profile();
my @second = grep !/_$/, glob $profile_file . '*';

is(scalar @first, 1);
is(scalar @second, 2);

my ($first) = @first;
my ($second) = _set_diff(\@second, \@first);
my @files = ($first, $second);

is(scalar @files, 2, 'wrote a new trace file after each start');
my (@sleep_patterns, @genealogies);

for my $file (@files) {
    my $r = Devel::StatProfiler::Reader->new($file);
    my %sleep_pattern;

    while (my $trace = $r->read_trace) {
        my $frames = $trace->frames;

        for my $frame (grep $_->file =~ /017_stop_start/, @$frames) {
            $sleep_pattern{$frame->line} += $trace->weight;
        }
    }

    push @sleep_patterns, \%sleep_pattern;
    push @genealogies, $r->get_genealogy_info;
}

# first
ok( exists $sleep_patterns[0]{$l1});
ok(!exists $sleep_patterns[0]{$l2});
ok(!exists $sleep_patterns[0]{$l3});
is($genealogies[0][2], "00" x 24);
is($genealogies[0][3], 0);

# second
ok(!exists $sleep_patterns[1]{$l1});
ok(!exists $sleep_patterns[1]{$l2});
ok( exists $sleep_patterns[1]{$l3});
is($genealogies[1][2], $genealogies[0][0]);
is($genealogies[1][3], 1);

# sanity
isnt($genealogies[0][0], $genealogies[1][0]);
isnt($genealogies[0][0], $genealogies[2][0]);

sub _set_diff {
    my ($a, $b) = @_;
    my %a;

    @a{@$a} = ();

    delete $a{$_} for @$b;

    return keys %a;
}
