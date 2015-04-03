#!/usr/bin/env perl

use t::lib::Test;

use Devel::StatProfiler::Reader;

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }

use Devel::StatProfiler -file => $profile_file, -interval => 1000, -source => 'traced_evals';

my $first_eval_name = eval "take_sample(); sub f { (caller 0)[1] } f()";
my ($first_eval_n) = $first_eval_name =~ /^\(eval (\d+)\)$/;

sub _e { sprintf '(eval %d)', $_[0] }

for (1..4) {
    eval "take_sample(); take_sample();";
    eval "Time::HiRes::sleep(0.000001);";
    eval "Time::HiRes::sleep(0.000001);";
}

Time::HiRes::sleep(0.040); # make "sure" the sample is taken here
eval "# I am not traced";

my $eval_with_hash_line = <<EOT;
#line 123 "eval string with #line directive"
take_sample();
1;
EOT

eval $eval_with_hash_line;

Devel::StatProfiler::stop_profile();

my @samples = get_samples($profile_file);
my $source = get_sources($profile_file);

cmp_ok(scalar @samples, '>=', 8);
cmp_ok(scalar keys %$source, '>=', 4);
cmp_ok(scalar keys %$source, '<=', 8);

for my $sample (@samples) {
    my $file = $sample->[2]->file;

    $file = _e($first_eval_n + 14)
        if $file =~ /eval string with #line directive/;

    ok(exists $source->{$file}, 'source code is there');
    like($source->{$file}, qr/take_sample/, 'source code is legit');
}

ok(!grep /# I am not traced/, values %$source);
ok(!exists $source->{'eval string with #line directive'});
like($source->{_e($first_eval_n + 14)}, 
     qr/^#line 123 "eval string with #line directive"$/m);

done_testing();
