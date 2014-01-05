package Module::Build::StatProfiler;

use strict;
use warnings;
use parent qw(Module::Build::WithXSpp);

sub new {
    my ($class, %args) = @_;

    return $class->SUPER::new(
        %args,
        share_dir          => 'share',
        extra_linker_flags => [qw(-lrt)],
    );
}

sub _run_benchmark {
    my ($self, $name, $script) = @_;
    my $prof = '-MDevel::StatProfiler=-template,benchmarks/output/bench.out';
    my $base = "$prof,-nostart";

    my @results;
    for my $params (['prof', $prof], ['base', $base]) {
        my $bench = Dumbbench->new(
            initial_runs         => 35,
            target_rel_precision => 0.002,
            verbosity            => 0,
        );

        $bench->add_instances(
            Dumbbench::Instance::Cmd->new(
                name      => "$name-$params->[0]",
                command   => [$^X, '-Mblib', $params->[1], $script],
            ),
        );

        $bench->run;
        $bench->report;

        push @results, $bench->instances;
    }

    return @results;
}

sub ACTION_benchmark {
    my ($self) = @_;

    if (!eval 'require Dumbbench; 1') {
        print "Please install Dumbbench\n";
        exit 1;
    }
    $self->depends_on('build');

    my @results;
    for my $benchmark (qw(shardedkv fibonacci hashsum subsum)) {
        print "Running $benchmark benchmark\n";
        push @results, $self->_run_benchmark($benchmark, "benchmarks/$benchmark.pl");
    }

    my (%summary);
    for my $instance (@results) {
        my ($name, $type) = split /-/, $instance->name, 2;

        $summary{$name}{$type} = $instance->result;
    }

    print "\n";

    for my $name (sort keys %summary) {
        my $ratio = $summary{$name}{prof} / $summary{$name}{base} * 100;

        printf "%s: %.02f%% +/- %.02f%% slowdown\n",
               $name,
               $ratio->number - 100, $ratio->error->[0];
    }
}

1;
