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

    test "denied hits do not count towards the window", %{table: table} do
      key = "key"
      scale = 200
      limit = 1

      assert {:allow, 1} = SlidingWindow.hit(table, key, scale, limit)
      :timer.sleep(100)
      assert {:deny, retry_after} = SlidingWindow.hit(table, key, scale, limit)
      assert SlidingWindow.get(table, key, scale) == 1

      # a later denied hit must not extend the block
      :timer.sleep(50)
      assert {:deny, _} = SlidingWindow.hit(table, key, scale, limit)

      :timer.sleep(retry_after)
      assert {:allow, 1} = SlidingWindow.hit(table, key, scale, limit)
    end

    test "concurrent hits never admit more than limit within one window", %{table: table} do
      key = "key"
      scale = 1_000
      limit = 5
      deadline = System.monotonic_time(:millisecond) + 200

      allowed =
        1..8
        |> Enum.map(fn _ -> Task.async(fn -> spin(table, key, scale, limit, deadline, 0) end) end)
        |> Task.await_many()
        |> Enum.sum()

      assert allowed > 0
      assert allowed <= limit
    end

    test "deny path does not crash when concurrent denied hits empty the window", %{
      table: table
    } do
      key = "key"
      deadline = System.monotonic_time(:millisecond) + 500

      # with limit 1 most hits are denied; each denied hit deletes its own entry, so the
      # window is often empty when the next one computes retry_after
      results =
        1..16
        |> Enum.map(fn _ -> Task.async(fn -> spin(table, key, 50, 1, deadline, 0) end) end)
        |> Task.await_many()

      assert Enum.sum(results) > 0
    end
  end

  defp spin(table, key, scale, limit, deadline, allowed) do
    if System.monotonic_time(:millisecond) >= deadline do
      allowed
    else
      case SlidingWindow.hit(table, key, scale, limit) do
        {:allow, _} -> spin(table, key, scale, limit, deadline, allowed + 1)
        {:deny, _} -> spin(table, key, scale, limit, deadline, allowed)
      end
    end
  end
end
