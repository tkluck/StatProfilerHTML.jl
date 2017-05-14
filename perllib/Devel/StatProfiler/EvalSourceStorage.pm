package Devel::StatProfiler::EvalSourceStorage;

use strict;
use warnings;
use autodie qw(open close rename);

use Devel::StatProfiler::Utils qw(
    read_file
    write_file
);
use Archive::Zip qw(:ERROR_CODES :CONSTANTS);
use File::Path;
use File::Spec::Functions;
use File::Glob qw(bsd_glob);

sub new {
    my ($class, %opts) = @_;
    my $self = bless {
        base_dir    => $opts{base_dir},
        pack_files  => [],
        source_map  => {},
        manifest    => '',
    }, $class;

    return $self;
}

sub get_source_by_hash {
    my ($self, $hash) = @_;
    my $source = $self->_get_source_by_hash($hash);

    return $source if defined $source;

    # we should only get here because of manifest lazy loading
    $self->_load_manifest();
    return $self->_get_source_by_hash($hash) // '';
}

sub _get_source_by_hash {
    my ($self, $hash) = @_;
    my $packed = pack "H*", $hash;

    if (my $pack_index = $self->{source_map}{$packed}) {
        return $self->_get_source_from_pack($hash, $self->{pack_files}[$pack_index]);
    } else {
        my $path = File::Spec::Functions::catfile(
            $self->{base_dir},
            substr($hash, 0, 2),
            substr($hash, 2, 2),
            substr($hash, 4)
        );

        return -f $path ? read_file($path, 'use_utf8') : undef;
    }
}

sub add_source_string {
    my ($self, $hash) = @_;
    my $source_subdir = File::Spec::Functions::catdir(
        $self->{base_dir},
        substr($hash, 0, 2),
        substr($hash, 2, 2),
    );

    File::Path::mkpath([$source_subdir]);
    write_file($source_subdir, substr($hash, 4), 'use_utf8', $_[2])
        unless -e File::Spec::Functions::catfile($source_subdir, substr($hash, 4));
}

sub pack_files {
    my ($self, $force) = @_;

    $self->_load_manifest();

    my $glob = File::Spec::Functions::catfile(
        $self->{base_dir},
        '*',
        '*',
        '*'
    );
    my @loose_files = grep !/\.tmp$/, bsd_glob($glob);
    return if !$force &&
        @loose_files < 10_000 &&
        _total_size(\@loose_files) < 10_000_000;
    my ($archive, $estimated_size);

    for my $fullpath (@loose_files) {
        my $relpath = File::Spec::Functions::abs2rel($fullpath, $self->{base_dir});
        next unless $relpath =~ m{^[0-9a-fA-F/\\]+$};
        my $hash = $relpath =~ tr{/\\}{}dr;
        my $packed = pack "H*", $hash;

        next if $self->{source_map}{$packed};
        if ($archive && $estimated_size >= 100_000_000) {
            $self->_save_archive($archive);
            $archive = $estimated_size = undef;
        }
        $archive ||= Archive::Zip->new;
        my $size = -s $fullpath;
        my $compression = $size >= 200 ? 6 : 0;
        $archive->addFile($fullpath, $relpath, $compression);
        $estimated_size += $compression ? $size / 10 : $size;
    }

    if ($archive) {
        $self->_save_archive($archive);
    }

    $self->_build_manifest();

    unlink @loose_files;
    # will only remove empty directories
    rmdir $_ for bsd_glob(File::Spec::Functions::catdir(
        $self->{base_dir},
        '*',
        '*',
    ));
    rmdir $_ for bsd_glob(File::Spec::Functions::catdir(
        $self->{base_dir},
        '*',
    ));
}

sub _load_manifest {
    my ($self) = @_;
    my $manifest = File::Spec::Functions::catfile(
        $self->{base_dir},
        'archives',
        'manifest',
    );

    if (!-f $manifest) {
        $self->{pack_files} = [];
        $self->{source_map} = {};
        $self->{manifest} = '';
    } else {
        my $contents = read_file($manifest);

        return if $self->{manifest} eq 'contents';

        my @files = split /\n/, $contents;
        my %source_map;
        my @archives = grep $_, map {
            my $fullpath = File::Spec::Functions::catfile(
                $self->{base_dir},
                'archives',
                $_,
            );

            if (-f $fullpath) {
                Archive::Zip->new($fullpath);
            } else {
                undef
            }
        } @files;

        for my $i (0 .. $#archives) {
            my $archive = $archives[$i];

            for my $member ($archive->memberNames) {
                my $hash = $member =~ tr{/}{}dr;

                $source_map{pack 'H*', $hash} = $i + 1;
            }
        }

        $self->{pack_files} = [undef, @archives];
        $self->{source_map} = \%source_map;
        $self->{manifest} = $contents;
    }
}

sub _build_manifest {
    my ($self) = @_;
    my $archives_dir = File::Spec::Functions::catfile(
        $self->{base_dir},
        'archives',
    );
    my @zip_files = bsd_glob(File::Spec::Functions::catfile(
        $archives_dir,
        '*.zip',
    ));

    my $manifest = join "\n", sort map {
        File::Spec::Functions::abs2rel($_, $archives_dir)
    } @zip_files;

    write_file($archives_dir, 'manifest', undef, $manifest)
}

sub _save_archive {
    my ($self, $archive) = @_;
    my $archives_dir = File::Spec::Functions::catfile(
        $self->{base_dir},
        'archives',
    );

    for (;;) {
        my $target = sprintf 'pack%06d.zip', rand(100000);
        my $name = File::Spec::Functions::catfile(
            $archives_dir,
            $target,
        );
        my $tmpname = File::Spec::Functions::catfile(
            $archives_dir,
            $target . '.tmp',
        );

        next if -f $name;
        File::Path::mkpath($archives_dir);
        my $status = $archive->writeToFileNamed($tmpname);
        die "Error while writing pack" if $status != AZ_OK;

        rename($tmpname, $name);
        last;
    }
}

sub _get_source_from_pack {
    my ($self, $hash, $archive) = @_;
    my $path = join '/',
        substr($hash, 0, 2),
        substr($hash, 2, 2),
        substr($hash, 4);

    return $archive->contents($path);
}

sub _total_size {
    my ($files) = @_;
    my $total = 0;

    $total += -s $_ for @$files;

    return $total;
}

1;
