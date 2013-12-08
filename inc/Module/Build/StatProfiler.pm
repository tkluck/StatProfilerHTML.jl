package Module::Build::StatProfiler;

use strict;
use warnings;
use parent qw(Module::Build::WithXSpp);

sub new {
    my ($class, %args) = @_;

    return $class->SUPER::new(
        %args,
        extra_linker_flags => [qw(-lrt)],
    );
}

1;
