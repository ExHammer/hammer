defmodule Hammer.Atomic.FixWindowTest do
  use ExUnit.Case, async: true

  alias Hammer.Atomic.FixWindow

  setup do
    table = :ets.new(:hammer_atomic_fix_window_test, FixWindow.ets_opts())
    {:ok, table: table}
  end

  describe "hit" do
    test "returns {:allow, 1} tuple on first access", %{table: table} do
      key = "key"
      scale = :timer.seconds(10)
      limit = 10

      assert {:allow, 1} = FixWindow.hit(table, key, scale, limit, 1)
    end

    test "returns {:allow, 4} tuple on in-limit checks", %{table: table} do
      key = "key"
      scale = :timer.minutes(10)
      limit = 10

      assert {:allow, 1} = FixWindow.hit(table, key, scale, limit, 1)
      assert {:allow, 2} = FixWindow.hit(table, key, scale, limit, 1)
      assert {:allow, 3} = FixWindow.hit(table, key, scale, limit, 1)
      assert {:allow, 4} = FixWindow.hit(table, key, scale, limit, 1)
    end

    test "returns expected tuples on mix of in-limit and out-of-limit checks", %{table: table} do
      key = "key"
      scale = :timer.minutes(10)
      limit = 2

      assert {:allow, 1} = FixWindow.hit(table, key, scale, limit, 1)
      assert {:allow, 2} = FixWindow.hit(table, key, scale, limit, 1)
      assert {:deny, _retry_after} = FixWindow.hit(table, key, scale, limit, 1)
      assert {:deny, _retry_after} = FixWindow.hit(table, key, scale, limit, 1)
    end

    test "returns expected tuples after waiting for the next window", %{table: table} do
      key = "key"
      scale = 100
      limit = 2

      assert {:allow, 1} = FixWindow.hit(table, key, scale, limit, 1)
      assert {:allow, 2} = FixWindow.hit(table, key, scale, limit, 1)
      assert {:deny, retry_after} = FixWindow.hit(table, key, scale, limit, 1)

      :timer.sleep(retry_after)

      assert {:allow, 1} = FixWindow.hit(table, key, scale, limit, 1)
      assert {:allow, 2} = FixWindow.hit(table, key, scale, limit, 1)
      assert {:deny, _retry_after} = FixWindow.hit(table, key, scale, limit, 1)
    end

    test "with custom increment", %{table: table} do
      key = "cost-key"
      scale = :timer.seconds(1)
      limit = 10

      assert {:allow, 4} = FixWindow.hit(table, key, scale, limit, 4)
      assert {:allow, 9} = FixWindow.hit(table, key, scale, limit, 5)
      assert {:deny, _retry_after} = FixWindow.hit(table, key, scale, limit, 3)
    end

    test "mixing default and custom increment", %{table: table} do
      key = "cost-key"
      scale = :timer.seconds(1)
      limit = 10

      assert {:allow, 3} = FixWindow.hit(table, key, scale, limit, 3)
      assert {:allow, 4} = FixWindow.hit(table, key, scale, limit, 1)
      assert {:allow, 5} = FixWindow.hit(table, key, scale, limit, 1)
      assert {:allow, 9} = FixWindow.hit(table, key, scale, limit, 4)
      assert {:allow, 10} = FixWindow.hit(table, key, scale, limit, 1)
      assert {:deny, _retry_after} = FixWindow.hit(table, key, scale, limit, 2)
    end

    test "race condition", %{table: table} do
      key = "key"
      scale = :timer.seconds(1)
      limit = 10

      # Start two processes

      spawn_link(fn ->
        for _ <- 1..2 do
          FixWindow.hit(table, key, scale, limit, 1)
        end
      end)

      spawn_link(fn ->
        for _ <- 1..2 do
          FixWindow.hit(table, key, scale, limit, 1)
        end
      end)

      # Wait for both processes to finish
      Process.sleep(100)

      # Check the final count
      assert FixWindow.get(table, key, scale) == 4
    end
  end

  describe "inc" do
    test "increments the count for the given key and scale", %{table: table} do
      key = "key"
      scale = :timer.seconds(10)

      assert FixWindow.get(table, key, scale) == 0

      assert FixWindow.inc(table, key, scale, 1) == 1
      assert FixWindow.get(table, key, scale) == 1

      assert FixWindow.inc(table, key, scale, 1) == 2
      assert FixWindow.get(table, key, scale) == 2

      assert FixWindow.inc(table, key, scale, 1) == 3
      assert FixWindow.get(table, key, scale) == 3

      assert FixWindow.inc(table, key, scale, 1) == 4
      assert FixWindow.get(table, key, scale) == 4
    end
  end

  describe "get/set" do
    test "get returns the count set for the given key and scale", %{table: table} do
      key = "key"
      scale = :timer.seconds(10)
      count = 10

      assert FixWindow.get(table, key, scale) == 0
      assert FixWindow.set(table, key, scale, count) == count
      assert FixWindow.get(table, key, scale) == count
    end
  end
end
