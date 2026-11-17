defmodule Hammer.AtomicTest do
  use ExUnit.Case, async: true

  defmodule RateAtomicLimit do
    use Hammer, backend: :atomic
  end

  setup do
    start_supervised!(RateAtomicLimit)
    :ok
  end

  describe "hit through actual RateAtomicLimit implementation" do
    test "returns {:allow, 4} tuple on in-limit checks" do
      key = "key"
      scale = :timer.minutes(10)
      limit = 10

      assert {:allow, 1} = RateAtomicLimit.hit(key, scale, limit)
      assert {:allow, 2} = RateAtomicLimit.hit(key, scale, limit)
      assert {:allow, 3} = RateAtomicLimit.hit(key, scale, limit)
      assert {:allow, 4} = RateAtomicLimit.hit(key, scale, limit)
    end

    test "returns expected tuples on mix of in-limit and out-of-limit checks" do
      key = "key"
      scale = :timer.minutes(10)
      limit = 2

      assert {:allow, 1} = RateAtomicLimit.hit(key, scale, limit)
      assert {:allow, 2} = RateAtomicLimit.hit(key, scale, limit)
      assert {:deny, _retry_after} = RateAtomicLimit.hit(key, scale, limit)
      assert {:deny, _retry_after} = RateAtomicLimit.hit(key, scale, limit)
    end

    test "with custom increment" do
      key = "cost-key"
      scale = :timer.seconds(1)
      limit = 10

      assert {:allow, 4} = RateAtomicLimit.hit(key, scale, limit, 4)
      assert {:allow, 9} = RateAtomicLimit.hit(key, scale, limit, 5)
      assert {:deny, _retry_after} = RateAtomicLimit.hit(key, scale, limit, 3)
    end
  end

  describe "inc through actual RateAtomicLimit implementation" do
    test "increments the count for the given key and scale" do
      key = "key"
      scale = :timer.seconds(10)

      assert RateAtomicLimit.get(key, scale) == 0

      assert RateAtomicLimit.inc(key, scale) == 1
      assert RateAtomicLimit.get(key, scale) == 1

      assert RateAtomicLimit.inc(key, scale) == 2
      assert RateAtomicLimit.get(key, scale) == 2

      assert RateAtomicLimit.inc(key, scale) == 3
      assert RateAtomicLimit.get(key, scale) == 3

      assert RateAtomicLimit.inc(key, scale) == 4
      assert RateAtomicLimit.get(key, scale) == 4
    end
  end

  describe "get/set through actual RateAtomicLimit implementation" do
    test "get returns the count set for the given key and scale" do
      key = "key"
      scale = :timer.seconds(10)
      count = 10

      assert RateAtomicLimit.get(key, scale) == 0
      assert RateAtomicLimit.set(key, scale, count) == count
      assert RateAtomicLimit.get(key, scale) == count
    end
  end

  describe "algorithm option" do
    test ":sliding_window is rejected with a pointer to the backends that have it" do
      assert_raise ArgumentError, ~r/:sliding_window is not available.*backend: :ets/s, fn ->
        defmodule SlidingWindowLimit do
          use Hammer, backend: :atomic, algorithm: :sliding_window
        end
      end
    end

    test "an unknown algorithm lists the ones the Atomic backend supports" do
      assert_raise ArgumentError, ~r/valid algorithm.*:token_bucket/s, fn ->
        defmodule UnknownAlgorithmLimit do
          use Hammer, backend: :atomic, algorithm: :nope
        end
      end
    end
  end
end
