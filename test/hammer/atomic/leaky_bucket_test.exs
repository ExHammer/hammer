defmodule Hammer.Atomic.LeakyBucketTest do
  use ExUnit.Case, async: true
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
end
