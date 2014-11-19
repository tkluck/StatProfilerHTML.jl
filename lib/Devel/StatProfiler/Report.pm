package Devel::StatProfiler::Report;
# ABSTRACT: process profiler output to generate a report

use strict;
use warnings;
use autodie qw(open close);

use Devel::StatProfiler::Reader;
use Devel::StatProfiler::EvalSource;
use Devel::StatProfiler::SourceMap;
use Devel::StatProfiler::Utils qw(
    check_serializer
    read_data
    state_dir
    utf8_sha1_hex
    write_data_any
);
use Devel::StatProfiler::Slowops;
use File::ShareDir;
use File::Basename ();
use File::Spec::Functions ();
use File::Copy ();
use File::Path ();
use Text::MicroTemplate;
use IO::Compress::Gzip;
use POSIX ();

my $NO_SOURCE = ['Source not available...'];

my %TEMPLATES = (
    file      => _get_template('file.tmpl'),
    subs      => _get_template('subs.tmpl'),
    index     => _get_template('index.tmpl'),
    header    => _get_template('header.tmpl'),
);

my %SPECIAL_SUBS = map { $_ => 1 } qw(
    BEGIN
    UNITCHECK
    CHECK
    INIT
    END
);

sub new {
    my ($class, %opts) = @_;
    my $genealogy = {};
    my $self = bless {
        aggregate     => {
            total     => 0,
            subs      => {},
            flames    => {},
            files     => {},
            file_map  => {},
            finalized => 0,
        },
        $opts{sources} ? (
            source    => Devel::StatProfiler::EvalSource->new(
                serializer     => $opts{serializer},
                genealogy      => $genealogy,
                root_dir       => $opts{root_directory},
                shard          => $opts{shard},
            ),
            sourcemap => Devel::StatProfiler::SourceMap->new(
                serializer     => $opts{serializer},
                root_dir       => $opts{root_directory},
                shard          => $opts{shard},
            ),
        ) : (
            source    => undef,
            sourcemap => undef,
        ),
        genealogy     => $genealogy,
        flamegraph    => $opts{flamegraph} || 0,
        slowops       => {map { $_ => 1 } @{$opts{slowops} || \@Devel::StatProfiler::Slowops::OPS}},
        tick          => 0,
        stack_depth   => 0,
        perl_version  => undef,
        process_id    => $opts{mixed_process} ? 'mixed' : undef,
        serializer    => $opts{serializer} || 'storable',
        fetchers      => $opts{fetchers} || [[undef, 'fetch_source_from_file']],
        shard         => $opts{shard},
        root_dir      => $opts{root_directory},
        shard         => $opts{shard},
    }, $class;

    if ($self->{flamegraph}) {
        my $fg = File::ShareDir::dist_file('Devel-StatProfiler', 'flamegraph.pl');
        $self->{fg_cmd} = "$^X $fg --nametype=sub --countname=samples";
    }

    check_serializer($self->{serializer});

    return $self;
}

sub _get_template {
    my ($basename) = @_;
    my $path = File::ShareDir::dist_file('Devel-StatProfiler', $basename);
    my $tmpl = do {
        local $/;
        open my $fh, '<', $path or die "Unable to open '$path': $!";
        readline $fh;
    };

    return Text::MicroTemplate::build_mt($tmpl);
}

sub _write_template {
    my ($self, $sub, $data, $dir, $file, $compress) = @_;
    my $text = $sub->($data);
    my $target = File::Spec::Functions::catfile($dir, $file);

    open my $fh, '>', $compress ? "$target.gz" : $target;
    if ($compress) {
        IO::Compress::Gzip::gzip(\"$text", $fh)
              or die "gzip failed: $IO::Compress::Gzip::GzipError";
    } else {
        print $fh $text;
    }
    close $fh;
}

sub _compress_inplace {
    my ($self, $path) = @_;

    IO::Compress::Gzip::gzip($path, "$path.gz")
        or die "gzip failed: $IO::Compress::Gzip::GzipError";
    unlink $path;
}

sub _call_site_id {
    my ($frame) = @_;

    return sprintf '%s:%d', $frame->file, $frame->line;
}

