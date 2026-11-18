defmodule Hammer.Atomic.FixWindowPerKeyTest do
  use ExUnit.Case, async: true

  alias Hammer.Atomic
  alias Hammer.Atomic.FixWindowPerKey

  setup do
    table = :ets.new(:hammer_atomic_fix_window_per_key_test, FixWindowPerKey.ets_opts())
    {:ok, table: table}
  end

  describe "hit" do
    test "returns {:allow, 1} tuple on first access", %{table: table} do
      key = "key"
      scale = :timer.seconds(10)
      limit = 10

      assert {:allow, 1} = FixWindowPerKey.hit(table, key, scale, limit, 1)
    end

    test "returns incrementing counts on in-limit checks", %{table: table} do
      key = "key"
      scale = :timer.minutes(10)
      limit = 10

      assert {:allow, 1} = FixWindowPerKey.hit(table, key, scale, limit, 1)
      assert {:allow, 2} = FixWindowPerKey.hit(table, key, scale, limit, 1)
      assert {:allow, 3} = FixWindowPerKey.hit(table, key, scale, limit, 1)
      assert {:allow, 4} = FixWindowPerKey.hit(table, key, scale, limit, 1)
    end

    test "returns expected tuples on mix of in-limit and out-of-limit checks", %{table: table} do
      key = "key"
      scale = :timer.minutes(10)
      limit = 2

      assert {:allow, 1} = FixWindowPerKey.hit(table, key, scale, limit, 1)
      assert {:allow, 2} = FixWindowPerKey.hit(table, key, scale, limit, 1)
      assert {:deny, _retry_after} = FixWindowPerKey.hit(table, key, scale, limit, 1)
      assert {:deny, _retry_after} = FixWindowPerKey.hit(table, key, scale, limit, 1)
    end

    test "returns expected tuples after waiting for the next window", %{table: table} do
      key = "key"
      scale = 100
      limit = 2

      assert {:allow, 1} = FixWindowPerKey.hit(table, key, scale, limit, 1)
      assert {:allow, 2} = FixWindowPerKey.hit(table, key, scale, limit, 1)
      assert {:deny, retry_after} = FixWindowPerKey.hit(table, key, scale, limit, 1)

      :timer.sleep(retry_after + 5)

      assert {:allow, 1} = FixWindowPerKey.hit(table, key, scale, limit, 1)
      assert {:allow, 2} = FixWindowPerKey.hit(table, key, scale, limit, 1)
      assert {:deny, _retry_after} = FixWindowPerKey.hit(table, key, scale, limit, 1)
    end

    test "with custom increment", %{table: table} do
      key = "cost-key"
      scale = :timer.seconds(1)
      limit = 10

      assert {:allow, 4} = FixWindowPerKey.hit(table, key, scale, limit, 4)
      assert {:allow, 9} = FixWindowPerKey.hit(table, key, scale, limit, 5)
      assert {:deny, _retry_after} = FixWindowPerKey.hit(table, key, scale, limit, 3)
    end

    test "mixing default and custom increment", %{table: table} do
      key = "cost-key"
      scale = :timer.seconds(1)
      limit = 10

      assert {:allow, 3} = FixWindowPerKey.hit(table, key, scale, limit, 3)
      assert {:allow, 4} = FixWindowPerKey.hit(table, key, scale, limit, 1)
      assert {:allow, 5} = FixWindowPerKey.hit(table, key, scale, limit, 1)
      assert {:allow, 9} = FixWindowPerKey.hit(table, key, scale, limit, 4)
      assert {:allow, 10} = FixWindowPerKey.hit(table, key, scale, limit, 1)
      assert {:deny, _retry_after} = FixWindowPerKey.hit(table, key, scale, limit, 2)
    end

    test "race condition", %{table: table} do
      key = "key"
      scale = :timer.seconds(10)
      limit = 10

      task1 =
        Task.async(fn ->
          for _ <- 1..2 do
            FixWindowPerKey.hit(table, key, scale, limit, 1)
          end
        end)

      task2 =
        Task.async(fn ->
          for _ <- 1..2 do
            FixWindowPerKey.hit(table, key, scale, limit, 1)
          end
        end)

      Task.await(task1, 5000)
      Task.await(task2, 5000)

      assert FixWindowPerKey.get(table, key, scale) == 4
    end
  end

  describe "per-key window anchoring" do
    test "different keys have independent windows anchored to their first hit", %{table: table} do
      scale = :timer.seconds(10)
      limit = 10

      assert {:allow, 1} = FixWindowPerKey.hit(table, "a", scale, limit, 1)
      :timer.sleep(50)
      assert {:allow, 1} = FixWindowPerKey.hit(table, "b", scale, limit, 1)

      expires_a = FixWindowPerKey.expires_at(table, "a", scale)
      expires_b = FixWindowPerKey.expires_at(table, "b", scale)

      assert expires_b - expires_a >= 40
      assert expires_b - expires_a <= 200
    end

    test "subsequent hits in active window do not extend the window", %{table: table} do
      scale = :timer.seconds(10)
      limit = 10

      assert {:allow, 1} = FixWindowPerKey.hit(table, "key", scale, limit, 1)
      first_expires_at = FixWindowPerKey.expires_at(table, "key", scale)

      :timer.sleep(20)
      assert {:allow, 2} = FixWindowPerKey.hit(table, "key", scale, limit, 1)
      second_expires_at = FixWindowPerKey.expires_at(table, "key", scale)

      assert second_expires_at == first_expires_at
    end

    test "next hit after expiry opens a new window anchored to that hit", %{table: table} do
      scale = 100
      limit = 5

      assert {:allow, 1} = FixWindowPerKey.hit(table, "key", scale, limit, 1)
      first_expires_at = FixWindowPerKey.expires_at(table, "key", scale)

      :timer.sleep(scale + 20)

      assert {:allow, 1} = FixWindowPerKey.hit(table, "key", scale, limit, 1)
      new_expires_at = FixWindowPerKey.expires_at(table, "key", scale)

      assert new_expires_at > first_expires_at
      assert new_expires_at - first_expires_at >= scale
    end
  end

  describe "concurrent expiry reset" do
    test "every concurrent hit on an expired key is counted", %{table: table} do
      key = "race"
      scale = :timer.seconds(5)
      limit = 100_000

      atomic = :atomics.new(2, signed: false)
      :ets.insert(table, {key, atomic})

      n = 200

      tasks =
        Enum.map(1..n, fn _ ->
          Task.async(fn ->
            receive do
              :go -> FixWindowPerKey.hit(table, key, scale, limit, 1)
            end
          end)
        end)

      Enum.each(tasks, &send(&1.pid, :go))
      results = Task.await_many(tasks, 5_000)

      allows = Enum.count(results, &match?({:allow, _}, &1))
      assert allows == n
      assert FixWindowPerKey.get(table, key, scale) == allows
    end
  end

  describe "unfinished window reset" do
    # Up to 7.5.1, resetting an expired window took a lock by writing a
    # sentinel into the expiry slot. A process killed while holding it left
    # the sentinel behind, and every later call on that key spun on it forever.
    # The lock is gone, but a table that lived through a hot code upgrade can
    # still carry one: it must read as an expired window, not as a live one
    # that expires at the end of time.
    setup %{table: table} do
      atomic = :atomics.new(2, signed: false)
      :atomics.put(atomic, 1, 7)
      :atomics.put(atomic, 2, 0xFFFFFFFFFFFFFFFF)
      :ets.insert(table, {"stuck", atomic})
      :ok
    end

    test "hit opens a fresh window", %{table: table} do
      task = Task.async(fn -> FixWindowPerKey.hit(table, "stuck", 1000, 10, 1) end)

      assert {:ok, {:allow, 1}} = Task.yield(task, 500) || Task.shutdown(task, :brutal_kill)
      assert FixWindowPerKey.expires_at(table, "stuck", 1000) <= Atomic.now() + 1000
    end

    test "inc opens a fresh window", %{table: table} do
      task = Task.async(fn -> FixWindowPerKey.inc(table, "stuck", 1000, 1) end)

      assert {:ok, 1} = Task.yield(task, 500) || Task.shutdown(task, :brutal_kill)
      assert FixWindowPerKey.expires_at(table, "stuck", 1000) <= Atomic.now() + 1000
    end

    test "get and expires_at report no active window", %{table: table} do
      assert FixWindowPerKey.get(table, "stuck", 1000) == 0
      assert FixWindowPerKey.expires_at(table, "stuck", 1000) == 0
    end
  end

  describe "set on a live window" do
    test "keeps the same counter, so a hit already in flight is not orphaned",
         %{table: table} do
      assert {:allow, 1} = FixWindowPerKey.hit(table, "key", 60_000, 10, 1)
      [{_, before}] = :ets.lookup(table, "key")

      assert FixWindowPerKey.set(table, "key", 60_000, 5) == 5

      # A hit that looked the counter up before the set lands on the one the
      # set wrote to, and is counted.
      assert [{_, ^before}] = :ets.lookup(table, "key")
      assert :atomics.add_get(before, 1, 1) == 6
      assert FixWindowPerKey.get(table, "key", 60_000) == 6
    end
  end

  describe "inc" do
    test "increments the count for the given key and scale", %{table: table} do
      key = "key"
      scale = :timer.seconds(10)

      assert FixWindowPerKey.get(table, key, scale) == 0

      assert FixWindowPerKey.inc(table, key, scale, 1) == 1
      assert FixWindowPerKey.get(table, key, scale) == 1

      assert FixWindowPerKey.inc(table, key, scale, 1) == 2
      assert FixWindowPerKey.get(table, key, scale) == 2

      assert FixWindowPerKey.inc(table, key, scale, 1) == 3
      assert FixWindowPerKey.get(table, key, scale) == 3

      assert FixWindowPerKey.inc(table, key, scale, 1) == 4
      assert FixWindowPerKey.get(table, key, scale) == 4
    end

    test "resets the counter after expiry", %{table: table} do
      key = "key"
      scale = 100

      assert FixWindowPerKey.inc(table, key, scale, 1) == 1
      assert FixWindowPerKey.inc(table, key, scale, 1) == 2

      :timer.sleep(scale + 20)

      assert FixWindowPerKey.inc(table, key, scale, 1) == 1
    end
  end

  describe "expires_at" do
    test "returns 0 for unknown key", %{table: table} do
      assert FixWindowPerKey.expires_at(table, "unknown", :timer.seconds(10)) == 0
    end

    test "returns the expiration timestamp after a hit", %{table: table} do
      key = "key"
      scale = :timer.seconds(10)

      assert {:allow, 1} = FixWindowPerKey.hit(table, key, scale, 10, 1)

      expires_at = FixWindowPerKey.expires_at(table, key, scale)
      now = System.system_time(:millisecond)

      assert expires_at > now
      assert expires_at <= now + scale
    end

    test "returns 0 after window expires", %{table: table} do
      key = "key"
      scale = 100

      assert {:allow, 1} = FixWindowPerKey.hit(table, key, scale, 10, 1)
      assert FixWindowPerKey.expires_at(table, key, scale) > 0

      :timer.sleep(scale + 20)

      assert FixWindowPerKey.expires_at(table, key, scale) == 0
    end
  end

  describe "get/set" do
    test "get returns the count set for the given key and scale", %{table: table} do
      key = "key"
      scale = :timer.seconds(10)
      count = 10

      assert FixWindowPerKey.get(table, key, scale) == 0
      assert FixWindowPerKey.set(table, key, scale, count) == count
      assert FixWindowPerKey.get(table, key, scale) == count
    end

    test "get returns 0 after the window expires", %{table: table} do
      key = "key"
      scale = 100

      assert {:allow, 1} = FixWindowPerKey.hit(table, key, scale, 10, 1)
      assert FixWindowPerKey.get(table, key, scale) == 1

      :timer.sleep(scale + 20)

      assert FixWindowPerKey.get(table, key, scale) == 0
    end
  end
end
