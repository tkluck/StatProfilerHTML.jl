package Devel::StatProfiler::Test;

use strict;
use warnings;

require Devel::StatProfiler;

package Devel::StatProfiler::Test::TiedScalar;

use Time::HiRes qw(usleep);

sub TIESCALAR {
    return bless \my $self, __PACKAGE__;
}

sub FETCH {
    usleep(50000);
}

package Devel::StatProfiler::Test::TiedHash;

# the rest is implemented in XS
sub TIEHASH {
    return bless \my $self, __PACKAGE__;
}

1;
