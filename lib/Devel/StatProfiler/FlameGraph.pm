package Devel::StatProfiler::FlameGraph;

use strict;
use warnings;

use File::ShareDir;
use File::Spec::Functions;
use IPC::Open3 ();
use Cwd ();
use Symbol ();

my @BASE_CMD = (
    $^X,
    File::ShareDir::dist_file('Devel-StatProfiler', 'flamegraph.pl'),
    '--nametype=sub',
    '--countname=samples',
);

sub write_attributes {
    my ($class, $file, $attributes, $zoomable) = @_;

    open my $fh, '>', $file or die "Unable to open '$file': $!";
    for my $sub (keys %$attributes) {
        my $attrs = $attributes->{$sub};

        print $fh join(
            "\t",
            $sub,
            map("$_=$attrs->{$_}",
                $zoomable ? (grep $_ ne 'href', keys %$attrs) :
                            (keys %$attrs)),
        ), "\n";
    }
    close $fh or die "Unable to close '$file': $!"
}

sub new {
    my ($class, %opts) = @_;
    my $self = bless {
        directory   => $opts{directory},
        traces      => $opts{traces},
        output      => $opts{output},
        attributes  => $opts{attributes},
        args        => $opts{extra_args},
        stderr      => undef,
    }, $class;

    return $self;
}

sub start {
    my ($self) = @_;
    my $cwd = Cwd::cwd;

    chdir $self->{directory};
    (my $stdin, $self->{stderr}) = map Symbol::gensym, 1 .. 2;
    open my $stdout, '>', $self->{output} or die "Error opening '", $self->flamegraph, "': $!";
    local *FLAMES = $stdout;
    $self->{pid} = IPC::Open3::open3(
        $stdin, ">&FLAMES", $self->{stderr},
        @BASE_CMD,
        map("--$_=$self->{args}{$_}", keys %{$self->{args}}),
        "--nameattr=$self->{attributes}",
        $self->{traces},
    );
    chdir $cwd;
}

sub wait {
    my ($self) = @_;

    if (waitpid($self->{pid}, 0) != $self->{pid}) {
        die "Generating ", $self->flamegraph, " failed:\n", $self->_errors;
    } elsif ($? != 0) {
        die "Generating ", $self->flamegraph, " failed\n", $self->_errors;;
    }
}

sub flamegraph {
    my ($self) = @_;

    return File::Spec::Functions::catfile($self->{directory}, $self->{output});
}

sub flamegraph_base {
    my ($self) = @_;

    return $self->{output};
}

sub all_files {
    my ($self) = @_;

    return [
        map File::Spec::Functions::catfile($self->{directory}, $_),
            $self->{output}, $self->{traces}, $self->{attributes},
    ];
}

sub _errors {
    my ($self) = @_;

    return $self->{errors} //= do {
        local $/;
        $self->{stderr} ? readline $self->{stderr} :
                          "Command was not run";
    };
}

1;
