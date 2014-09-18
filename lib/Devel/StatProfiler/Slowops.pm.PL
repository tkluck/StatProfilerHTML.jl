#!/usr/bin/env perl

use strict;
use warnings;
use autodie qw(open);

use Opcode qw(opset opset_to_ops);

open my $out, '>', $ARGV[0];

my @ops = opset_to_ops(
    opset(
        ":base_io",
        ":filesys_read",
        ":filesys_write",
        ":filesys_open",
        ":sys_db",
        ":subprocess",
        ":others",
        qw(match subst substcont qr regcomp prtf crypt chdir flock ioctl
           socket getpeername ssockopt bind connect listen accept shutdown
           gsockopt getsockname sleep sort pack unpack syscall dump chroot
           dbmopen dbmclose lock sselect select),
        qw(!fileno !require !dofile !fork)
    )
);

print $out <<'EOT';
package Devel::StatProfiler::Slowops;

use strict;
use warnings;

our @OPS = qw(
EOT

print $out "    $_\n" for sort @ops;

print $out <<'EOT';
);

1;
EOT
