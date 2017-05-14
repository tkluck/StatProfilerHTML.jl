package Devel::StatProfiler::Reader::Text;

use 5.12.0;
use warnings;

use Devel::StatProfiler::Reader;

sub new {
    my ($class, $fh)= @_;
    return bless {
        fh => $fh,
    }, $class;
}

sub get_genealogy_info {
    return [1,1,0,0];
}

sub get_custom_metadata {
    return {};
}

sub get_source_code {
    return {};
}

sub read_trace {
    my ($self) = @_;
    my $fh = $self->{fh};

    my @frames;
    LINE: while(my $line = <$fh>) {
        if($line eq "\n") {
            last LINE;
        }
        if($line =~ /^(.*)\t(.*)\t(.*)\t(.*)$/) {
            my $file = $1;
            my $line_number = $2;
            my $func = $3;
            my $func_line = $4;

            push @frames, bless {
                package    => "package",
                sub_name   => $func,
                fq_sub_name=> $func,
                file       => $file,
                line       => 0+$line_number,
                first_line => 0+$func_line,
            }, 'Devel::StatProfiler::StackFrame';
        }
    }

    if(@frames) {
        return bless {
            weight => 1,
            frames => \@frames,
            op_name => "",

            # not sure what these do:
            metadata => {},
            sections_changed => undef,
            metadata_changed => undef,
        }, 'Devel::StatProfiler::StackTrace';
    } else {
        return;
    }
}


1; # satisfy require
