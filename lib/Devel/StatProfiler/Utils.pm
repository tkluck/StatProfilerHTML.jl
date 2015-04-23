package Devel::StatProfiler::Utils;

use strict;
use warnings;
use autodie qw(open close rename);

use File::Spec::Functions ();
use Fcntl qw(O_WRONLY O_CREAT O_EXCL);
use Errno ();
use Exporter qw(import);
use Digest::SHA qw(sha1 sha1_hex);

our @EXPORT_OK = qw(
    check_serializer
    read_data
    read_file
    state_dir
    state_file
    state_file_shard
    utf8_sha1
    utf8_sha1_hex
    write_data
    write_data_any
    write_data_part
    write_file
);

my ($SEREAL_ENCODER, $SEREAL_DECODER);

sub state_dir {
    my ($obj, $is_part) = @_;
    die "first parameter of state_dir() must be an object" unless ref $obj;
    die ref($obj), " passed to state_dir() is missing the root_dir attribute"
        unless $obj->{root_dir};

    if ($is_part) {
        File::Spec::Functions::catdir($obj->{parts_dir} // $obj->{root_dir}, '__state__', 'parts');
    } else {
        File::Spec::Functions::catdir($obj->{root_dir}, '__state__');
    }
}

sub _state_file {
    my ($obj, $is_part, $file) = @_;
    die "first parameter of state_file() must be an object" unless ref $obj;
    die ref($obj), " passed to state_file() is missing the root_dir attribute"
        unless $obj->{root_dir};

    if ($is_part) {
        File::Spec::Functions::catfile($obj->{parts_dir} // $obj->{root_dir}, '__state__', 'parts', $file);
    } else {
        File::Spec::Functions::catfile($obj->{root_dir}, '__state__', $file);
    }
}

sub state_file {
    my ($obj, $is_part, $file) = @_;
    die "first parameter of state_file() must be an object" unless ref $obj;
    die ref($obj), " passed to state_file() is missing the root_dir attribute"
        unless $obj->{root_dir};
    die ref($obj), " passed to state_file() is missing the shard attribute"
        unless $obj->{shard};

    my $file_base = $file =~ s/\.\*$// ? "$file.$obj->{shard}.*" : "$file.$obj->{shard}";
    if ($is_part) {
        File::Spec::Functions::catfile($obj->{parts_dir} // $obj->{root_dir}, '__state__', 'parts', $file_base);
    } else {
        File::Spec::Functions::catfile($obj->{root_dir}, '__state__', $file_base);
    }
}

sub check_serializer {
    my ($serializer) = @_;

    if ($serializer eq 'storable') {
        require Storable;
    } elsif ($serializer eq 'sereal') {
        require Sereal;

        $SEREAL_ENCODER = Sereal::Encoder->new({
            snappy         => 1,
        });
        $SEREAL_DECODER = Sereal::Decoder->new;
    } else {
        die "Unsupported serializer format '$serializer'";
    }
}

sub read_data {
    my ($serializer, $file) = @_;
    open my $fh, '<', $file;

    if ($serializer eq 'storable') {
        return Storable::fd_retrieve($fh);
    } elsif ($serializer eq 'sereal') {
        my ($data, $read);

        1 while ($read = $fh->read($data, 256 * 1024, length $data));
        die "Error while reading Sereal-ized data" if !defined $read;

        return $SEREAL_DECODER->decode($data);
    } else {
        die "Unsupported serializer format '$serializer'";
    }
}

sub write_data_any {
    if (shift) {
        write_data_part(@_);
    } else {
        write_data(@_);
    }
}

sub write_data_part {
    my ($obj, $dir, $file_base, $data) = @_;
    die "first parameter of write_data_part() must be an object" unless ref $obj;
    die ref($obj), " passed to write_data_part() is missing the serializer attribute"
        unless $obj->{serializer};
    die ref($obj), " passed to write_data_part() is missing the shard attribute"
        unless $obj->{shard};

    my $subdir = File::Spec::Functions::catdir($dir, sprintf "%02x", $$ % 256);
    File::Path::mkpath([$subdir]);

    my ($fh, $tmppath, $path) = _output_file($subdir, "$file_base.$obj->{shard}");
    _write_and_rename($obj->{serializer}, $fh, $tmppath, $path, $data);
}

sub write_data {
    my ($obj, $dir, $file, $data) = @_;
    die "first parameter of write_data() must be an object" unless ref $obj;
    die ref($obj), " passed to write_data() is missing the serializer attribute"
        unless $obj->{serializer};
    die ref($obj), " passed to write_data() is missing the shard attribute"
        unless $obj->{shard};

    my $file_base = "$file.$obj->{shard}";
    my $full_tmppath = File::Spec::Functions::catfile($dir, "_$file_base.tmp");
    my $full_path = File::Spec::Functions::catfile($dir, $file_base);
    open my $fh, '>', $full_tmppath;

    _write_and_rename($obj->{serializer}, $fh, $full_tmppath, $full_path, $data);
}

sub write_file {
    my ($dir, $file, $utf8, $data) = @_;
    my ($fh, $tmppath, undef) = _output_file($dir, $file);

    binmode $fh, ':utf8' if $utf8;
    $fh->print($data) or die "Error while writing file data";
    close $fh;
    rename $tmppath, File::Spec::Functions::catfile($dir, $file);
}

sub read_file {
    my ($file, $utf8) = @_;
    local $/;

    open my $fh, '<', $file;
    binmode $fh, ':utf8' if $utf8;
    return readline $fh;
}

sub _write_and_rename {
    my ($serializer, $fh, $tmppath, $path, $data) = @_;

    if ($serializer eq 'storable') {
        Storable::nstore_fd($data, $fh)
            or die "Internal error in Storable::nstore_fd"
    } elsif ($serializer eq 'sereal') {
        $fh->print($SEREAL_ENCODER->encode($data))
            or die "Error while writing Sereal-ized data";
    } else {
        die "Unsupported serializer format '$serializer'";
    }

    close $fh;
    rename $tmppath, $path;
}

sub _output_file {
    my ($dir, $file_base) = @_;

    for (;;) {
        my $suffix = int(rand(2 ** 31));
        my $tmppath = File::Spec::Functions::catfile($dir, "_$file_base.$suffix.tmp");
        my $path = File::Spec::Functions::catfile($dir, "$file_base.$suffix");

        if (sysopen my $fh, $tmppath, O_WRONLY|O_CREAT|O_EXCL) {
            if (-f $path) {
                unlink $tmppath;
                next;
            }
            return ($fh, $tmppath, $path);
        }
        if ($! != Errno::EEXIST) {
            die "Error while opening report file: $!";
        }
    }

    die "Can't get here";
}

sub utf8_sha1 {
    my ($value) = @_;

    utf8::encode($value) if utf8::is_utf8($value);

    return sha1($value);
}

sub utf8_sha1_hex {
    my ($value) = @_;

    utf8::encode($value) if utf8::is_utf8($value);

    return sha1_hex($value);
}

1;
