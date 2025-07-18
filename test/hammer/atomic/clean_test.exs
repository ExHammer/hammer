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

  # Helper function to wait for a condition to be true
  defp eventually(fun, timeout \\ 5000, interval \\ 50) do
    eventually(fun, timeout, interval, System.monotonic_time(:millisecond))
  end

  defp eventually(fun, timeout, interval, start_time) do
    if fun.() do
      :ok
    else
      now = System.monotonic_time(:millisecond)

      if now - start_time > timeout do
        flunk("Condition not met within #{timeout}ms")
      else
        Process.sleep(interval)
        eventually(fun, timeout, interval, start_time)
      end
    end
  end

  test "cleaning works for fix window/default ets backend" do
    start_supervised!({RateAtomicLimit, clean_period: 50, key_older_than: 10})

    key = "key"
    scale = 100
    count = 10

    assert {:allow, 1} = RateAtomicLimit.hit(key, scale, count)

    assert [_] = :ets.tab2list(RateAtomicLimit)

    # Wait for cleanup to occur by polling the table
    eventually(fn ->
      :ets.tab2list(RateAtomicLimit) == []
    end)
  end

  test "cleaning works for token bucket" do
    start_supervised!({RateAtomicLimitTokenBucket, clean_period: 50, key_older_than: 10})

    key = "key"
    refill_rate = 1
    capacity = 10

    assert {:allow, 9} = RateAtomicLimitTokenBucket.hit(key, refill_rate, capacity, 1)

    assert [_] = :ets.tab2list(RateAtomicLimitTokenBucket)

    # Wait for cleanup to occur by polling the table
    eventually(fn ->
      :ets.tab2list(RateAtomicLimitTokenBucket) == []
    end)
  end

  test "cleaning works for leaky bucket" do
    start_supervised!({RateAtomicLimitLeakyBucket, clean_period: 50, key_older_than: 10})

    key = "key"
    leak_rate = 1
    capacity = 10

    assert {:allow, 1} = RateAtomicLimitLeakyBucket.hit(key, leak_rate, capacity, 1)

    assert [_] = :ets.tab2list(RateAtomicLimitLeakyBucket)

    # Wait for cleanup to occur by polling the table
    eventually(fn ->
      :ets.tab2list(RateAtomicLimitLeakyBucket) == []
    end)
  end
end