sub _sub {
    my ($self, $frame) = @_;
    my $file = $frame->file;
    my $uq_name = $frame->uq_sub_name;
    my $name = $frame->fq_sub_name || $uq_name;

    # count the number of subroutines of a certain package defined per
    # file, used as an heuristic for where to display xsub time
    if ($frame->line > 0 && $frame->package) {
        $self->{aggregate}{file_map}{$frame->package}{$file}++;
    }

    return $self->{aggregate}{subs}{$uq_name} ||= {
        name       => $name,
        uq_name    => $uq_name,
        package    => $frame->package,
        file       => $file,
        inclusive  => 0,
        exclusive  => 0,
        callees    => {},
        call_sites => {},
        start_line => $frame->first_line,
        kind       => $frame->kind,
        is_main    => $frame->is_main,
        is_eval    => $frame->is_eval,
    };
}

sub _file {
    my ($self, $file) = @_;

    return $self->{aggregate}{files}{$file} ||= {
        name      => $file,
        basename  => $file ? File::Basename::basename($file) : '',
        lines     => {
            exclusive       => [],
            inclusive       => [],
            # filled during finalization
            callees         => {},
        },
        # filled during finalization
        report    => undef,
        exclusive => 0,
        subs      => {},
    };
}

sub _check_consistency {
    my ($self, $tick, $depth, $perl_version, $process_id, $file) = @_;

    if ($self->{tick} == 0) {
        $self->{tick} = $tick;
        $self->{stack_depth} = $depth;
        $self->{perl_version} = $perl_version;
        $self->{process_id} //= $process_id;
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

        if ($self->{process_id} ne 'mixed' &&
                ($process_id // 'undef') ne ($self->{process_id} // 'undef')) {
            my ($p1_str, $p2_str) = ($process_id // 'undef', $self->{process_id} // 'undef');
            die <<EOT;
Inconsistent process IDs:
Current process ID: $p2_str
$file process ID: $p1_str
EOT
        }
    }
}

sub add_trace_file {
    my ($self, $file) = @_;
    my $r = ref $file ? $file : Devel::StatProfiler::Reader->new($file);
    my $flames = $self->{flamegraph} ? $self->{aggregate}{flames} : undef;
    my $slowops = $self->{slowops};

    my ($process_id, $process_ordinal, $parent_id, $parent_ordinal) =
        @{$r->get_genealogy_info};
    $self->{genealogy}{$process_id}{$process_ordinal} = [$parent_id, $parent_ordinal];

    $self->_check_consistency(
        $r->get_source_tick_duration,
        $r->get_source_stack_sample_depth,
        $r->get_source_perl_version,
        $process_id,
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
                first_line => -2,
            }, 'Devel::StatProfiler::StackFrame';
        }

        for my $i (0 .. $#$frames) {
            my $frame = $frames->[$i];
            my $line = $frame->line;
            my $sub = $self->_sub($frame);
            my $file = $line > 0 ? $self->_file($sub->{file}) : undef;

            $sub->{inclusive} += $weight;
            $file->{lines}{inclusive}[$line] += $weight if $file;

            if ($i != $#$frames) {
                my $call_site = $frames->[$i + 1];
                my $caller = $self->_sub($call_site);
                my $call_line = $call_site->line;
                my $site = $sub->{call_sites}{_call_site_id($call_site)} ||= {
                    caller    => $caller->{uq_name},
                    exclusive => 0,
                    inclusive => 0,
                    file      => $call_site->file,
                    line      => $call_line,
                };

                $site->{inclusive} += $weight;
                $site->{exclusive} += $weight if !$i;

                my $callee = $caller->{callees}{$call_line}{$sub->{uq_name}} ||= {
                    callee    => $sub->{uq_name},
                    inclusive => 0,
                };

                $callee->{inclusive} += $weight;
            }

            if (!$i) {
                $sub->{exclusive} += $weight;
                $file->{lines}{exclusive}[$line] += $weight if $file;
            }
        }

        if ($flames) {
            my $key = join ';', map $_->uq_sub_name, reverse @$frames;

            $flames->{$key} += $weight;
        }
    }

    $self->{source}->add_sources_from_reader($r) if $self->{source};
    $self->{sourcemap}->add_sources_from_reader($r) if $self->{sourcemap};
}

