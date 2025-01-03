defmodule Hammer.ETS.TokenBucketTest do
  use ExUnit.Case, async: true
  alias Hammer.ETS.TokenBucket

  defmodule RateLimitTokenBucket do
    use Hammer, backend: :ets, algorithm: :token_bucket
  end

  setup do
    table = :ets.new(:hammer_token_bucket_test, TokenBucket.ets_opts())
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

      assert {:deny, 1000} = TokenBucket.hit(table, key, refill_rate, capacity, 1)

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
end
