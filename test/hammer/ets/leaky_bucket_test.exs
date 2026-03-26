defmodule Hammer.ETS.LeakyBucketTest do
  use ExUnit.Case, async: true
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

      assert {:deny, 1000} =
               LeakyBucket.hit(table, key, leak_rate, capacity, 1)

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
