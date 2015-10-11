package Devel::StatProfiler::Reader;
# ABSTRACT: read profiler output

use strict;
use warnings;

require Devel::StatProfiler; # load XS but don't start profiling

sub get_reader_state {
    my ($self) = @_;

    return {
        metadata => { %{$self->get_custom_metadata} },
        sections => { %{$self->get_active_sections} },
    };
}

sub set_reader_state {
    my ($self, $state) = @_;

    %{$self->get_custom_metadata} = %{$state->{metadata}};
    %{$self->get_active_sections} = %{$state->{sections}};
}

package Devel::StatProfiler::StackFrame;

sub file { $_[0]->{file} }
sub file_pretty { $_[0]->{file_pretty} // $_[0]->{file} }
sub line { $_[0]->{line} }

sub package { $_[0]->{package} }
sub sub_name { $_[0]->{sub_name} }
sub sub_name_pretty { undef }
sub fq_sub_name { $_[0]->{fq_sub_name} }
sub uq_sub_name {
    ($_[0]->{file} || '(unknown)') . ':' .
    $_[0]->{fq_sub_name} .
    ($_[0]->{first_line} > 0 ? ':' . $_[0]->{first_line} : '')
}
sub first_line { $_[0]->{first_line} }
sub kind { $_[0]->{line} == -2 ? 2 :
           $_[0]->{line} == -1 ? 1 : # -1 means "XSUB"
                                 0 }
sub is_main { 0 }
sub is_eval { 0 }

package Devel::StatProfiler::MainStackFrame;

sub file { $_[0]->{file} }
sub file_pretty { $_[0]->{file_pretty} }
sub line { $_[0]->{line} }

sub package { '' }
sub sub_name { '' }
sub sub_name_pretty { '' }
sub fq_sub_name { '' }
sub uq_sub_name { $_[0]->{file} . ':main' }
sub first_line { 1 }
sub kind { 0 }
sub is_main { 1 }
sub is_eval { 0 }

package Devel::StatProfiler::EvalStackFrame;

our @ISA = qw(Devel::StatProfiler::MainStackFrame);

sub sub_name_pretty { $_[0]->{file_pretty} }
sub uq_sub_name { $_[0]->{file} . ':eval' }
sub is_main { 0 }
sub is_eval { 1 }

package Devel::StatProfiler::StackTrace;

sub weight { $_[0]->{weight} }
sub frames { $_[0]->{frames} }
sub op_name { $_[0]->{op_name} }
sub metadata { $_[0]->{metadata} }
sub sections_changed { $_[0]->{sections_changed} }
sub metadata_changed { $_[0]->{metadata_changed} }

1;
