package Module::Build::StatProfiler;

use strict;
use warnings;
use parent qw(Module::Build::WithXSpp);

use Getopt::Long;
use Config;

# yes, doing this in a module is ugly; OTOH it's a private module
GetOptions(
    'g'         => \my $DEBUG,
);

die "OS unsupported"
    unless $^O eq 'linux' ||
           $^O eq 'darwin' ||
           $^O eq 'MSWin32';

sub new {
    my ($class, %args) = @_;
    my $debug_flag = $DEBUG ? ' -g' : '';
    my @extra_libs;

    if ($^O eq 'linux') {
        @extra_libs = qw(-lrt);
    } elsif ($^O eq 'MSWin32') {
        if ($DEBUG) {
            # TODO add the MSVC equivalent
            my ($ccflags, $lddlflags, $optimize) = map {
                s{(^|\s)-s(\s|$)}{$1$2}r
            } @Config{qw(ccflags lddlflags optimize)};

            $args{config} = {
                ccflags     => $ccflags,
                lddlflags   => $lddlflags,
                optimize    => $optimize,
            };
        }
    }

    return $class->SUPER::new(
        %args,
        share_dir          => 'share',
        extra_compiler_flags => '-DSNAPPY=1 -DPERL_NO_GET_CONTEXT' . $debug_flag,
        extra_linker_flags => [@extra_libs],
    );
}

sub _run_benchmark {
    my ($self, $name, $script) = @_;
    my $prof = '-MDevel::StatProfiler=-template,benchmarks/output/bench.out';
    my $base = "$prof,-nostart";

    my $args = $self->args;
    my @results;
    for my $params (['prof', $prof], ['base', $base]) {
        my $bench = Dumbbench->new(
            initial_runs         => $args->{"initial-runs"} || 35,
            target_rel_precision => $args->{"rel-precision"} || 0.002,
            verbosity            => $args->{"bench-verbosity"} || 0,
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

    my $opt = $self->args();
    my $freq_pinner;
    local $SIG{INT} = $SIG{INT};
    local $SIG{TERM} = $SIG{TERM};
    if ($opt->{"pin-frequency"}) {
        print "Pinning CPU frequency to lowest possible speed for benchmark.\n";
        require Dumbbench::CPUFrequencyPinner;
        $freq_pinner = Dumbbench::CPUFrequencyPinner->new;
        $SIG{INT} = $SIG{TERM} = sub {undef $freq_pinner; exit};
        $freq_pinner->set_max_frequencies($freq_pinner->min_frequencies->[0]);
    }
    my @results;
    my @benchmarks = (
        [ 'shardedkv', 'ShardedKV' ],
        qw(fibonacci hashsum subsum),
    );
  BENCH: for my $item (@benchmarks) {
        my $benchmark = $item;
        if (ref $item) {
            $benchmark = $item->[0];
            for my $req (@{$item}[1..$#$item]) {
                eval "require $req; 1" or do {
                    print "Skipping $benchmark due to missing $req\n";
                    next BENCH;
                }
            }
        }
        print "Running $benchmark benchmark\n";
        push @results, $self->_run_benchmark($benchmark, "benchmarks/$benchmark.pl");
    }
    undef $freq_pinner;

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

sub ACTION_cdriver {
    my ($self) = @_;
    my $cbuilder = $self->cbuilder;
    my $expected_exe = "t/callsv$Config{_exe}";

    return if -f $expected_exe;

    $self->add_to_cleanup('t/xsinit.c', $expected_exe);

    require ExtUtils::Embed;

    ExtUtils::Embed::xsinit('t/xsinit.c', '-std');

    my $driver = $cbuilder->compile(source => 't/driver.c');
    my $xsinit = $cbuilder->compile(source => 't/xsinit.c');
    my $exe = $cbuilder->link_executable(
        exe_file           => $expected_exe,
        objects            => [$driver, $xsinit],
        extra_linker_flags => ExtUtils::Embed::ldopts(),
    );

    $self->add_to_cleanup($driver, $xsinit);
}

sub ACTION_test {
    my ($self) = @_;

    $self->depends_on('cdriver');
    $self->SUPER::ACTION_test;
}

1;
