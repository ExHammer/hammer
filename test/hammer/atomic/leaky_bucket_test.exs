defmodule Hammer.Atomic.LeakyBucketTest do
  use ExUnit.Case, async: true
  import Bitwise
  import Hammer.ClockTestHelpers
  alias Hammer.Atomic.LeakyBucket

  defmodule RateLimitLeakyBucket do
    use Hammer, backend: :atomic, algorithm: :leaky_bucket
  end

  setup do
    table = :ets.new(:hammer_atomic_leaky_bucket_test, LeakyBucket.ets_opts())
    {:ok, table: table}
  end

  describe "hit/get" do
    test "returns {:allow, 1} tuple on first access", %{table: table} do
      key = "key"
      leak_rate = 10
      capacity = 10

      assert {:allow, 1} = LeakyBucket.hit(table, key, leak_rate, capacity, 1)
    end

    test "returns {:allow, 4} tuple on in-limit checks", %{table: table} do
      key = "key"
      leak_rate = 2
      capacity = 10

      assert {:allow, 1} = LeakyBucket.hit(table, key, leak_rate, capacity, 1)
      assert {:allow, 2} = LeakyBucket.hit(table, key, leak_rate, capacity, 1)
      assert {:allow, 3} = LeakyBucket.hit(table, key, leak_rate, capacity, 1)
      assert {:allow, 4} = LeakyBucket.hit(table, key, leak_rate, capacity, 1)
    end

    test "returns expected tuples on mix of in-limit and out-of-limit checks", %{table: table} do
      key = "key"
      leak_rate = 1
      capacity = 2

      assert {:allow, 1} = LeakyBucket.hit(table, key, leak_rate, capacity, 1)
      assert {:allow, 2} = LeakyBucket.hit(table, key, leak_rate, capacity, 1)

      assert {:deny, retry_after} =
               LeakyBucket.hit(table, key, leak_rate, capacity, 1)

      assert retry_after in 1..1000

      assert {:deny, _retry_after} =
               LeakyBucket.hit(table, key, leak_rate, capacity, 1)
    end

    test "returns expected tuples after waiting for the next window", %{table: table} do
      key = "key"
      leak_rate = 1
      capacity = 2

      assert {:allow, 1} = LeakyBucket.hit(table, key, leak_rate, capacity, 1)
      assert {:allow, 2} = LeakyBucket.hit(table, key, leak_rate, capacity, 1)

      assert {:deny, retry_after} =
               LeakyBucket.hit(table, key, leak_rate, capacity, 1)

      :timer.sleep(retry_after)

      assert {:allow, 2} = LeakyBucket.hit(table, key, leak_rate, capacity, 1)

      assert {:deny, _retry_after} =
               LeakyBucket.hit(table, key, leak_rate, capacity, 1)
    end

    test "the deny wait is the real time until the bucket leaks below capacity",
         %{table: table} do
      await_fresh_second()
      key = "key"
      leak_rate = 1
      capacity = 2

      # 11 in a bucket of 2: ten more seconds of leaking before a hit is allowed.
      seed(table, key, 11, System.system_time(:second))

      assert {:deny, retry_after} = LeakyBucket.hit(table, key, leak_rate, capacity, 1)
      assert retry_after in 9001..10_000

      # A faster leak shortens the wait: ceil(10 / 5) == 2 seconds.
      assert {:deny, retry_after_fast} = LeakyBucket.hit(table, key, 5, capacity, 1)
      assert retry_after_fast in 1001..2000
    end

    test "the advertised wait is sufficient across rates, capacities and fill levels",
         %{table: table} do
      await_fresh_second()

      for leak_rate <- [1, 2, 3, 7, 55],
          capacity <- [1, 10, 1000],
          overfill <- [0, 1, 5, capacity] do
        key = "sufficient:#{leak_rate}:#{capacity}:#{overfill}"
        seed(table, key, capacity + overfill, System.system_time(:second))

        assert {:deny, wait} = LeakyBucket.hit(table, key, leak_rate, capacity, 1)
        assert wait >= 1

        # Rewind the stored clock by the advertised wait (in the whole seconds
        # the bucket counts in) -- the state a caller finds after sleeping it.
        rewind(table, key, ceil(wait / 1000))

        assert {:allow, _} = LeakyBucket.hit(table, key, leak_rate, capacity, 1),
               "wait of #{wait}ms was too short for rate=#{leak_rate} " <>
                 "cap=#{capacity} overfill=#{overfill}"
      end
    end

    test "a leak rate of 0 still denies with a flat second", %{table: table} do
      key = "key"
      seed(table, key, 5, System.system_time(:second))

      assert {:deny, 1000} = LeakyBucket.hit(table, key, 0, 2, 1)
    end

    test "race condition", %{table: table} do
      key = "key"
      leak_rate = 1
      capacity = 4

      # Use tasks to better control process lifecycle
      task1 =
        Task.async(fn ->
          for _ <- 1..2 do
            LeakyBucket.hit(table, key, leak_rate, capacity, 1)
          end
        end)

      task2 =
        Task.async(fn ->
          for _ <- 1..2 do
            LeakyBucket.hit(table, key, leak_rate, capacity, 1)
          end
        end)

      # Wait for both tasks to complete
      Task.await(task1, 5000)
      Task.await(task2, 5000)

      # Check the final count
      assert LeakyBucket.get(table, key) == 4
    end
  end

  describe "get" do
    test "get returns current bucket level", %{table: table} do
      key = "key"
      leak_rate = 1
      capacity = 10

      assert LeakyBucket.get(table, key) == 0

      assert {:allow, _} = LeakyBucket.hit(table, key, leak_rate, capacity, 4)
      assert LeakyBucket.get(table, key) == 4

      assert {:allow, _} = LeakyBucket.hit(table, key, leak_rate, capacity, 3)
      assert LeakyBucket.get(table, key) == 7
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
