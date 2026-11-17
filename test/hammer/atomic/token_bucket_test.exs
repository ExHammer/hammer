defmodule Hammer.Atomic.TokenBucketTest do
  use ExUnit.Case, async: true
  import Bitwise
  import Hammer.ClockTestHelpers
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

    test "the deny wait is the real time until the bucket holds enough tokens",
         %{table: table} do
      await_fresh_second()
      key = "key"
      refill_rate = 1
      capacity = 10

      seed(table, key, 0, System.system_time(:second))

      # Short five tokens at one token per second.
      assert {:deny, retry_after} = TokenBucket.hit(table, key, refill_rate, capacity, 5)
      assert retry_after in 4001..5000

      # A faster refill shortens the wait: ceil(5 / 3) == 2 seconds.
      assert {:deny, retry_after_fast} = TokenBucket.hit(table, key, 3, capacity, 5)
      assert retry_after_fast in 1001..2000
    end

    test "the advertised wait is sufficient across rates, costs and deficits", %{table: table} do
      await_fresh_second()

      for refill_rate <- [1, 2, 3, 7, 55],
          capacity <- [1, 10, 1000],
          cost <- [1, 3, capacity],
          cost <= capacity,
          starting_level <- [0, div(cost, 2)],
          starting_level < cost do
        key = "sufficient:#{refill_rate}:#{capacity}:#{cost}:#{starting_level}"
        seed(table, key, starting_level, System.system_time(:second))

        assert {:deny, wait} = TokenBucket.hit(table, key, refill_rate, capacity, cost)
        assert wait >= 1

        # Rewind the stored clock by the advertised wait (in the whole seconds
        # the bucket counts in) -- the state a caller finds after sleeping it.
        rewind(table, key, ceil(wait / 1000))

        assert {:allow, _} = TokenBucket.hit(table, key, refill_rate, capacity, cost),
               "wait of #{wait}ms was too short for rate=#{refill_rate} " <>
                 "cap=#{capacity} cost=#{cost} level=#{starting_level}"
      end
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

  # Publish a bucket holding `level` whose clock reads `timestamp` (seconds),
  # packed the way the algorithm packs it: timestamp high, level low.
  defp seed(table, key, level, timestamp) do
    atomic = :atomics.new(2, signed: false)
    :atomics.put(atomic, 1, timestamp <<< 32 ||| level)
    :atomics.put(atomic, 2, timestamp)
    :ets.insert(table, {key, atomic})
  end

  # Move the bucket's clock back, as if the caller had slept `seconds`.
  defp rewind(table, key, seconds) do
    [{^key, atomic}] = :ets.lookup(table, key)
    packed = :atomics.get(atomic, 1)
    level = packed &&& 0xFFFFFFFF
    :atomics.put(atomic, 1, ((packed >>> 32) - seconds) <<< 32 ||| level)
  end
end
