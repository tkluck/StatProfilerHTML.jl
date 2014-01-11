package Devel::StatProfiler::SectionGuard;
use 5.12.0;
use warnings;

sub new {
  my $class = shift;
  my $self = bless({@_} => $class);
  Devel::StatProfiler::start_section($self->{section_name});
  return $self;
}

sub section_name { $_[0]->{section_name} }

sub DESTROY {
  my $self = shift;
  Devel::StatProfiler::end_section($self->{section_name});
}

1;
