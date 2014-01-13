package Devel::StatProfiler::Report;
# ABSTRACT: process profiler output to generate a report

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
            file_map  => {},
        },
        templates     => {
            file      => _get_template('file.tmpl'),
            subs      => _get_template('subs.tmpl'),
            index     => _get_template('index.tmpl'),
        },
        flamegraph    => $opts{flamegraph} || 0,
        slowops       => {map { $_ => 1 } @{$opts{slowops} || []}},
        tick          => 0,
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
    my ($sub, $file) = ($frame->subroutine, $frame->file);
    my $name = $sub || $file . ':main';
    my $id = $frame->id || $name;

    # count the number of subroutines of a certain package defined per
    # file, used as an heuristic for where to display xsub time
    if ($sub && $file) {
        # TODO in the binary format there should be a 'package' accessor
        my ($package) = $sub =~ m{^(.*)::[^:]+};

        $self->{aggregate}{file_map}{$package}{$file}++;
    }

    return $self->{aggregate}{subs}{$id} ||= {
        name       => $name,
        file       => $file,
        inclusive  => 0,
        exclusive  => 0,
        lines      => {},
        call_sites => {},
        start_line => $frame->line,
        kind       => $frame->kind,
    };
}

sub add_trace_file {
    my ($self, $file) = @_;
    my $r = Devel::StatProfiler::Reader->new($file);
    my $flames = $self->{flamegraph} ? $self->{aggregate}{flames} : undef;
    my $slowops = $self->{slowops};

    if ($self->{tick} == 0) {
        $self->{tick} = $r->get_source_tick_duration;
        $self->{stack_depth} = $r->get_source_stack_sample_depth;
        $self->{perl_version} = $r->get_source_perl_version;
    } else {
        my $tick = $r->get_source_tick_duration;
        my $depth = $r->get_source_stack_sample_depth;
        my $perl_version = $r->get_source_perl_version;

        if ($tick != $self->{tick} ||
                $depth != $self->{stack_depth} ||
                $perl_version != $self->{perl_version}) {
            die <<EOT;
Inconsistent sampling parameters:
Current tick duration: $self->{tick} stack sample depth: $self->{stack_depth} Perl version: $self->{perl_version}

$file sampling parameters:
Tick duration: $tick stack sample depth: $depth Perl version: $perl_version
EOT
        }
    }

    while (my $trace = $r->read_trace) {
        my $weight = $trace->weight;

        $self->{aggregate}{total} += $weight;

        my $frames = $trace->frames;

        # TODO move it to Reader.pm?
        if ($slowops->{my $op_name = $trace->op_name}) {
            unshift @$frames, bless {
                id         => $frames->[0]->file . ":CORE::$op_name",
                subroutine => "CORE::$op_name",
                file       => $frames->[0]->file,
                line       => -2,
            }, 'Devel::StatProfiler::StackFrame';
        }

        for my $i (0 .. $#$frames) {
            my $frame = $frames->[$i];
            my $line = $frame->line;
            my $sub = $self->_sub($frame);

            $sub->{start_line} = $line if $sub->{start_line} > $line;
            $sub->{inclusive} += $weight;
            $sub->{lines}{inclusive}{$line} += $weight if $line > 0;

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

                my $callee = $caller->{lines}{callees}{$call_site->line}{_sub_id($sub)} ||= {
                    callee    => $sub,
                    inclusive => 0,
                };
                Scalar::Util::weaken($callee->{callee}) unless $callee->{inclusive};

                $callee->{inclusive} += $weight;
            }

            if (!$i) {
                $sub->{exclusive} += $weight;
                $sub->{lines}{exclusive}{$line} += $weight if $line > 0;
            }
        }

        if ($flames) {
            my $key = join ';', map { $_->subroutine || 'MAIN' } reverse @$frames;

            $flames->{$key} += $weight;
        }
    }
}

sub _fileify {
    my ($name) = @_;

    return 'no-file' unless $name;
    (my $base = File::Basename::basename($name)) =~ s/\W+/-/g;

    return $base;
}

sub _finalize {
    my ($self) = @_;
    my (%files, %package_map);

    # use the file defining the maximum number of subs of a certain
    # package as the main file for that package (for xsubs)
    for my $package (keys %{$self->{aggregate}{file_map}}) {
        my $max = 0;

        for my $file (keys %{$self->{aggregate}{file_map}{$package}}) {
            my $count = $self->{aggregate}{file_map}{$package}{$file};

            if ($count > $max) {
                $package_map{$package} = $file;
                $max = $count;
            }
        }
    }

    my $ordinal = 0;
    for my $sub (sort { $a->{file} cmp $b->{file} }
                      values %{$self->{aggregate}{subs}}) {
        # set the file for the xsub
        if ($sub->{kind} == 1) {
            # TODO in the binary format there should be a 'package' accessor
            my ($package) = $sub->{name} =~ m{^(.*)::[^:]+};

            $sub->{file} = $package_map{$package} // '';
        }

        my ($exclusive, $inclusive, $callees) = @{$sub->{lines}}{qw(exclusive inclusive callees)};
        my $entry = $files{$sub->{file}} ||= {
            name      => $sub->{file},
            basename  => $sub->{file} eq '' ? '' : File::Basename::basename($sub->{file}),
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

    if ($path eq '') {
        return ['Dummy file to stick orphan XSUBs in...'];
    }

    # temporary
    if (!-f $path) {
        warn "Can't find source for '$path'";
        return ['Eval source not available...'];
    }

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

        if ($sub->{kind} == 0) {
            return sprintf '%s#L%d',
                $self->{aggregate}{files}{$sub->{file}}{report},
                $sub->{start_line};
        } else {
            (my $anchor = $sub->{name}) =~ s/\W+/-/g;
            return sprintf '%s#LX%s',
                $self->{aggregate}{files}{$sub->{file}}{report},
                $anchor;
        }
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
