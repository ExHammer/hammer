defmodule Hammer.ETS.SlidingWindowTest do
  use ExUnit.Case, async: true

  alias Hammer.ETS.SlidingWindow

  setup do
    table = :ets.new(:hammer_sliding_window_test, SlidingWindow.ets_opts())
    {:ok, table: table}
  end

  describe "hit/get" do
    test "returns {:allow, 1} tuple on first access", %{table: table} do
      key = "key"
      scale = :timer.seconds(10)
      limit = 10

      assert {:allow, 1} = SlidingWindow.hit(table, key, scale, limit)
    end

    test "returns {:allow, 4} tuple on in-limit checks", %{table: table} do
      key = "key"
      scale = :timer.minutes(10)
      limit = 10

      assert {:allow, 1} = SlidingWindow.hit(table, key, scale, limit)
      assert {:allow, 2} = SlidingWindow.hit(table, key, scale, limit)
      assert {:allow, 3} = SlidingWindow.hit(table, key, scale, limit)
      assert {:allow, 4} = SlidingWindow.hit(table, key, scale, limit)
    end

    test "returns expected tuples on mix of in-limit and out-of-limit checks", %{table: table} do
      key = "key"
      scale = :timer.minutes(10)
      limit = 2

      assert {:allow, 1} = SlidingWindow.hit(table, key, scale, limit)
      assert {:allow, 2} = SlidingWindow.hit(table, key, scale, limit)
      assert {:deny, _retry_after} = SlidingWindow.hit(table, key, scale, limit)
      assert {:deny, _retry_after} = SlidingWindow.hit(table, key, scale, limit)
    end

    test "returns expected tuples after waiting for the next window", %{table: table} do
      key = "key"
      scale = 100
      limit = 2

      assert {:allow, 1} = SlidingWindow.hit(table, key, scale, limit)
      assert {:allow, 2} = SlidingWindow.hit(table, key, scale, limit)
      assert {:deny, retry_after} = SlidingWindow.hit(table, key, scale, limit)

      :timer.sleep(retry_after)

      assert {:allow, 1} = SlidingWindow.hit(table, key, scale, limit)
      assert {:allow, 2} = SlidingWindow.hit(table, key, scale, limit)
      assert {:deny, _retry_after} = SlidingWindow.hit(table, key, scale, limit)
    end
  end
end