sub _map_hash_rx {
    my ($hash, $rx, $subst, $map, $merge) = @_;

    for my $key (keys %$hash) {
        my $value = $hash->{$key};
        my $new_key = $map->{$key};

        if (!$new_key && $key =~ $rx) {
            $new_key = $subst->($key);
        }

        if ($new_key) {
            if (!exists $hash->{$new_key}) {
                $hash->{$new_key} = delete $hash->{$key};
            } elsif ($merge) {
                $merge->($hash->{$new_key}, delete $hash->{$key});
            } else {
                Carp::confess("Duplicate value for key '$key' => '$new_key' without a merge function");
            }
        }

        if (ref $value) {
            $value->{uq_name} = $subst->($value->{uq_name}) if $value->{uq_name};
            $value->{file} = $subst->($value->{file}) if $value->{file};
            $value->{callee} = $subst->($value->{callee}) if $value->{callee};
            $value->{caller} = $subst->($value->{caller}) if $value->{caller};
        }
    }
}

sub _merge_lines {
    my ($a, $b) = @_;
    my $max = $#$a > $#$b ? $#$a : $#$b;

    $a->[$_] += $b->[$_] // 0 for 0..$max;
}

sub _merge_file_map_entry {
    $_[0] += $_[1];
}

sub _merge_file_entry {
    my ($a, $b) = @_;

    $a->{name} = $b->{name} if $a->{name} gt $b->{name};
    $a->{basename} = $b->{basename} if $a->{basename} gt $b->{basename};

    _merge_lines($a->{lines}{exclusive}, $b->{lines}{exclusive});
    _merge_lines($a->{lines}{inclusive}, $b->{lines}{inclusive});
}

sub _merge_call_sites {
    my ($a, $b) = @_;

    $a->{inclusive} += $b->{inclusive};
    $a->{exclusive} += $b->{exclusive};
}

sub _merge_callees {
    my ($a, $b) = @_;

    $a->{inclusive} += $b->{inclusive};
}

sub _merge_sub_entry {
    my ($a, $b) = @_;

    $a->{name} = $b->{name} if $a->{name} gt $b->{name};

    $a->{inclusive} += $b->{inclusive};
    $a->{exclusive} += $b->{exclusive};

    my ($acs, $bcs) = ($a->{call_sites}, $b->{call_sites});
    for my $key (keys %$bcs) {
        if (exists $acs->{$key}) {
            $acs->{$key}{inclusive} += $bcs->{$key}{inclusive};
            $acs->{$key}{exclusive} += $bcs->{$key}{exclusive};
        } else {
            $acs->{$key} = $bcs->{$key};
        }
    }

    my ($ac, $bc) = ($a->{callees}, $b->{callees});
    for my $key (keys %$bc) {
        if (exists $ac->{$key}) {
            my ($acl, $bcl) = ($ac->{$key}, $bc->{$key});

            for my $sub (keys %$bcl) {
                if (exists $acl->{$sub}) {
                    $acl->{$sub}{inclusive} += $bcl->{$sub}{inclusive};
                } else {
                    $acl->{$sub} = $bcl->{$sub};
                }
            }
        } else {
            $ac->{$key} = $bc->{$key};
        }
    }
}

sub map_source {
    my ($self, $process_id) = @_;
    my $files = $self->{aggregate}{files};
    my $subs = $self->{aggregate}{subs};
    my $flames = $self->{aggregate}{flames};
    my $file_map = $self->{aggregate}{file_map};
    my %eval_map;
    $process_id ||= $self->{process_id};

    for my $file (keys %$files) {
        my $hash = $self->{source}->get_hash_by_name($process_id, $file);

        $eval_map{$file} = "eval:$hash" if $hash;
    }

    my @eval_map = sort { length($b) <=> length($a) } keys %eval_map;

    return unless @eval_map;

    my $file_map_rx = '(^|:|;)(' . join('|', map "\Q$_\E", @eval_map) . ')(:|;|$)';
    my $file_map_qr = qr/$file_map_rx/;
    my $file_repl_sub = sub {
        $_[0] =~ s/$file_map_qr/$1$eval_map{$2}$3/gr
    };

    for my $package (values %$file_map) {
        _map_hash_rx($package, $file_map_qr, $file_repl_sub, \%eval_map, \&_merge_file_map_entry);
    }

    _map_hash_rx($files, $file_map_qr, $file_repl_sub, \%eval_map, \&_merge_file_entry);
    _map_hash_rx($subs, $file_map_qr, $file_repl_sub, \%eval_map, \&_merge_sub_entry);

    for my $sub (values %$subs) {
        _map_hash_rx($sub->{call_sites}, $file_map_qr, $file_repl_sub, \%eval_map, \&_merge_call_sites);

        for my $by_line (values %{$sub->{callees}}) {
            _map_hash_rx($by_line, $file_map_qr, $file_repl_sub, \%eval_map, \&_merge_callees);
        }
    }

    _map_hash_rx($flames, $file_map_qr, $file_repl_sub, \%eval_map, \&_merge_file_map_entry);
}

