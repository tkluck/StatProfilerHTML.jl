#!/usr/bin/env perl
use t::lib::Test;

use Devel::StatProfiler::EvalSource;
use Digest::SHA qw(sha1_hex);

{
    package DummyReader;

    sub new {
        my $class = shift;

        return bless { @_ }, $class;
    }

    sub get_genealogy_info {
        return ['fake_process', 1];
    }

    sub get_source_code { $_[0]->{source_code} }
}

sub _add_sources {
    my ($es, @range) = @_;

    $es->add_sources_from_reader(DummyReader->new(
        source_code => {
            map +("(eval $_)" => "eval $_"), @range,
        },
    ));
}

sub _packed {
    my (@range) = @_;

    return join '', map +(pack "H*", sha1_hex("eval $_")), @range;
}

# repeated packing
{
    my $s1 = Devel::StatProfiler::EvalSource->new;

    _add_sources($s1, 7..8);
    $s1->_pack_data;
    eq_or_diff($s1->{all}{fake_process}{1}, {
        sparse  => {},
        first   => 7,
        packed  => _packed(7..8),
    });

    _add_sources($s1, 9..10);
    $s1->_pack_data;
    eq_or_diff($s1->{all}{fake_process}{1}, {
        sparse  => {},
        first   => 7,
        packed  => _packed(7..10),
    });
}

done_testing();
