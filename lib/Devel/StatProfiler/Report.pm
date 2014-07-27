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

my %templates = (
    file      => _get_template('file.tmpl'),
    subs      => _get_template('subs.tmpl'),
    index     => _get_template('index.tmpl'),
);

sub new {
    my ($class, %opts) = @_;
    my $self = bless {
        aggregate     => {
            total     => 0,
            subs      => {},
            flames    => {},
            files     => {},
            file_map  => {},
            finalized => 0,
        },
        flamegraph    => $opts{flamegraph} || 0,
        slowops       => {map { $_ => 1 } @{$opts{slowops} || []}},
        tick          => 0,
    }, $class;

    if ($self->{flamegraph}) {
        my $fg = File::Which::which('flamegraph') // File::Which::which('flamegraph.pl');
        $self->{fg_cmd} = "$fg --nametype=sub --countname=microseconds"
            if $fg;
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
    my $file = $frame->file;
    my $name = $frame->fq_sub_name || $frame->uq_sub_name;

    # count the number of subroutines of a certain package defined per
    # file, used as an heuristic for where to display xsub time
    if ($frame->line > 0) {
        $self->{aggregate}{file_map}{$frame->package}{$file}++;
    }

    return $self->{aggregate}{subs}{$frame->uq_sub_name} ||= {
        name       => $name,
        package    => $frame->package,
        file       => $file,
        inclusive  => 0,
        exclusive  => 0,
        callees    => {},
        call_sites => {},
        start_line => $frame->line,
        kind       => $frame->kind,
    };
}

sub _file {
    my ($self, $sub) = @_;

    return $self->{aggregate}{files}{$sub->{file}} ||= {
        name      => $sub->{file},
        basename  => $sub->{file} ? File::Basename::basename($sub->{file}) : '',
        report    => undef,
        lines     => {
            exclusive       => [],
            inclusive       => [],
            callees         => {},
        },
        exclusive => 0,
        subs      => {},
    };
}

sub _check_consistency {
    my ($self, $tick, $depth, $perl_version, $file) = @_;

    if ($self->{tick} == 0) {
        $self->{tick} = $tick;
        $self->{stack_depth} = $depth;
        $self->{perl_version} = $perl_version;
    } else {
        if ($tick != $self->{tick} ||
                $depth != $self->{stack_depth} ||
                $perl_version ne $self->{perl_version}) {
            die <<EOT;
Inconsistent sampling parameters:
Current tick duration: $self->{tick} stack sample depth: $self->{stack_depth} Perl version: $self->{perl_version}

$file sampling parameters:
Tick duration: $tick stack sample depth: $depth Perl version: $perl_version
EOT
        }
    }
}

sub add_trace_file {
    my ($self, $file) = @_;
    my $r = ref $file ? $file : Devel::StatProfiler::Reader->new($file);
    my $flames = $self->{flamegraph} ? $self->{aggregate}{flames} : undef;
    my $slowops = $self->{slowops};

    $self->_check_consistency(
        $r->get_source_tick_duration,
        $r->get_source_stack_sample_depth,
        $r->get_source_perl_version,
        $file,
    );

    while (my $trace = $r->read_trace) {
        my $weight = $trace->weight;

        $self->{aggregate}{total} += $weight;

        my $frames = $trace->frames;

        # TODO move it to Reader.pm?
        if ($slowops->{my $op_name = $trace->op_name}) {
            unshift @$frames, bless {
                "package"  => "CORE",
                sub_name   => $op_name,
                fq_sub_name=> "CORE::$op_name",
                file       => $frames->[0]->file,
                line       => -2,
            }, 'Devel::StatProfiler::StackFrame';
        }

        for my $i (0 .. $#$frames) {
            my $frame = $frames->[$i];
            my $line = $frame->line;
            my $sub = $self->_sub($frame);
            my $file = $line > 0 ? $self->_file($sub) : undef;

            $sub->{start_line} = $line if $sub->{start_line} > $line;
            $sub->{inclusive} += $weight;
            $file->{lines}{inclusive}[$line] += $weight if $file;

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

                my $callee = $caller->{callees}{$site->{line}}{_sub_id($sub)} ||= {
                    callee    => $sub,
                    inclusive => 0,
                };
                Scalar::Util::weaken($callee->{callee}) unless $callee->{inclusive};

                $callee->{inclusive} += $weight;
            }

            if (!$i) {
                $sub->{exclusive} += $weight;
                $file->{lines}{exclusive}[$line] += $weight if $file;
            }
        }

        if ($flames) {
            my $key = join ';', map { $_->fq_sub_name || 'MAIN' } reverse @$frames;

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

sub finalize {
    my ($self) = @_;

    die "Reports can only be finalized once" if $self->{aggregate}{finalized};
    $self->{aggregate}{finalized} = 1;

    # use the file defining the maximum number of subs of a certain
    # package as the main file for that package (for xsubs)
    my %package_map;
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
            $sub->{file} = $package_map{$sub->{package}} // '';
        }

        # the entry for all files are already there, except for XSUBs
        # that don't have an assigned file yet
        my $entry = $self->{aggregate}{files}{$sub->{file}} ||= $self->_file($sub);

        $entry->{report} ||= sprintf('%s-%d-line.html', _fileify($sub->{file}), ++$ordinal);
        $entry->{exclusive} += $sub->{exclusive};
        push @{$entry->{subs}{$sub->{start_line}}}, $sub;

        my $callees = $sub->{callees};
        for my $line (keys %$callees) {
            push @{$entry->{lines}{callees}{$line}}, values %{$callees->{$line}};
        }
    }
}

sub _fetch_source {
    my ($self, $path) = @_;
    my @lines;

    if ($path eq '') {
        return ['Dummy file to stick orphan XSUBs in...'];
    }

    # temporary
    if (!-f $path) {
        warn "Can't find source for '$path'\n";
        return ['Eval source not available...'];
    }

    open my $fh, '<', $path
        or die "Failed to open source code file '$path', "
               . "do you have permission to read it? (Reason: $!)";

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

    $self->finalize;
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

        $self->_write_template($templates{file}, \%file_data,
                               $directory, $entry->{report});
    }

    # format flame graph
    my $flamegraph_link;
    if ($self->{flamegraph}) {
        die "Unable to find flamegraph executable, please install NYTProf"
            unless $self->{fg_cmd};

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

    $self->_write_template($templates{subs}, \%subs_data,
                           $directory, 'subs.html');

    # format index page
    my %main_data = (
        files           => [sort { $b->{exclusive} <=> $a->{exclusive} }
                                 values %$files],
        subs            => \@subs,
        flamegraph      => $flamegraph_link,
        sub_link        => $sub_link,
    );

    $self->_write_template($templates{index}, \%main_data,
                           $directory, 'index.html');

    # copy CSS
    File::Copy::copy(
        File::ShareDir::dist_file('Devel-StatProfiler', 'statprofiler.css'),
        File::Spec::Functions::catfile($directory, 'statprofiler.css'));
}

1;
