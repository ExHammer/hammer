defmodule Hammer.Atomic.TokenBucketTest do
  use ExUnit.Case, async: true
  import Bitwise
  alias Hammer.Atomic.TokenBucket

  defmodule RateLimitTokenBucket do
    use Hammer, backend: :atomic, algorithm: :token_bucket
  end

  setup do
    table = :ets.new(:hammer_atomic_token_bucket_test, TokenBucket.ets_opts())
    {:ok, table: table}
  end

  describe "hit/get" do
    test "returns {:allow, 9} tuple on first access", %{table: table} do
      key = "key"
      refill_rate = 10
      capacity = 10

      assert {:allow, 9} = TokenBucket.hit(table, key, refill_rate, capacity, 1)
    end

    test "returns {:allow, 6} tuple on in-limit checks", %{table: table} do
      key = "key"
      refill_rate = 2
      capacity = 10

      assert {:allow, 9} = TokenBucket.hit(table, key, refill_rate, capacity, 1)
      assert {:allow, 8} = TokenBucket.hit(table, key, refill_rate, capacity, 1)
      assert {:allow, 7} = TokenBucket.hit(table, key, refill_rate, capacity, 1)
      assert {:allow, 6} = TokenBucket.hit(table, key, refill_rate, capacity, 1)
    end

    test "returns expected tuples on mix of in-limit and out-of-limit checks", %{table: table} do
      key = "key"
      refill_rate = 1
      capacity = 2

      assert {:allow, 1} = TokenBucket.hit(table, key, refill_rate, capacity, 1)
      assert {:allow, 0} = TokenBucket.hit(table, key, refill_rate, capacity, 1)

      assert {:deny, retry_after} = TokenBucket.hit(table, key, refill_rate, capacity, 1)
      assert retry_after in 1..1000

      assert {:deny, _retry_after} = TokenBucket.hit(table, key, refill_rate, capacity, 1)
    end

    test "returns expected tuples after waiting for the next window", %{table: table} do
      key = "key"
      refill_rate = 1
      capacity = 2

      assert {:allow, 1} = TokenBucket.hit(table, key, refill_rate, capacity, 1)
      assert {:allow, 0} = TokenBucket.hit(table, key, refill_rate, capacity, 1)

      assert {:deny, retry_after} =
               TokenBucket.hit(table, key, refill_rate, capacity, 1)

      :timer.sleep(retry_after)

      assert {:allow, 0} = TokenBucket.hit(table, key, refill_rate, capacity, 1)

      assert {:deny, _retry_after} =
               TokenBucket.hit(table, key, refill_rate, capacity, 1)
    end

    # The tests below pin the refill clock's bookkeeping directly rather than
    # measuring throughput. They seed the bucket's clock at a known offset from
    # `now` and assert what is written back, so they are deterministic.
    test "carries the sub-token remainder instead of discarding it", %{table: table} do
      key = "key"
      # One token every ~18.18ms.
      refill_rate = 55
      capacity = 10

      seeded_at = System.system_time(:millisecond) - 30
      seed(table, key, 5, seeded_at)

      # 30ms accrues trunc(30 * 55 / 1000) == 1 token, which is worth 18ms.
      # The remaining ~12ms must stay on the clock for the next hit.
      assert {:allow, 5} = TokenBucket.hit(table, key, refill_rate, capacity, 1)
      assert {5, clock(seeded_at + 18)} == stored(table, key)
    end

    test "does not reset the clock when a full bucket accrued no new tokens", %{table: table} do
      key = "key"
      refill_rate = 55
      capacity = 10

      seeded_at = System.system_time(:millisecond) - 10
      seed(table, key, capacity, seeded_at)

      # 10ms accrues no whole token. Nothing overflowed, so the 10ms is still
      # owed to the level this hit draws down.
      assert {:allow, 9} = TokenBucket.hit(table, key, refill_rate, capacity, 1)
      assert {9, clock(seeded_at)} == stored(table, key)
    end

    test "resets the clock when an idle bucket overflows", %{table: table} do
      key = "key"
      refill_rate = 55
      capacity = 10

      now = System.system_time(:millisecond)
      seed(table, key, capacity, now - 5_000)

      # 5s would accrue 275 tokens into a bucket that holds 10. The surplus is
      # discarded, so the clock must snap forward or the bucket banks credit.
      assert {:allow, 9} = TokenBucket.hit(table, key, refill_rate, capacity, 1)

      {9, stored_at} = stored(table, key)
      assert (stored_at - now &&& 0xFFFFFFFF) in 0..1000
    end

    test "a caller paced at the nominal refill rate does not starve", %{table: table} do
      key = "key"
      refill_rate = 55
      capacity = 10

      # 60 hits spaced 18ms apart (a token period is ~18.18ms), simulated by
      # rewinding the bucket's clock. Each hit credits exactly one token, so a
      # lossless bucket holds its level instead of draining.
      seed(table, key, capacity, System.system_time(:millisecond))

      for step <- 1..60 do
        rewind(table, key, 18)

        assert {:allow, _} = TokenBucket.hit(table, key, refill_rate, capacity, 1),
               "denied at step #{step} -- the bucket drained while paced under its own refill rate"
      end

      {final_level, _} = stored(table, key)
      assert final_level >= div(capacity, 2)
    end

    test "refills at sub-second granularity when refill_rate > capacity", %{table: table} do
      key = "key"
      refill_rate = 100
      capacity = 10

      seed(table, key, 0, System.system_time(:millisecond) - 30)

      # 30ms at 100 tokens/sec is 3 tokens: no waiting for a second boundary.
      assert {:allow, 0} = TokenBucket.hit(table, key, refill_rate, capacity, 3)
    end

    test "the deny wait is the real time until the bucket holds enough tokens",
         %{table: table} do
      key = "key"
      refill_rate = 55
      capacity = 10

      seed(table, key, 0, System.system_time(:millisecond))

      # Short exactly one token: ceil(1000 / 55) == 19ms.
      assert {:deny, 19} = TokenBucket.hit(table, key, refill_rate, capacity, 1)

      # The wait scales with how many tokens the cost is short of.
      assert {:deny, 91} = TokenBucket.hit(table, key, refill_rate, capacity, 5)
    end

    test "the advertised wait is sufficient across rates, costs and deficits", %{table: table} do
      for refill_rate <- [1, 2, 3, 7, 55, 100, 999, 1_000_000],
          capacity <- [1, 10, 1000],
          cost <- [1, 3, capacity],
          cost <= capacity,
          starting_level <- [0, div(cost, 2)],
          starting_level < cost do
        key = "sufficient:#{refill_rate}:#{capacity}:#{cost}:#{starting_level}"
        seed(table, key, starting_level, System.system_time(:millisecond))

        assert {:deny, wait} = TokenBucket.hit(table, key, refill_rate, capacity, cost)
        assert wait >= 1

        # Rewind the clock by exactly the advertised wait -- the state the
        # caller would find having slept precisely that long.
        rewind(table, key, wait)

        assert {:allow, _} = TokenBucket.hit(table, key, refill_rate, capacity, cost),
               "wait of #{wait}ms was too short for rate=#{refill_rate} " <>
                 "cap=#{capacity} cost=#{cost} level=#{starting_level}"
      end
    end

    test "a bucket idle for longer than its 32-bit clock can express is refilled",
         %{table: table} do
      key = "key"

      # The packed clock is the low 32 bits of the millisecond time, so on its
      # own it cannot tell 30 days from a clock that ran backwards.
      seed(table, key, 0, System.system_time(:millisecond) - :timer.hours(24 * 30))

      assert {:allow, 999} = TokenBucket.hit(table, key, 1, 1000, 1)
    end

    test "a stored clock ahead of the caller's credits nothing", %{table: table} do
      key = "key"

      # A concurrent hit that read the time later can store a clock slightly
      # ahead of ours. That must read as no time elapsed, not as a full refill.
      seed(table, key, 0, System.system_time(:millisecond) + 500)

      assert {:deny, _} = TokenBucket.hit(table, key, 1000, 1000, 1)
    end

    test "a refill rate of 0 still denies with a flat second", %{table: table} do
      key = "key"
      seed(table, key, 0, System.system_time(:second))

      assert {:deny, 1000} = TokenBucket.hit(table, key, 0, 10, 1)
    end

    test "handles costs greater than 1 correctly", %{table: table} do
      key = "key"
      refill_rate = 2
      capacity = 10

      # First hit with cost of 3 should succeed and leave 7 tokens
      assert {:allow, 7} = TokenBucket.hit(table, key, refill_rate, capacity, 3)

      # Second hit with cost of 4 should succeed and leave 3 tokens
      assert {:allow, 3} = TokenBucket.hit(table, key, refill_rate, capacity, 4)

      # Third hit with cost of 4 should be denied (only 3 tokens left)
      assert {:deny, _retry_after} = TokenBucket.hit(table, key, refill_rate, capacity, 4)

      # Small cost of 2 should still succeed since we have 3 tokens
      assert {:allow, 1} = TokenBucket.hit(table, key, refill_rate, capacity, 2)
    end

    test "race condition", %{table: table} do
      key = "key"
      # No refill to avoid timing issues
      refill_rate = 0
      capacity = 4

      # Use tasks to better control process lifecycle
      task1 =
        Task.async(fn ->
          for _ <- 1..2 do
            TokenBucket.hit(table, key, refill_rate, capacity, 1)
          end
        end)

      task2 =
        Task.async(fn ->
          for _ <- 1..2 do
            TokenBucket.hit(table, key, refill_rate, capacity, 1)
          end
        end)

      # Wait for both tasks to complete
      Task.await(task1, 5000)
      Task.await(task2, 5000)

      # Check the final count - should be 0 after consuming 4 tokens from capacity 4
      assert TokenBucket.get(table, key) == 0
    end
  end

  describe "get" do
    test "get returns current bucket level", %{table: table} do
      key = "key"
      refill_rate = 1
      capacity = 10

      assert TokenBucket.get(table, key) == 0

      assert {:allow, _} = TokenBucket.hit(table, key, refill_rate, capacity, 4)
      assert TokenBucket.get(table, key) == 6

      assert {:allow, _} = TokenBucket.hit(table, key, refill_rate, capacity, 3)
      assert TokenBucket.get(table, key) == 3
    end
  end

  # Publish a bucket holding `level` whose clock reads `timestamp` (ms), packed
  # the way the algorithm packs it: low 32 bits of the time high, level low.
  defp seed(table, key, level, timestamp) do
    atomic = :atomics.new(2, signed: false)
    :atomics.put(atomic, 1, clock(timestamp) <<< 32 ||| level)
    :atomics.put(atomic, 2, div(timestamp, 1000))
    :ets.insert(table, {key, atomic})
  end

  defp stored(table, key) do
    [{^key, atomic}] = :ets.lookup(table, key)
    packed = :atomics.get(atomic, 1)
    {packed &&& 0xFFFFFFFF, packed >>> 32}
  end

  # Move the bucket's clock back, as if the caller had slept `ms`.
  defp rewind(table, key, ms) do
    [{^key, atomic}] = :ets.lookup(table, key)
    {level, timestamp} = stored(table, key)
    :atomics.put(atomic, 1, clock(timestamp - ms) <<< 32 ||| level)
  end

  defp clock(timestamp), do: timestamp &&& 0xFFFFFFFF
end
