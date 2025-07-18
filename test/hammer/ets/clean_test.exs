defmodule Hammer.ETS.CleanTest do
  use ExUnit.Case, async: true

  defmodule RateLimit do
    use Hammer, backend: :ets
  end

  defmodule RateLimitSlidingWindow do
    use Hammer, backend: :ets, algorithm: :sliding_window
  end

  defmodule RateLimitLeakyBucket do
    use Hammer, backend: :ets, algorithm: :leaky_bucket
  end

  defmodule RateLimitTokenBucket do
    use Hammer, backend: :ets, algorithm: :token_bucket
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
    start_supervised!({RateLimit, clean_period: 100})

    key = "key"
    scale = 100
    count = 10

    assert {:allow, 1} = RateLimit.hit(key, scale, count)

    assert [_] = :ets.tab2list(RateLimit)

    # Wait for cleanup to occur by polling the table
    eventually(fn ->
      :ets.tab2list(RateLimit) == []
    end)
  end

  test "cleaning works for sliding window" do
    start_supervised!({RateLimitSlidingWindow, clean_period: 100})

    key = "key"
    scale = 100
    count = 10

    assert {:allow, 1} = RateLimitSlidingWindow.hit(key, scale, count)

    assert [_] = :ets.tab2list(RateLimitSlidingWindow)

    # Wait for cleanup to occur by polling the table
    eventually(fn ->
      :ets.tab2list(RateLimitSlidingWindow) == []
    end)
  end

  test "cleaning works for token bucket" do
    start_supervised!({RateLimitTokenBucket, clean_period: 100})

    key = "key"
    refill_rate = 1
    capacity = 10

    assert {:allow, 9} = RateLimitTokenBucket.hit(key, refill_rate, capacity, 1)

    assert [_] = :ets.tab2list(RateLimitTokenBucket)

    # Wait for cleanup to occur by polling the table
    eventually(fn ->
      :ets.tab2list(RateLimitTokenBucket) == []
    end)
  end

  test "cleaning works for leaky bucket" do
    start_supervised!({RateLimitLeakyBucket, clean_period: 100})

    key = "key"
    leak_rate = 1
    capacity = 10

    assert {:allow, 1} = RateLimitLeakyBucket.hit(key, leak_rate, capacity, 1)

    assert [_] = :ets.tab2list(RateLimitLeakyBucket)

    # Wait for cleanup to occur by polling the table
    eventually(fn ->
      :ets.tab2list(RateLimitLeakyBucket) == []
    end)
  end
end