sub merge {
    my ($self, $report) = @_;

    $self->_check_consistency(
        $report->{tick},
        $report->{stack_depth},
        $report->{perl_version},
        $report->{process_id},
        'merged report',
    );

    $self->{aggregate}{total} += $report->{aggregate}{total};

    for my $process_id (keys %{$report->{genealogy}}) {
        for my $process_ordinal (keys %{$report->{genealogy}{$process_id}}) {
            $self->{genealogy}{$process_id}{$process_ordinal} ||= $report->{genealogy}{$process_id}{$process_ordinal};
        }
    }

    {
        my $my_map = $self->{aggregate}{file_map};
        my $other_map = $report->{aggregate}{file_map};

        for my $package (keys %$other_map) {
            for my $file (keys %{$other_map->{$package}}) {
                $my_map->{$package}{$file} += $other_map->{$package}{$file};
            }
        }
    }

    {
        my $my_subs = $self->{aggregate}{subs};
        my $other_subs = $report->{aggregate}{subs};

        for my $id (keys %$other_subs) {
            my $other_sub = $other_subs->{$id};
            my $my_sub = $my_subs->{$id} ||= {
                name       => $other_sub->{name},
                uq_name    => $other_sub->{uq_name},
                package    => $other_sub->{package},
                file       => $other_sub->{file},
                inclusive  => 0,
                exclusive  => 0,
                callees    => {},
                call_sites => {},
                start_line => $other_sub->{start_line},
                uq_name    => $other_sub->{uq_name},
                kind       => $other_sub->{kind},
                is_main    => $other_sub->{is_main},
                is_eval    => $other_sub->{is_eval},
            };

            $my_sub->{inclusive} += $other_sub->{inclusive};
            $my_sub->{exclusive} += $other_sub->{exclusive};
        }

        for my $id (keys %$other_subs) {
            my $other_sub = $other_subs->{$id};
            my $my_sub = $my_subs->{$id};

            for my $site_id (keys %{$other_sub->{call_sites}}) {
                my $other_site = $other_sub->{call_sites}{$site_id};
                my $site = $my_sub->{call_sites}{$site_id} ||= {
                    caller    => $other_site->{caller},
                    exclusive => 0,
                    inclusive => 0,
                    file      => $other_site->{file},
                    line      => $other_site->{line},
                };

                $site->{inclusive} += $other_site->{inclusive};
                $site->{exclusive} += $other_site->{exclusive};
            }

            for my $line (keys %{$other_sub->{callees}}) {
                for my $callee_id (keys %{$other_sub->{callees}{$line}}) {
                    my $callee = $my_sub->{callees}{$line}{$callee_id} ||= {
                        callee    => $other_sub->{callees}{$line}{$callee_id}{callee},
                        inclusive => 0,
                    };

                    $callee->{inclusive} += $other_sub->{callees}{$line}{$callee_id}{inclusive};
                };
            }
        }
    }

    {
        my $my_files = $self->{aggregate}{files};
        my $other_files = $report->{aggregate}{files};

        for my $file_id (keys %$other_files) {
            my $other_file = $other_files->{$file_id};
            my $file = $my_files->{$file_id} ||= {
                name      => $other_file->{name},
                basename  => $other_file->{basename},
                report    => undef,
                lines     => {
                    exclusive       => [],
                    inclusive       => [],
                    callees         => {},
                },
                exclusive => 0,
                subs      => {},
            };

            $file->{exclusive} += $other_file->{exclusive};

            my $other_exclusive = $other_file->{lines}{exclusive};
            my $my_exclusive = $file->{lines}{exclusive};
            for my $i (0..$#$other_exclusive) {
                $my_exclusive->[$i] += $other_exclusive->[$i]
                    if $other_exclusive->[$i];
            }

            my $other_inclusive = $other_file->{lines}{inclusive};
            my $my_inclusive = $file->{lines}{inclusive};
            for my $i (0..$#$other_inclusive) {
                $my_inclusive->[$i] += $other_inclusive->[$i]
                    if $other_inclusive->[$i];
            }
        }
    }

    {
        my $my_flames = $self->{aggregate}{flames};
        my $other_flames = $report->{aggregate}{flames};

        for my $key (keys %$other_flames) {
            $my_flames->{$key} += $other_flames->{$key};
        }
    }
}

