defmodule Hammer.Atomic.CleanTest do
  use ExUnit.Case, async: true

  defmodule RateAtomicLimit do
    use Hammer, backend: :atomic
  end

  defmodule RateAtomicLimitLeakyBucket do
    use Hammer, backend: :atomic, algorithm: :leaky_bucket
  end

  defmodule RateAtomicLimitTokenBucket do
    use Hammer, backend: :atomic, algorithm: :token_bucket
  end

  test "cleaning works for fix window/default ets backend" do
    start_supervised!({RateAtomicLimit, clean_period: 50, key_older_than: 10})

    key = "key"
    scale = 100
    count = 10

    assert {:allow, 1} = RateAtomicLimit.hit(key, scale, count)

    assert [_] = :ets.tab2list(RateAtomicLimit)

    :timer.sleep(150)

    assert :ets.tab2list(RateAtomicLimit) == []
  end

  test "cleaning works for token bucket" do
    start_supervised!({RateAtomicLimitTokenBucket, clean_period: 50, key_older_than: 10})

    key = "key"
    refill_rate = 1
    capacity = 10

    assert {:allow, 9} = RateAtomicLimitTokenBucket.hit(key, refill_rate, capacity, 1)

    assert [_] = :ets.tab2list(RateAtomicLimitTokenBucket)

    :timer.sleep(150)

    assert :ets.tab2list(RateAtomicLimitTokenBucket) == []
  end

  test "cleaning works for leaky bucket" do
    start_supervised!({RateAtomicLimitLeakyBucket, clean_period: 50, key_older_than: 10})

    key = "key"
    leak_rate = 1
    capacity = 10

    assert {:allow, 1} = RateAtomicLimitLeakyBucket.hit(key, leak_rate, capacity, 1)

    assert [_] = :ets.tab2list(RateAtomicLimitLeakyBucket)

    :timer.sleep(150)

    assert :ets.tab2list(RateAtomicLimitLeakyBucket) == []
  end
end
