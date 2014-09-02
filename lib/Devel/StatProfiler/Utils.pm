package Devel::StatProfiler::Utils;

use strict;
use warnings;
use autodie qw(open close rename);

use File::Spec::Functions ();
use Fcntl qw(O_WRONLY O_CREAT O_EXCL);
use Errno ();
use Exporter qw(import);
use Digest::SHA qw(sha1_hex);

our @EXPORT_OK = qw(
    check_serializer read_data read_file write_data write_data_part write_file
    utf8_sha1_hex
);

my ($SEREAL_ENCODER, $SEREAL_DECODER);

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

sub write_data_part {
    my ($serializer, $dir, $file_base, $data) = @_;
    my ($fh, $tmppath, $path) = _output_file($dir, $file_base);

    _write_and_rename($serializer, $fh, $tmppath, $path, $data);
}

sub write_data {
    my ($serializer, $dir, $file, $data) = @_;
    my $full_tmppath = File::Spec::Functions::catfile($dir, "_$file.tmp");
    my $full_path = File::Spec::Functions::catfile($dir, $file);
    open my $fh, '>', $full_tmppath;

    _write_and_rename($serializer, $fh, $full_tmppath, $full_path, $data);
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
            return ($fh, $tmppath, $path);
        }
        if ($! != Errno::EEXIST) {
            die "Error while opening report file: $!";
        }
    }

    die "Can't get here";
}

sub utf8_sha1_hex {
    my ($value) = @_;

    utf8::encode($value) if utf8::is_utf8($value);

    return sha1_hex($value);
}

1;
