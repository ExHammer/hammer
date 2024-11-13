defmodule Hammer.ETSTest do
  use ExUnit.Case, async: true

  defmodule RateLimit do
    use Hammer, backend: :ets
  end

  setup do
    start_supervised!(RateLimit)
    :ok
  end

  describe "check_rate" do
    test "returns {:allow, 1} tuple on first access" do
      key = "key"
      scale = :timer.seconds(10)
      limit = 10

      assert {:allow, 1} = RateLimit.check_rate(key, scale, limit)
    end

    test "returns {:allow, 4} tuple on in-limit checks" do
      key = "key"
      scale = :timer.minutes(10)
      limit = 10

      assert {:allow, 1} = RateLimit.check_rate(key, scale, limit)
      assert {:allow, 2} = RateLimit.check_rate(key, scale, limit)
      assert {:allow, 3} = RateLimit.check_rate(key, scale, limit)
      assert {:allow, 4} = RateLimit.check_rate(key, scale, limit)
    end

    test "returns expected tuples on mix of in-limit and out-of-limit checks" do
      key = "key"
      scale = :timer.minutes(10)
      limit = 2

      assert {:allow, 1} = RateLimit.check_rate(key, scale, limit)
      assert {:allow, 2} = RateLimit.check_rate(key, scale, limit)
      assert {:deny, 2} = RateLimit.check_rate(key, scale, limit)
      assert {:deny, 2} = RateLimit.check_rate(key, scale, limit)
    end

    test "returns expected tuples after waiting for the next window" do
      key = "key"
      scale = 100
      limit = 2

      assert {:allow, 1} = RateLimit.check_rate(key, scale, limit)
      assert {:allow, 2} = RateLimit.check_rate(key, scale, limit)
      assert {:deny, 2} = RateLimit.check_rate(key, scale, limit)

      assert :ok = RateLimit.wait(scale)

      assert {:allow, 1} = RateLimit.check_rate(key, scale, limit)
      assert {:allow, 2} = RateLimit.check_rate(key, scale, limit)
      assert {:deny, 2} = RateLimit.check_rate(key, scale, limit)
    end

    test "with custom increment" do
      key = "cost-key"
      scale = :timer.seconds(1)
      limit = 10

      assert {:allow, 4} = RateLimit.check_rate(key, scale, limit, 4)
      assert {:allow, 9} = RateLimit.check_rate(key, scale, limit, 5)
      assert {:deny, 10} = RateLimit.check_rate(key, scale, limit, 3)
    end

    test "mixing default and custom increment" do
      key = "cost-key"
      scale = :timer.seconds(1)
      limit = 10

      assert {:allow, 3} = RateLimit.check_rate(key, scale, limit, 3)
      assert {:allow, 4} = RateLimit.check_rate(key, scale, limit)
      assert {:allow, 5} = RateLimit.check_rate(key, scale, limit)
      assert {:allow, 9} = RateLimit.check_rate(key, scale, limit, 4)
      assert {:allow, 10} = RateLimit.check_rate(key, scale, limit)
      assert {:deny, 10} = RateLimit.check_rate(key, scale, limit, 2)
    end
  end

  describe "hit" do
    test "increments the count for the given key and scale" do
      key = "key"
      scale = :timer.seconds(10)

      assert RateLimit.get(key, scale) == 0

      assert RateLimit.hit(key, scale) == 1
      assert RateLimit.get(key, scale) == 1

      assert RateLimit.hit(key, scale) == 2
      assert RateLimit.get(key, scale) == 2

      assert RateLimit.hit(key, scale) == 3
      assert RateLimit.get(key, scale) == 3

      assert RateLimit.hit(key, scale) == 4
      assert RateLimit.get(key, scale) == 4
    end
  end

  describe "get/set" do
    test "get returns the count set for the given key and scale" do
      key = "key"
      scale = :timer.seconds(10)
      count = 10

      assert RateLimit.get(key, scale) == 0
      assert RateLimit.set(key, scale, count) == count
      assert RateLimit.get(key, scale) == count
    end
  end

  describe "reset" do
    test "resets the count for the given key and scale" do
      key = "key"
      scale = :timer.seconds(10)
      count = 10

      assert RateLimit.get(key, scale) == 0

      assert RateLimit.set(key, scale, count) == count
      assert RateLimit.get(key, scale) == count

      assert RateLimit.reset(key, scale) == 0
      assert RateLimit.get(key, scale) == 0
    end
  end
end
