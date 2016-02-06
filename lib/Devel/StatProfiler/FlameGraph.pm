package Devel::StatProfiler::FlameGraph;

use strict;
use warnings;

use File::ShareDir;
use File::Spec::Functions;
use Cwd ();

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
    }, $class;

    return $self;
}

sub start {
    my ($self) = @_;
    my $cwd = Cwd::cwd;
    my $args = join " ", map "--$_=$self->{args}{$_}", keys %{$self->{args}};

    chdir $self->{directory};
    system("@BASE_CMD $args --nameattr=$self->{attributes} $self->{traces} > $self->{output}") == 0
        or die "Generating ", $self->flamegraph, " failed\n";
    chdir $cwd;
}

sub wait {
    my ($self) = @_;

    return;
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

1;
