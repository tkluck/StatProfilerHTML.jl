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

sub _sparse {
    my (@range) = @_;

    return map +("(eval $_)" => sha1_hex("eval $_")), @range;
}

# lexicographic order
{
    my $s1 = Devel::StatProfiler::EvalSource->new;

    _add_sources($s1, 9..11);
    $s1->_pack_data;
    eq_or_diff($s1->{all}{fake_process}{1}, {
        sparse  => {},
        first   => 9,
        packed  => _packed(9..11),
    });
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

# merging two unpacked objects
{
    my $s1 = Devel::StatProfiler::EvalSource->new;
    my $s2 = Devel::StatProfiler::EvalSource->new;

    _add_sources($s1, 7..8);
    _add_sources($s2, 10..11);
    $s1->_merge_source($s2->{all});

    eq_or_diff($s1->{all}{fake_process}{1}, {
        sparse  => { _sparse(7..8, 10..11) },
    });
}

# merging packed into unpacked
{
    my $s1 = Devel::StatProfiler::EvalSource->new;
    my $s2 = Devel::StatProfiler::EvalSource->new;

    _add_sources($s1, 7..8);
    _add_sources($s2, 10..11);
    $s2->_pack_data;
    $s1->_merge_source($s2->{all});

    eq_or_diff($s1->{all}{fake_process}{1}, {
        sparse  => { _sparse(7..8, 10..11) },
    });
}

# merging unpacked into packed
{
    my $s1 = Devel::StatProfiler::EvalSource->new;
    my $s2 = Devel::StatProfiler::EvalSource->new;

    _add_sources($s1, 7..8);
    _add_sources($s2, 10..11);
    $s1->_pack_data;
    $s1->_merge_source($s2->{all});

    eq_or_diff($s1->{all}{fake_process}{1}, {
        sparse  => { _sparse(10..11) },
        first   => 7,
        packed  => _packed(7..8),
    });
}

# merging packed into packed, with hole
{
    my $s1 = Devel::StatProfiler::EvalSource->new;
    my $s2 = Devel::StatProfiler::EvalSource->new;

    _add_sources($s1, 7..8);
    _add_sources($s2, 10..11);
    $s1->_pack_data;
    $s2->_pack_data;
    $s1->_merge_source($s2->{all});

    eq_or_diff($s1->{all}{fake_process}{1}, {
        sparse  => { _sparse(10..11) },
        first   => 7,
        packed  => _packed(7..8),
    });
}

# merging packed into packed, contiguous
{
    my $s1 = Devel::StatProfiler::EvalSource->new;
    my $s2 = Devel::StatProfiler::EvalSource->new;

    _add_sources($s1, 7..8);
    _add_sources($s2, 9..10);
    $s1->_pack_data;
    $s2->_pack_data;
    $s1->_merge_source($s2->{all});

    eq_or_diff($s1->{all}{fake_process}{1}, {
        sparse  => {},
        first   => 7,
        packed  => _packed(7..10),
    });
}

done_testing();
