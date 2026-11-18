defmodule Hammer.Atomic.TokenBucketTest do
  use ExUnit.Case, async: true
  import Bitwise
  alias Hammer.Atomic.TokenBucket

  defmodule RateLimitTokenBucket do
    use Hammer, backend: :atomic, algorithm: :token_bucket
  end

  setup do
    table = :ets.new(:hammer_atomic_token_bucket_test, TokenBucket.ets_opts())
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

      assert {:deny, retry_after} = TokenBucket.hit(table, key, refill_rate, capacity, 1)
      assert retry_after in 1..1000

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

    test "a caller hitting in a tight loop is held to the refill rate", %{table: table} do
      # Each credited token must move the refill clock by exactly its own
      # worth of time. Rounding that step down hands the same elapsed time out
      # again on the next hit: at 1500 tokens/sec a token is worth 0.67ms, a
      # step of trunc(0.67) == 0 never moves the clock, and the limiter is off.
      for refill_rate <- [600, 1500, 2500] do
        key = "tight:#{refill_rate}"
        capacity = 10
        # Measured on the wall clock the bucket itself reads, with 2ms of
        # slack: both ends are truncated to a whole millisecond.
        started = System.system_time(:millisecond)
        deadline = System.monotonic_time(:millisecond) + 200

        allowed = count_allowed(table, key, refill_rate, capacity, deadline, 0)

        elapsed = System.system_time(:millisecond) - started + 2
        bound = capacity + ceil(refill_rate * elapsed / 1000)

        assert allowed <= bound,
               "allowed #{allowed} hits in #{elapsed}ms at rate=#{refill_rate}, bound is #{bound}"
      end
    end

    # The tests below seed a bucket directly. `frozen/0` is a clock far enough
    # ahead that the bucket sees no time pass, however long the test is paused,
    # so the level they assert on is exact.
    test "credits fractions of a token instead of discarding them", %{table: table} do
      key = "key"
      refill_rate = 55
      capacity = 10

      # 60 hits spaced 18ms apart, simulated by rewinding the bucket's clock.
      # 18ms is worth 0.99 of a token: a bucket that only kept whole tokens
      # would credit nothing and be drained by the eleventh hit.
      seed(table, key, capacity, System.system_time(:millisecond))

      for step <- 1..60 do
        rewind(table, key, 18)

        assert {:allow, _} = TokenBucket.hit(table, key, refill_rate, capacity, 1),
               "denied at step #{step} -- the bucket drained while paced at its own refill rate"
      end

      # One token for the first hit, then a hundredth of a token per step.
      assert TokenBucket.get(table, key) == capacity - 2
    end

    test "an idle bucket does not bank more than its capacity", %{table: table} do
      key = "key"
      seed(table, key, 10, System.system_time(:millisecond) - 5_000)

      # 5s at 55/sec is 275 tokens into a bucket that holds 10.
      assert {:allow, 9} = TokenBucket.hit(table, key, 55, 10, 1)
    end

    test "refills at sub-second granularity when refill_rate > capacity", %{table: table} do
      key = "key"
      seed(table, key, 0, System.system_time(:millisecond) - 30)

      # 30ms at 100 tokens/sec is 3 tokens: no waiting for a second boundary.
      assert {:allow, _} = TokenBucket.hit(table, key, 100, 10, 3)
    end

    test "the deny wait is the real time until the bucket holds enough tokens",
         %{table: table} do
      key = "key"
      refill_rate = 55
      capacity = 10

      clock = frozen()
      seed(table, key, 0, clock)

      # Short exactly one token: ceil(1000 / 55) == 19ms, once the bucket's
      # clock has been caught up with.
      assert 19 in refill_wait(table, key, refill_rate, capacity, 1, clock)

      # The wait scales with how many tokens the cost is short of.
      assert 91 in refill_wait(table, key, refill_rate, capacity, 5, clock)
    end

    test "the deny wait covers a stored clock ahead of the caller's", %{table: table} do
      key = "key"

      # A wall clock that stepped back leaves the stored clock ahead. Nothing
      # refills until the caller's time catches up with it, so that stretch is
      # part of the wait.
      seed(table, key, 0, System.system_time(:millisecond) + 40)

      assert {:deny, wait} = TokenBucket.hit(table, key, 1000, 10, 1)
      assert wait in 30..41

      # Retried against the same bucket, the advertised wait is enough.
      Process.sleep(wait)
      assert {:allow, _} = TokenBucket.hit(table, key, 1000, 10, 1)
    end

    test "the advertised wait is sufficient across rates, costs and deficits", %{table: table} do
      for refill_rate <- [1, 2, 3, 7, 55, 100, 999, 1_000_000],
          capacity <- [1, 10, 1000],
          cost <- [1, 3, capacity],
          cost <= capacity,
          starting_level <- [0, div(cost, 2)],
          starting_level < cost do
        key = "sufficient:#{refill_rate}:#{capacity}:#{cost}:#{starting_level}"
        clock = frozen()
        seed(table, key, starting_level, clock)

        assert {:deny, wait} = TokenBucket.hit(table, key, refill_rate, capacity, cost)
        assert wait >= 1

        # The same bucket as a caller finds it having slept the advertised wait.
        seed(table, key, starting_level, clock - wait)

        assert {:allow, _} = TokenBucket.hit(table, key, refill_rate, capacity, cost),
               "wait of #{wait}ms was too short for rate=#{refill_rate} " <>
                 "cap=#{capacity} cost=#{cost} level=#{starting_level}"
      end
    end

    test "a bucket idle for longer than its packed clock can express is refilled",
         %{table: table} do
      # The packed clock is the low 22 bits of the millisecond time, so on its
      # own it cannot tell a long gap from a short one.
      for idle <- [:timer.minutes(40), :timer.hours(3), :timer.hours(24 * 30)] do
        key = "idle:#{idle}"
        seed(table, key, 0, System.system_time(:millisecond) - idle)

        # One token per second into a bucket too large to fill.
        assert {:allow, level} = TokenBucket.hit(table, key, 1, 100_000_000, 1)
        assert level in (div(idle, 1000) - 1)..(div(idle, 1000) + 5)
      end
    end

    test "a long idle refill is not credited again by an overlapping hit", %{table: table} do
      # The packed state and slot 2 are two writes. Between them the packed
      # state already holds the idle refill and the current clock, while slot 2
      # still holds the time before the idle period.
      for idle <- [:timer.minutes(40), :timer.hours(3), :timer.hours(24 * 30)] do
        key = "overlap:#{idle}"
        now = System.system_time(:millisecond)
        seed(table, key, 2399, now, now - idle)

        # One token per second into a bucket too large to fill.
        assert {:allow, 2398} = TokenBucket.hit(table, key, 1, 100_000_000, 1)
      end
    end

    test "concurrent hits after a long idle share one refill", %{table: table} do
      key = "key"
      idle = :timer.minutes(40)
      seed(table, key, 0, System.system_time(:millisecond) - idle)

      # One token per second into a bucket too large to fill.
      allowed =
        1..50
        |> Enum.map(fn _ ->
          Task.async(fn -> TokenBucket.hit(table, key, 1, 100_000_000, 1) end)
        end)
        |> Task.await_many()
        |> Enum.count(&match?({:allow, _}, &1))

      assert allowed == 50
      assert (TokenBucket.get(table, key) + allowed) in div(idle, 1000)..(div(idle, 1000) + 5)
    end

    test "a stored clock ahead of the caller's credits nothing", %{table: table} do
      key = "key"

      # A concurrent hit that read the time later can store a clock slightly
      # ahead of ours. That must read as no time elapsed, not as a refill.
      seed(table, key, 0, System.system_time(:millisecond) + 500)

      assert {:deny, _} = TokenBucket.hit(table, key, 1000, 1000, 1)
    end

    test "a bucket written by 7.5.1 or earlier starts over full", %{table: table} do
      key = "key"

      # The old layout: whole seconds in the high 32 bits, tokens in the low
      # 32, and whole seconds in slot 2. Reachable only by a hot code upgrade.
      now = System.system_time(:second)
      atomic = :atomics.new(2, signed: false)
      :atomics.put(atomic, 1, now <<< 32 ||| 3)
      :atomics.put(atomic, 2, now)
      :ets.insert(table, {key, atomic})

      assert {:allow, 9} = TokenBucket.hit(table, key, 1, 10, 1)
      assert {:allow, 8} = TokenBucket.hit(table, key, 1, 10, 1)
    end

    test "a refill rate of 0 still denies with a flat second", %{table: table} do
      key = "key"
      seed(table, key, 0, System.system_time(:millisecond))

      assert {:deny, 1000} = TokenBucket.hit(table, key, 0, 10, 1)
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

    test "race condition", %{table: table} do
      key = "key"
      # No refill to avoid timing issues
      refill_rate = 0
      capacity = 4

      # Use tasks to better control process lifecycle
      task1 =
        Task.async(fn ->
          for _ <- 1..2 do
            TokenBucket.hit(table, key, refill_rate, capacity, 1)
          end
        end)

      task2 =
        Task.async(fn ->
          for _ <- 1..2 do
            TokenBucket.hit(table, key, refill_rate, capacity, 1)
          end
        end)

      # Wait for both tasks to complete
      Task.await(task1, 5000)
      Task.await(task2, 5000)

      # Check the final count - should be 0 after consuming 4 tokens from capacity 4
      assert TokenBucket.get(table, key) == 0
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

  # Publish a bucket holding `level` whole tokens whose clock reads `timestamp`
  # (ms), packed the way the algorithm packs it: the low 22 bits of the time
  # high, the level in thousandths of a token low. Slot 2 holds `stamp`, the
  # full time of that clock unless a test wants it lagging.
  defp seed(table, key, level, timestamp, stamp \\ nil) do
    atomic = :atomics.new(2, signed: false)
    :atomics.put(atomic, 1, (timestamp &&& 0x3FFFFF) <<< 42 ||| level * 1000)
    :atomics.put(atomic, 2, stamp || timestamp)
    :ets.insert(table, {key, atomic})
  end

  # Move the bucket's clock back, as if the caller had slept `ms`.
  defp rewind(table, key, ms) do
    [{^key, atomic}] = :ets.lookup(table, key)
    packed = :atomics.get(atomic, 1)
    level = packed &&& 0x3FFFFFFFFFF
    :atomics.put(atomic, 1, ((packed >>> 42) - ms &&& 0x3FFFFF) <<< 42 ||| level)
    :atomics.put(atomic, 2, :atomics.get(atomic, 2) - ms)
  end

  # The deny wait with the time left until `clock`, a stored clock ahead of
  # ours, taken out: what remains is the time the refill itself needs. A
  # range, because the hit read the time somewhere between `before` and now.
  defp refill_wait(table, key, refill_rate, capacity, cost, clock) do
    before = System.system_time(:millisecond)
    assert {:deny, wait} = TokenBucket.hit(table, key, refill_rate, capacity, cost)
    gap = clock - System.system_time(:millisecond)
    (wait - (clock - before))..(wait - gap)
  end

  defp frozen, do: System.system_time(:millisecond) + :timer.minutes(1)

  defp count_allowed(table, key, refill_rate, capacity, deadline, allowed) do
    allowed =
      case TokenBucket.hit(table, key, refill_rate, capacity, 1) do
        {:allow, _} -> allowed + 1
        {:deny, _} -> allowed
      end

    if System.monotonic_time(:millisecond) < deadline do
      count_allowed(table, key, refill_rate, capacity, deadline, allowed)
    else
      allowed
    end
  end
end
