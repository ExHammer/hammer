defmodule Hammer.ETS.LeakyBucketTest do
  use ExUnit.Case, async: true
  import Hammer.ClockTestHelpers
  alias Hammer.ETS.LeakyBucket

  defmodule RateLimitLeakyBucket do
    use Hammer, backend: :ets, algorithm: :leaky_bucket
  end

  setup do
    table = :ets.new(:hammer_leaky_bucket_test, LeakyBucket.ets_opts())
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

    test "denies a hit whose cost would take the level over capacity", %{table: table} do
      await_fresh_second()
      key = "key"
      leak_rate = 1
      capacity = 10

      assert {:allow, 8} = LeakyBucket.hit(table, key, leak_rate, capacity, 8)

      # 8 + 5 does not fit in 10, even though the bucket is not yet full.
      # Three must leak first: 2001..3000ms at one per second.
      assert {:deny, retry_after} = LeakyBucket.hit(table, key, leak_rate, capacity, 5)
      assert retry_after in 2001..3000

      # The denied hit added nothing, and a cost that fits is still allowed.
      assert LeakyBucket.get(table, key) == 8
      assert {:allow, 10} = LeakyBucket.hit(table, key, leak_rate, capacity, 2)
    end

    test "the deny wait is the real time until the bucket leaks below capacity",
         %{table: table} do
      await_fresh_second()
      key = "key"
      leak_rate = 1
      capacity = 2

      # 11 in a bucket of 2: ten more seconds of leaking before a hit is allowed.
      :ets.insert(table, {key, 11, System.system_time(:second)})

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
        :ets.insert(table, {key, capacity + overfill, System.system_time(:second)})

        assert {:deny, wait} = LeakyBucket.hit(table, key, leak_rate, capacity, 1)
        assert wait >= 1

        # Rewind the stored clock by the advertised wait (in the whole seconds
        # the bucket counts in) -- the state a caller finds after sleeping it.
        [{^key, level, last_update}] = :ets.lookup(table, key)
        :ets.insert(table, {key, level, last_update - ceil(wait / 1000)})

        assert {:allow, _} = LeakyBucket.hit(table, key, leak_rate, capacity, 1),
               "wait of #{wait}ms was too short for rate=#{leak_rate} " <>
                 "cap=#{capacity} overfill=#{overfill}"
      end
    end

    test "a stored clock ahead of the caller's leaks nothing and adds nothing",
         %{table: table} do
      key = "key"

      # A concurrent hit that read the time later, or a wall clock that stepped
      # back, leaves the stored clock ahead of ours. Negative elapsed time must
      # not be turned into a negative leak, which would raise the level.
      :ets.insert(table, {key, 5, System.system_time(:second) + 10})

      assert {:allow, 6} = LeakyBucket.hit(table, key, 100, 10, 1)
      assert {:allow, 7} = LeakyBucket.hit(table, key, 100, 10, 1)
    end

    test "a leak rate of 0 still denies with a flat second", %{table: table} do
      key = "key"
      :ets.insert(table, {key, 5, System.system_time(:second)})

      assert {:deny, 1000} = LeakyBucket.hit(table, key, 0, 2, 1)
    end
  end

  describe "race condition handling" do
    test "hit recovers when entry is deleted between insert_new and lookup", %{table: table} do
      key = "race_key"
      leak_rate = 10
      capacity = 10

      # Insert an entry, then delete it to simulate cleanup race
      :ets.insert(table, {key, 5, System.system_time(:second)})
      :ets.delete(table, key)

      # hit should handle the missing entry gracefully
      assert {:allow, 1} = LeakyBucket.hit(table, key, leak_rate, capacity, 1)
    end

    test "hit works on a fresh empty table", %{table: table} do
      key = "fresh_key"
      leak_rate = 10
      capacity = 10

      # Ensure key doesn't exist
      assert :ets.lookup(table, key) == []

      assert {:allow, 1} = LeakyBucket.hit(table, key, leak_rate, capacity, 1)
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
end
