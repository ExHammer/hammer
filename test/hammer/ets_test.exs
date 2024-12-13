defmodule Hammer.ETSTest do
  use ExUnit.Case, async: true

  defmodule RateLimit do
    use Hammer, backend: :ets
  end

  setup do
    start_supervised!(RateLimit)
    :ok
  end

  describe "hit through actual RateLimit implementation" do
    test "returns {:allow, 4} tuple on in-limit checks" do
      key = "key"
      scale = :timer.minutes(10)
      limit = 10

      assert {:allow, 1} = RateLimit.hit(key, scale, limit)
      assert {:allow, 2} = RateLimit.hit(key, scale, limit)
      assert {:allow, 3} = RateLimit.hit(key, scale, limit)
      assert {:allow, 4} = RateLimit.hit(key, scale, limit)
    end

    test "returns expected tuples on mix of in-limit and out-of-limit checks" do
      key = "key"
      scale = :timer.minutes(10)
      limit = 2

      assert {:allow, 1} = RateLimit.hit(key, scale, limit)
      assert {:allow, 2} = RateLimit.hit(key, scale, limit)
      assert {:deny, _retry_after} = RateLimit.hit(key, scale, limit)
      assert {:deny, _retry_after} = RateLimit.hit(key, scale, limit)
    end

    test "with custom increment" do
      key = "cost-key"
      scale = :timer.seconds(1)
      limit = 10

      assert {:allow, 4} = RateLimit.hit(key, scale, limit, 4)
      assert {:allow, 9} = RateLimit.hit(key, scale, limit, 5)
      assert {:deny, _retry_after} = RateLimit.hit(key, scale, limit, 3)
    end
  end

  describe "inc through actual RateLimit implementation" do
    test "increments the count for the given key and scale" do
      key = "key"
      scale = :timer.seconds(10)

      assert RateLimit.get(key, scale) == 0

      assert RateLimit.inc(key, scale) == 1
      assert RateLimit.get(key, scale) == 1

      assert RateLimit.inc(key, scale) == 2
      assert RateLimit.get(key, scale) == 2

      assert RateLimit.inc(key, scale) == 3
      assert RateLimit.get(key, scale) == 3

      assert RateLimit.inc(key, scale) == 4
      assert RateLimit.get(key, scale) == 4
    end
  end

  describe "get/set through actual RateLimit implementation" do
    test "get returns the count set for the given key and scale" do
      key = "key"
      scale = :timer.seconds(10)
      count = 10

      assert RateLimit.get(key, scale) == 0
      assert RateLimit.set(key, scale, count) == count
      assert RateLimit.get(key, scale) == count
    end
  end
end
