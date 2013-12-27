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
use Scalar::Util ();
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

sub _call_site_id {
    my ($frame) = @_;

    return sprintf '%s:%d', $frame->file, $frame->line;
}

sub _sub_id {
    my ($sub) = @_;

    return sprintf '%s:%s', $sub->{name}, $sub->{file};
}

sub _sub {
    my ($self, $frame) = @_;
    my $name = $frame->subroutine || $frame->file . ':main';

    return $self->{aggregate}{subs}{$name} ||= {
        name       => $name,
        file       => $frame->file,
        inclusive  => 0,
        exclusive  => 0,
        lines      => {},
        call_sites => {},
        start_line => $frame->line,
    };
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
            my $line = $frame->line;
            my $sub = $self->_sub($frame);

            $sub->{start_line} = $line if $sub->{start_line} > $line;
            $sub->{inclusive} += $weight;
            $sub->{lines}{inclusive}{$line} += $weight;

            if ($i != $#$frames) {
                my $call_site = $frames->[$i + 1];
                my $caller = $self->_sub($call_site);
                my $site = $sub->{call_sites}{_call_site_id($call_site)} ||= {
                    caller    => $caller,
                    exclusive => 0,
                    inclusive => 0,
                    file      => $call_site->file,
                    line      => $call_site->line,
                };
                Scalar::Util::weaken($site->{caller}) unless $site->{inclusive};

                $site->{inclusive} += $weight;
                $site->{exclusive} += $weight if !$i;

                my $callee = $caller->{lines}{callees}{$call_site->line}{_sub_id($caller)} ||= {
                    callee    => $sub,
                    inclusive => 0,
                };
                Scalar::Util::weaken($callee->{callee}) unless $callee->{inclusive};

                $callee->{inclusive} += $weight;
            }

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
        my ($exclusive, $inclusive, $callees) = @{$sub->{lines}}{qw(exclusive inclusive callees)};
        my $entry = $files{$sub->{file}} ||= {
            name      => $sub->{file},
            basename  => File::Basename::basename($sub->{file}),
            report    => sprintf('%s-%d-line.html', _fileify($sub->{file}), ++$ordinal),
            lines     => {
                exclusive       => [],
                inclusive       => [],
                callees         => {},
            },
            exclusive => 0,
            subs      => {},
        };

        $entry->{exclusive} += $sub->{exclusive};
        push @{$entry->{subs}{$sub->{start_line}}}, $sub;

        for my $line (keys %$exclusive) {
            $entry->{lines}{exclusive}[$line] += $exclusive->{$line};
        }

        for my $line (keys %$inclusive) {
            $entry->{lines}{inclusive}[$line] += $inclusive->{$line};
        }

        for my $line (keys %$callees) {
            push @{$entry->{lines}{callees}{$line}}, values %{$callees->{$line}};
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

    my $file_link = sub {
        my ($file, $line) = @_;

        return sprintf '%s#L%d',
            $self->{aggregate}{files}{$file}{report},
            $line;
    };

    # format files
    for my $file (keys %$files) {
        my $entry = $files->{$file};
        my $code = $self->_fetch_source($file);

        my %file_data = (
            name        => $entry->{name},
            lines       => $code,
            subs        => $entry->{subs},
            exclusive   => $entry->{lines}{exclusive},
            inclusive   => $entry->{lines}{inclusive},
            callees     => $entry->{lines}{callees},
            sub_link    => $sub_link,
            file_link   => $file_link,
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
