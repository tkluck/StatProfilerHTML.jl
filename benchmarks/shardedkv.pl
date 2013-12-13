use 5.12.0;
use warnings;
use ShardedKV;
use ShardedKV::Continuum::StaticMapping;

# Very simple benchmark that should primarily stress the usual Perl OO overhead
# of methods dispatch, function calls, and hash accesses.

run_skv_benchmark($ARGV[0] // 1e5);

sub run_skv_benchmark {
  my ($count) = @_;
  my $continuum = ShardedKV::Continuum::StaticMapping->new(
    num_significant_bits => 10, # 2**10 == up to 1024 tables/shards
    from => [
      [0, 255, "shard1"],
      [256, 511, "shard2"],
      [512, 767, "shard3"],
      [768, 1023, "shard4"],
    ],
  );


  my %storages = (
    map {$_ => ShardedKV::Storage::Memory->new}
    qw(shard1 shard2 shard3 shard4)
  );

  my $skv = ShardedKV->new(
    storages => \%storages,
    continuum => $continuum,
  );

  for (1..$count) {
    $skv->set("foo$_", "VALUE");
    my $value = $skv->get("foo$_");
    $skv->delete("foo$_");
  }
}