sub _save {
    my ($self, $report_dir, $is_part) = @_;
    my $state_dir = state_dir($self, $is_part);
    my $report_base = $is_part ? sprintf('report.%s', $self->{process_id}) : 'report';

    File::Path::mkpath([$state_dir, $report_dir]);

    # the merged metadata is saved separately
    if ($is_part) {
        write_data_any($is_part, $self, $state_dir, 'genealogy', $self->{genealogy});
        $self->{source}->save_part if $self->{source};
    }
    write_data_any($is_part, $self, $report_dir, $report_base, [
        $self->{tick},
        $self->{stack_depth},
        $self->{perl_version},
        $self->{process_id},
        $self->{aggregate}
    ]);
}

sub save_part { $_[0]->_save($_[1], 1) }
sub save_aggregate { $_[0]->_save($_[1], 0) }

sub load {
    my ($self, $report) = @_;

    @{$self}{qw(
        tick
        stack_depth
        perl_version
        process_id
        aggregate
    )} = @{read_data($self->{serializer}, $report)};
}

sub _fileify {
    my ($name) = @_;

    return 'no-file' unless $name;
    my $base = File::Basename::basename($name) =~ s/\W+/-/gr;
    my $id = substr(utf8_sha1_hex($name), 0, 20);

    return "$base-$id";
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

    for my $sub (sort { $a->{file} cmp $b->{file} }
                      values %{$self->{aggregate}{subs}}) {
        # set the file for the xsub
        if ($sub->{kind} == 1) {
            $sub->{file} = $package_map{$sub->{package}} // '';
        }

        # the entry for all files are already there, except for XSUBs
        # that don't have an assigned file yet
        my $entry = $self->_file($sub->{file});

        $entry->{report} ||= sprintf('%s-line.html', _fileify($sub->{file}));
        $entry->{exclusive} += $sub->{exclusive};
        push @{$entry->{subs}{$sub->{start_line}}}, $sub
            if !$sub->{is_main} && !$sub->{is_eval};

        my $callees = $sub->{callees};
        for my $line (keys %$callees) {
            push @{$entry->{lines}{callees}{$line}}, values %{$callees->{$line}};
        }
    }

    # in case there are extra file entries without subs (added
    # manually in order to parse #line directives), and in case
    # there are files/evals where the "principal" part did not get an entry
    # because it has no samples, but some of the other parts, mapped by #line
    # directives got some samples
    for my $entry (values %{$self->{aggregate}{files}}) {
        $entry->{report} ||= sprintf('%s-line.html', _fileify($entry->{name}));

        my $reverse_file = $self->{sourcemap} &&
            $self->{sourcemap}->get_reverse_mapping($entry->{name});

        # ensure the main entry for the file/eval is present
        if ($reverse_file && !$self->{aggregate}{files}{$reverse_file}) {
            my $entry = $self->_file($reverse_file);

            $entry->{report} = sprintf('%s-line.html', _fileify($reverse_file));
            $entry->{exclusive} = 0;;
        }
    }
}

sub fetch_source_from_file {
    my ($self, $path) = @_;

    return -f $path ? $path : undef;
}

sub _fetch_source {
    my ($self, $path) = @_;
    my @lines;

    if ($path eq '') {
        return [], ['Dummy file to stick orphan XSUBs in...'];
    }

    # eval source code
    if ($self->{source} && $path =~ /^eval:([0-9a-fA-F]+)$/) {
        if (my $source = $self->{source}->get_source_by_hash($1)) {
            return [], ['Eval source code...', split /\n/, $source];
        }
    }

    my ($input, $fh);
    for my $fetcher (@{$self->{fetchers}}) {
        my ($prefix, $code) = @$fetcher;

        next if $prefix && rindex($path, $prefix, 0) == -1;
        $input = ref($code) eq 'CODE' ? $code->($path) : $self->$code($path);
        last if $input;
    }
    return [], $NO_SOURCE unless $input;

    if (my $ref = ref($input)) {
        if ($ref eq 'SCALAR') {
            open $fh, '<', $input;
        } elsif ($ref eq 'GLOB') {
            $fh = $input;
        } else {
            die "Source code fetcher returned reference to '$ref', "
                . " expected either 'SCALAR' or 'GLOB'";
        }
    } else {
        open $fh, '<', $input
            or die "Failed to open source code file '$input' for path '$path', "
                   . "do you have permission to read it? (Reason: $!)";
    }

    $self->{sourcemap}->start_file_mapping($path);

    my @ends;
    while (defined (my $line = <$fh>)) {
        $self->{sourcemap}->add_file_mapping(@lines + 2, $2, $1)
            if $line =~ /^#line\s+(\d+)\s+(.+)$/;
        push @lines, $line;
        push @ends, scalar @lines if $line =~ /\b__(?:DATA|END)__\b/;
    }

    $self->{sourcemap}->end_file_mapping(scalar @lines);

    return [], $NO_SOURCE unless @lines;
    return \@ends, ['I hope you never see this...', @lines];
}

