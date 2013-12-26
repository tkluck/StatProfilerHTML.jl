package Devel::StatProfiler::Report;

use strict;
use warnings;
use autodie qw(open close mkdir);

use Devel::StatProfiler::Reader;
use File::ShareDir;
use File::Basename ();
use File::Spec::Functions ();
use File::Which;
use File::Copy ();
use Template::Perlish;

sub new {
    my ($class, %opts) = @_;
    my $self = bless {
        aggregate     => {
            total     => 0,
            subs      => {},
            flames    => {},
            files     => {},
        },
        templates     => {
            file      => _get_template('file.tmpl'),
            subs      => _get_template('subs.tmpl'),
            index     => _get_template('index.tmpl'),
        },
        flamegraph    => $opts{flamegraph} || 0,
        tick          => 1000, # TODO get from profile files
    }, $class;

    if ($self->{flamegraph}) {
        my $fg = File::Which::which('flamegraph') // File::Which::which('flamegraph.pl');
        die "Unable to find flamegraph executable, please install NYTProf"
            unless $fg;
        $self->{fg_cmd} = "$fg --nametype=sub --countname=microseconds";
    }

    return $self;
}

sub _get_template {
    my ($basename) = @_;
    my $path = File::ShareDir::dist_file('Devel-StatProfiler', $basename);
    my $tp = Template::Perlish->new;
    my $tmpl;

    {
        local $/;
        open my $fh, '<', $path;
        $tmpl = <$fh>;
    }

    my $sub = $tp->compile_as_sub($tmpl);

    die "Error while compiling '$basename'" unless $sub;

    return $sub;
}

sub _write_template {
    my ($self, $sub, $data, $dir, $file) = @_;
    my $text = $sub->($data);

    open my $fh, '>', File::Spec::Functions::catfile($dir, $file);
    print $fh $text;
    close $fh;
}

sub add_trace_file {
    my ($self, $file) = @_;
    my $r = Devel::StatProfiler::Reader->new($file);
    my $subs = $self->{aggregate}{subs};
    my $flames = $self->{flamegraph} ? $self->{aggregate}{flames} : undef;

    # TODO handle metadata, die if inconsistent

    while (my $trace = $r->read_trace) {
        my $weight = $trace->weight;

        $self->{aggregate}{total} += $weight;

        my $frames = $trace->frames;

        for my $i (0 .. $#$frames) {
            my $frame = $frames->[$i];
            my $name = $frame->subroutine || $frame->file . ':main';
            my $line = $frame->line;
            my $sub = $subs->{$name} ||= {
                name       => $name,
                file       => $frame->file,
                inclusive  => 0,
                exclusive  => 0,
                lines      => {},
                start_line => $line,
            };

            $sub->{start_line} = $line if $sub->{start_line} > $line;
            $sub->{inclusive} += $weight;
            $sub->{lines}{inclusive}{$line} += $weight;

            if (!$i) {
                $sub->{exclusive} += $weight;
                $sub->{lines}{exclusive}{$line} += $weight;
            }

            # TODO aggregate opcodes
        }

        if ($flames) {
            my $key = join ';', map { $_->subroutine || 'MAIN' } reverse @$frames;

            $flames->{$key} += $weight;
        }
    }
}

sub _fileify {
    my ($name) = @_;

    (my $base = File::Basename::basename($name)) =~ s/\W+/-/g;

    return $base;
}

sub _finalize {
    my ($self) = @_;
    my %files;

    my $ordinal = 0;
    for my $sub (sort { $a->{file} cmp $b->{file} }
                      values %{$self->{aggregate}{subs}}) {
        my ($exclusive, $inclusive) = @{$sub->{lines}}{qw(exclusive inclusive)};
        my $entry = $files{$sub->{file}} ||= {
            name      => $sub->{file},
            basename  => File::Basename::basename($sub->{file}),
            report    => sprintf('%s-%d-line.html', _fileify($sub->{file}), ++$ordinal),
            lines     => {
                exclusive       => [],
                inclusive       => [],
            },
            exclusive => 0,
        };

        $entry->{exclusive} += $sub->{exclusive};
        push @{$entry->{subs}}, $sub;

        for my $line (keys %$exclusive) {
            $entry->{lines}{exclusive}[$line] += $exclusive->{$line};
        }

        for my $line (keys %$inclusive) {
            $entry->{lines}{inclusive}[$line] += $inclusive->{$line};
        }
    }

    $self->{aggregate}{files} = \%files;
}

sub _fetch_source {
    my ($self, $path) = @_;
    my @lines;

    open my $fh, '<', $path;
    while (defined (my $line = <$fh>)) {
        # this might match a token inside a string, and does not match
        # the token on a non-empty line; probably it should double-check
        # using the range of lines with samples
        last if $line =~ /^__(?:DATA|END)__\s+$/;
        push @lines, $line;
    }

    return ['I hope you never see this...', @lines];
}

sub output {
    my ($self, $directory) = @_;

    mkdir $directory unless -d $directory;

    $self->_finalize;
    my $files = $self->{aggregate}{files};
    my @subs = sort { $b->{exclusive} <=> $a->{exclusive} }
                    values %{$self->{aggregate}{subs}};

    my $sub_link = sub {
        my ($sub) = @_;

        return sprintf '%s#L%d',
            $self->{aggregate}{files}{$sub->{file}}{report},
            $sub->{start_line};
    };

    # format files
    for my $file (keys %$files) {
        my $entry = $files->{$file};
        my $code = $self->_fetch_source($file);

        my %file_data = (
            name        => $entry->{name},
            lines       => $code,
            exclusive   => $entry->{lines}{exclusive},
            inclusive   => $entry->{lines}{inclusive},
        );

        $self->_write_template($self->{templates}{file}, \%file_data,
                               $directory, $entry->{report});
    }

    # format flame graph
    my $flamegraph_link;
    if ($self->{flamegraph}) {
        $flamegraph_link = 'all_stacks_by_time.svg';

        my $flames = $self->{aggregate}{flames};
        my $calls_data = File::Spec::Functions::catfile($directory, 'all_stacks_by_time.calls');
        my $calls_svg = File::Spec::Functions::catfile($directory, $flamegraph_link);

        open my $calls_fh, '>', $calls_data;
        for my $key (keys %$flames) {
            print $calls_fh $key, ' ', $flames->{$key}, "\n";
        }
        close $calls_fh;

        # TODO links --nameattr=$subattr
        my $fg_factor = 1000000 / $self->{tick};
        system("$self->{fg_cmd} --factor=$fg_factor --total=$self->{aggregate}{total} $calls_data > $calls_svg") == 0
            or die "Generating $calls_svg failed\n";
    }

    # format subs page
    my %subs_data = (
        subs            => \@subs,
        sub_link        => $sub_link,
    );

    $self->_write_template($self->{templates}{subs}, \%subs_data,
                           $directory, 'subs.html');

    # format index page
    my %main_data = (
        files           => [sort { $b->{exclusive} <=> $a->{exclusive} }
                                 values %$files],
        subs            => \@subs,
        flamegraph      => $flamegraph_link,
        sub_link        => $sub_link,
    );

    $self->_write_template($self->{templates}{index}, \%main_data,
                           $directory, 'index.html');

    # copy CSS
    File::Copy::copy(
        File::ShareDir::dist_file('Devel-StatProfiler', 'statprofiler.css'),
        File::Spec::Functions::catfile($directory, 'statprofiler.css'));
}

1;
