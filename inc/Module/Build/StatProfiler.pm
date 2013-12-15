package Module::Build::StatProfiler;

use strict;
use warnings;
use parent qw(Module::Build::WithXSpp);

sub new {
    my ($class, %args) = @_;

    return $class->SUPER::new(
        %args,
        share_dir          => 'share',
        extra_linker_flags => [qw(-lrt)],
    );
}

1;