# merges the entries for multiple logical files to match the source
# code of a physical file
sub _merged_entry {
    my ($self, $file, $mapping, $diagnostics) = @_;
    my $base = $self->{aggregate}{files}{$file};
    my $merged = {
        name      => $base->{name},
        basename  => $base->{basename},
        lines     => {
            exclusive       => [@{$base->{lines}{exclusive}}],
            inclusive       => [@{$base->{lines}{inclusive}}],
            callees         => {%{$base->{lines}{callees}}},
        },
        report    => $base->{report},
        exclusive => $base->{exclusive},
        subs      => {%{$base->{subs}}},
    };
    my %line_ranges;

    for (my $i = 0; $i < $#$mapping; ++$i) {
        my ($physical_line, $logical_file, $logical_line) = @{$mapping->[$i]};
        my $physical_end = $mapping->[$i + 1][0];

        push @{$line_ranges{$logical_file}}, [
            $logical_line,
            $logical_line + $physical_end - $physical_line,
            $physical_line,
            $physical_end,
        ];
    }

    for my $key (keys %line_ranges) {
        next if $key eq $file;
        my $entry = $self->{aggregate}{files}{$key};

        # we have no data for this part of the file
        next unless $entry;

        my @ranges = sort { $a->[1] <=> $b->[1] } @{$line_ranges{$key}};
        my @subs = sort { $a <=> $b } keys %{$entry->{subs}};
        my @callees = sort { $a <=> $b } keys %{$entry->{lines}{callees}};
        my ($sub_index, $callee_index) = (0, 0);

        $merged->{exclusive} += $entry->{exclusive};

        for my $range (@ranges) {
            my ($logical_start, $logical_end, $physical_start, $physical_end) =
                @$range;

            while ($sub_index < @subs && $subs[$sub_index] <= $logical_end) {
                my $mapped = $subs[$sub_index] - $logical_start + $physical_start;

                $merged->{subs}{$mapped} = $entry->{subs}{$subs[$sub_index]};
                ++$sub_index;
            }

            while ($callee_index < @callees && $callees[$callee_index] <= $logical_end) {
                my $mapped = $callees[$callee_index] - $logical_start + $physical_start;

                $merged->{lines}{callees}{$mapped} = $entry->{lines}{callees}{$callees[$callee_index]};
                ++$callee_index;
            }

            for my $logical_line ($logical_start .. $logical_end) {
                my $physical_line = $logical_line - $logical_start + $physical_start;

                $merged->{lines}{inclusive}[$physical_line] += $entry->{lines}{inclusive}[$logical_line] // 0;
                $merged->{lines}{exclusive}[$physical_line] += $entry->{lines}{exclusive}[$logical_line] // 0;
            }
        }

        push @$diagnostics, "There are unmapped subs for '$key' in '$file'"
            unless $sub_index == @subs;
        push @$diagnostics, "There are unmapped callees for '$key' in '$file'"
            unless $callee_index == @callees;
    }

    return $merged;
}

sub _format_ratio {
    my ($value, $total, $empty) = @_;
    $value //= 0, $total //= 0;

    return '' if $empty && $value == 0;
    return '0' if $value == 0 && $total == 0;
    return '? (?%)' if $value != 0 && $total == 0;

    my $perc = $value / $total * 100;
    if ($perc >= 0.01) {
        return sprintf '%d (%.02f%%)', $value, $perc;
    } elsif ($perc >= 0.0001) {
        return sprintf '%d (%.04f%%)', $value, $perc;
    } else {
        return sprintf '%d', $value;
    }
}

