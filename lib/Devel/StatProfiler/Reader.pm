package Devel::StatProfiler::Reader;
# ABSTRACT: read profiler output

use strict;
use warnings;

require Devel::StatProfiler; # load XS but don't start profiling

package Devel::StatProfiler::StackFrame;

sub id { $_[0]->{id} }
sub subroutine { $_[0]->{subroutine} }
sub file { $_[0]->{file} }
sub line { $_[0]->{line} }
sub kind { $_[0]->{line} == -2 ? 2 :
           $_[0]->{line} == -1 ? 1 :
                                 0 }

package Devel::StatProfiler::StackTrace;

sub weight { $_[0]->{weight} }
sub frames { $_[0]->{frames} }
sub op_name { $_[0]->{op_name} }

1;