sub output {
    my ($self, $directory, $compress) = @_;
    my @diagnostics;

    die "Unable to create report without a source map and an eval map"
        unless $self->{source} and $self->{sourcemap};

    File::Path::mkpath([$directory]);

    $self->finalize;
    my $files = $self->{aggregate}{files};
    my @subs = sort { $b->{exclusive} <=> $a->{exclusive} ||
                      $b->{inclusive} <=> $a->{inclusive} }
                    values %{$self->{aggregate}{subs}};

    my $date = POSIX::strftime('%c', localtime(time));
    my $include = sub {
        $TEMPLATES{$_[0]}->($_[1]);
    };

    my $sub_link = sub {
        my ($sub) = @_;

        if ($sub->{kind} == 0) {
            return sprintf '%s#S%s',
                $self->{aggregate}{files}{$sub->{file}}{report},
                $sub->{uq_name} =~ s/\W+/-/gr;
        } else {
            return sprintf '%s#S%s',
                $self->{aggregate}{files}{$sub->{file}}{report},
                $sub->{name} =~ s/\W+/-/gr;
        }
    };

    my $file_link = sub {
        my ($file, $line) = @_;
        my $report = $self->{aggregate}{files}{$file}{report};

        # twice, because we have physical files with source code for
        # multiple logical files (via #line directives)
        return sprintf '%s#L%s-%d', $report, $report, $line;
    };

    my $lookup_sub = sub {
        my ($name) = @_;

        die "Invalid sub reference '$name'" unless exists $self->{aggregate}{subs}{$name};
        return $self->{aggregate}{subs}{$name};
    };

    my $format_total_samples = sub {
        my ($samples, $empty) = @_;

        return _format_ratio($samples, $self->{aggregate}{total}, $empty);
    };

    # format files
    my @queued_files;
    my %merged_profiles;

    my $format_file = sub {
        my ($entry, $ends, $code, $mapping) = @_;
        # map logical line, physical file, physical line ->
        #     logical line, HTML report file, physical line
        my $mapping_for_link = [map {
            [$_->[0],
             ($_->[1] && $self->{aggregate}{files}{$_->[1]} ?
                  $self->{aggregate}{files}{$_->[1]}{report} :
                  undef),
             $_->[2]]
        } @$mapping];

        # find actual sub definition by matching source name in code
        # (yes, fragile, but mostly good enough)
        my %subs;
        for my $subs_at_line (values %{$entry->{subs}}) {
            for my $sub (@$subs_at_line) {
                my $fq_name = $sub->{name};
                my $name = $fq_name =~ s{.*::}{}r;

                # finding the start of anonymous subs is way too fragile,
                # just use the default
                if ($name eq '__ANON__') {
                    push @{$subs{$sub->{start_line}}}, $sub;
                    next;
                }

                my $match = $SPECIAL_SUBS{$name} ?
                    qr{\bsub\s+(?:\Q$fq_name\E|\Q$name\E)\b|^\s*\Q$name\E\b} :
                    qr{\bsub\s+(?:\Q$fq_name\E|\Q$name\E)\b};
                my $start_line = $sub->{start_line};
                for (my $i = 0; $i < @$mapping; ++$i) {
                    my $entry = $mapping->[$i];
                    next unless $entry->[1] && $entry->[1] eq $sub->{file};
                    if ($entry->[2] <= $start_line && ($entry->[2] + ($mapping->[$i + 1][0] - $entry->[0])) > $start_line) {
                        $start_line = $entry->[0] + $start_line - $entry->[2];
                    }
                }
                for (my $line = $start_line; $line > 0 && $line < @$code; --$line) {
                    my $src = $code->[$line];

                    if ($src =~ $match) {
                        $start_line = $line;
                        last;
                    }
                }

                push @{$subs{$start_line}}, $sub;
            }
        }

        # remove source after __DATA__/__END__ token, but only if
        # there are no samples after it (to avoid false positives)
        for my $end (@$ends) {
            if ($end >= @{$entry->{lines}{inclusive}} - 1) {
                splice @$code, $end + 1; # preserve the __DATA__/__END__
                last;
            }
        }

        my %file_data = (
            include                 => $include,
            date                    => $date,
            name                    => $entry->{name},
            basename                => $entry->{basename},
            lines                   => $code,
            subs                    => \%subs,
            exclusive               => $entry->{lines}{exclusive},
            inclusive               => $entry->{lines}{inclusive},
            callees                 => $entry->{lines}{callees},
            sub_link                => $sub_link,
            file_link               => $file_link,
            format_total_ratio      => $format_total_samples,
            format_ratio            => \&_format_ratio,
            lookup_sub              => $lookup_sub,
            mapping                 => $mapping_for_link,
        );

        $self->_write_template($TEMPLATES{file}, \%file_data,
                               $directory, $entry->{report}, $compress);
    };

    # write reports for physical files
    for my $file (keys %$files) {
        my ($ends, $code) = $self->_fetch_source($file);

        if ($code eq $NO_SOURCE) {
            # re-process this later, in case the mapping is due to a
            # #line directive in one of the parsed files
            push @queued_files, $file;
        } elsif (my $mapping = $self->{sourcemap}->get_mapping($file)) {
            my $merged_entry = $self->_merged_entry($file, $mapping, \@diagnostics);

            $format_file->($merged_entry, $ends, $code, $mapping);
        } else {
            my $entry = $files->{$file};
            my $mapping = [
                [1, $file, 1],
                [scalar @$code, undef, scalar @$code],
            ];

            $format_file->($entry, $ends, $code, $mapping);
        }
    }

    # logical files (just copies the content of the report written by
    # the loop above
    for my $file (@queued_files) {
        # this can only be a mapped copy of an existing file
        my $reverse_file = $self->{sourcemap}->get_reverse_mapping($file);

        unless ($reverse_file) {
            push @diagnostics, "Unable to find source for '$file'";
            next;
        }

        my $entry = $files->{$file};
        my $reverse_entry = $files->{$reverse_file};

        unless ($reverse_entry && $reverse_entry->{report}) {
            push @diagnostics, "Unable to find source for '$file'";
            next;
        }

        # TODO use symlink/hardlinks where available
        File::Copy::copy(
            File::Spec::Functions::catfile($directory, $reverse_entry->{report}),
            File::Spec::Functions::catfile($directory, $entry->{report}));
    }

    # format flame graph
    my $flamegraph_link;
    if ($self->{flamegraph} && %{$self->{aggregate}{flames}}) {
        $flamegraph_link = 'all_stacks_by_time.svg';

        my $flames = $self->{aggregate}{flames};
        my $calls_data = File::Spec::Functions::catfile($directory, 'all_stacks_by_time.calls');
        my $calls_svg = File::Spec::Functions::catfile($directory, $flamegraph_link);
        my $nameattr = File::Spec::Functions::catfile($directory, 'all_stacks.attrs');

        open my $calls_fh, '>', $calls_data;
        for my $key (keys %$flames) {
            print $calls_fh $key, ' ', $flames->{$key}, "\n";
        }
        close $calls_fh;

        open my $attrs_fh, '>', $nameattr;
        for my $sub (@subs) {
            print $attrs_fh join(
                "\t",
                $sub->{uq_name},
                "href=" . $sub_link->($sub),
                "function=" . $sub->{name},
            ), "\n";
        }
        close $attrs_fh;

        system("$self->{fg_cmd} --total=$self->{aggregate}{total} --nameattr=$nameattr $calls_data > $calls_svg") == 0
            or die "Generating $calls_svg failed\n";

        if ($compress) {
            $self->_compress_inplace($calls_data);
            $self->_compress_inplace($nameattr);
            $self->_compress_inplace($calls_svg);
        }
    }

    # format subs page
    my %subs_data = (
        include             => $include,
        date                => $date,
        subs                => \@subs,
        sub_link            => $sub_link,
        format_total_ratio  => $format_total_samples,
    );

    $self->_write_template($TEMPLATES{subs}, \%subs_data,
                           $directory, 'subs.html', $compress);

    # format index page
    my %main_data = (
        include             => $include,
        date                => $date,
        files               => [sort { $b->{exclusive} <=> $a->{exclusive} }
                                     values %$files],
        subs                => \@subs,
        flamegraph          => $flamegraph_link,
        sub_link            => $sub_link,
        format_total_ratio  => $format_total_samples,
    );

    $self->_write_template($TEMPLATES{index}, \%main_data,
                           $directory, 'index.html', $compress);

    # copy CSS
    File::Copy::copy(
        File::ShareDir::dist_file('Devel-StatProfiler', 'statprofiler.css'),
        File::Spec::Functions::catfile($directory, 'statprofiler.css'));

    return \@diagnostics;
}

1;
