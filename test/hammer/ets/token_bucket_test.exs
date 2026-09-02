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

    # The three tests below pin the refill clock's bookkeeping directly rather
    # than measuring throughput. They seed `last_update` at a known offset from
    # `now` and assert the value written back, so they are deterministic: the
    # stored timestamp is derived from `last_update` plus the time actually
    # credited, never from when the test happened to run.
    test "carries the sub-token remainder instead of discarding it", %{table: table} do
      key = "key"
      # One token every ~18.18ms.
      refill_rate = 55
      capacity = 10

      now = System.system_time(:millisecond)
      seeded_at = now - 30
      :ets.insert(table, {key, 5, seeded_at})

      # 30ms accrues trunc(30 * 55 / 1000) == 1 token, which is worth 18ms.
      # The remaining ~12ms must stay on the clock for the next hit.
      assert {:allow, 5} = TokenBucket.hit(table, key, refill_rate, capacity, 1)

      assert [{^key, 5, stored_at}] = :ets.lookup(table, key)
      assert stored_at == seeded_at + 18
    end

    test "does not reset the clock when a full bucket accrued no new tokens", %{table: table} do
      key = "key"
      refill_rate = 55
      capacity = 10

      now = System.system_time(:millisecond)
      seeded_at = now - 10
      :ets.insert(table, {key, capacity, seeded_at})

      # 10ms accrues trunc(10 * 55 / 1000) == 0 tokens. The bucket reads as full
      # only because it already was, so nothing overflowed and nothing may be
      # discarded -- this hit drops it to 9, and the 10ms is still owed to that
      # level. Stamping `now` here would silently throw the accrual away.
      assert {:allow, 9} = TokenBucket.hit(table, key, refill_rate, capacity, 1)

      assert [{^key, 9, stored_at}] = :ets.lookup(table, key)
      assert stored_at == seeded_at
    end

    test "resets the clock when an idle bucket overflows", %{table: table} do
      key = "key"
      refill_rate = 55
      capacity = 10

      now = System.system_time(:millisecond)
      :ets.insert(table, {key, capacity, now - 5_000})

      # 5s would accrue 275 tokens into a bucket that holds 10. The surplus is
      # legitimately discarded, so the clock must snap forward -- otherwise an
      # idle bucket banks unbounded credit and the next burst is unbounded too.
      assert {:allow, 9} = TokenBucket.hit(table, key, refill_rate, capacity, 1)

      assert [{^key, 9, stored_at}] = :ets.lookup(table, key)
      assert stored_at >= now
      assert stored_at <= now + 1_000
    end

    test "a caller paced at the nominal refill rate does not starve", %{table: table} do
      key = "key"
      refill_rate = 55
      capacity = 10

      # Walk 60 hits spaced one whole millisecond faster than a token period
      # (18ms vs ~18.18ms) by advancing the seeded clock by hand. Each hit
      # credits exactly one token, so a lossless bucket holds its level. If the
      # ~0.18ms remainder is dropped per hit the level decays and the caller is
      # eventually denied at a rate it was entitled to sustain.
      start = System.system_time(:millisecond)
      :ets.insert(table, {key, capacity, start})

      for step <- 1..60 do
        [{^key, level, last_update}] = :ets.lookup(table, key)
        :ets.insert(table, {key, level, last_update - 18})

        assert {:allow, _} = TokenBucket.hit(table, key, refill_rate, capacity, 1),
               "denied at step #{step} -- the bucket drained while paced under its own refill rate"
      end

      # The level settles a little below capacity rather than at it: each time a
      # refill tops the bucket out, the overflow branch correctly discards the
      # surplus. What matters is that it reaches a steady state instead of
      # decaying -- before this fix the same loop is denied by step 11.
      assert [{^key, final_level, _}] = :ets.lookup(table, key)
      assert final_level >= div(capacity, 2)
    end

    test "the stored clock stays between last_update and now", %{table: table} do
      # Carrying the remainder means the stored timestamp is deliberately
      # allowed to lag `now`. Two bounds keep that safe, and both matter to
      # clean/1, which reaps rows by comparing this timestamp against
      # `now - key_older_than`:
      #
      #   * it can never run AHEAD of now, or a row outlives its real idleness
      #   * it can never lag by more than one token period, or an actively
      #     used row could look idle and be reaped out from under its caller
      #
      # The upper bound holds because the credited time is at most the elapsed
      # time: trunc(new_tokens * 1000 / refill_rate) <= elapsed, always.
      for {refill_rate, capacity} <- [{1, 5}, {55, 10}, {100, 1000}, {1_000_000, 10}],
          offset <- [0, 1, 9, 18, 500, 5_000] do
        key = "bounds:#{refill_rate}:#{capacity}:#{offset}"
        before = System.system_time(:millisecond)
        seeded_at = before - offset
        :ets.insert(table, {key, div(capacity, 2) + 1, seeded_at})

        assert {:allow, _} = TokenBucket.hit(table, key, refill_rate, capacity, 1)
        now_after = System.system_time(:millisecond)

        assert [{^key, _, stored_at}] = :ets.lookup(table, key)

        assert stored_at <= now_after,
               "clock ran ahead of now for rate=#{refill_rate} cap=#{capacity} offset=#{offset}"

        assert stored_at >= seeded_at,
               "clock moved backwards for rate=#{refill_rate} cap=#{capacity} offset=#{offset}"

        token_period = div(1000, refill_rate) + 1

        assert now_after - stored_at <= offset + token_period,
               "lagged more than one token period for rate=#{refill_rate} cap=#{capacity} offset=#{offset}"
      end
    end

    test "refills at sub-second granularity when refill_rate > capacity", %{table: table} do
      key = "key"
      # Small burst allowance with a higher sustained rate,
      # e.g. a third-party API allowing burst 10 / 100 sustained per second
      refill_rate = 100
      capacity = 10

      # Drain the bucket completely
      assert {:allow, 0} = TokenBucket.hit(table, key, refill_rate, capacity, capacity)

      # At 100 tokens/sec, ~3 tokens accrue within 30ms, so the next hit
      # must be allowed without waiting for a whole-second boundary
      :timer.sleep(30)

      assert {:allow, _} = TokenBucket.hit(table, key, refill_rate, capacity, 1)
    end

    test "denies with the real time until the next token, not a flat second", %{table: table} do
      key = "key"
      # One token every ~18.18ms.
      refill_rate = 55
      capacity = 10

      assert {:allow, 0} = TokenBucket.hit(table, key, refill_rate, capacity, capacity)

      # Short exactly one token: ceil(1000 / 55) == 19ms. A flat 1000 here
      # makes the caller sleep ~53x longer than the limiter actually requires.
      assert {:deny, retry_after} = TokenBucket.hit(table, key, refill_rate, capacity, 1)
      assert retry_after == 19

      # The wait scales with how many tokens the cost is short of.
      assert {:deny, retry_after_5} = TokenBucket.hit(table, key, refill_rate, capacity, 5)
      assert retry_after_5 == 91
    end

    test "the deny wait is long enough to actually pay the cost", %{table: table} do
      key = "key"
      refill_rate = 55
      capacity = 10

      assert {:allow, 0} = TokenBucket.hit(table, key, refill_rate, capacity, capacity)
      assert {:deny, retry_after} = TokenBucket.hit(table, key, refill_rate, capacity, 3)

      # Sleeping the advertised wait must be sufficient -- a wait that rounds
      # down would hand callers a retry that is still denied.
      :timer.sleep(retry_after)
      assert {:allow, _} = TokenBucket.hit(table, key, refill_rate, capacity, 3)
    end

    test "the advertised wait is sufficient across rates, costs and deficits", %{table: table} do
      # The refill path truncates DOWN and the deny path rounds UP, so it is
      # worth pinning that the two cannot conspire to hand a caller a wait
      # that leaves it still denied. Simulated rather than slept: seeding
      # `last_update` back by exactly the advertised wait is equivalent to the
      # caller sleeping it, and keeps the sweep deterministic and instant.
      for refill_rate <- [1, 2, 3, 7, 55, 100, 999, 1_000_000],
          capacity <- [1, 10, 1000],
          cost <- [1, 3, capacity],
          cost <= capacity,
          starting_level <- [0, div(cost, 2)],
          starting_level < cost do
        key = "sufficient:#{refill_rate}:#{capacity}:#{cost}:#{starting_level}"
        :ets.insert(table, {key, starting_level, System.system_time(:millisecond)})

        assert {:deny, wait} = TokenBucket.hit(table, key, refill_rate, capacity, cost)
        assert wait >= 1

        # Rewind the stored clock by exactly the advertised wait -- the state
        # the caller would find itself in having slept precisely that long.
        [{^key, level, last_update}] = :ets.lookup(table, key)
        :ets.insert(table, {key, level, last_update - wait})

        assert {:allow, _} = TokenBucket.hit(table, key, refill_rate, capacity, cost),
               "wait of #{wait}ms was too short for rate=#{refill_rate} " <>
                 "cap=#{capacity} cost=#{cost} level=#{starting_level}"
      end
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

  describe "race condition handling" do
    test "hit recovers when entry is deleted between insert_new and lookup", %{table: table} do
      key = "race_key"
      refill_rate = 10
      capacity = 10

      # Insert an entry, then delete it to simulate cleanup race
      :ets.insert(table, {key, 5, System.system_time(:millisecond)})
      :ets.delete(table, key)

      # hit should handle the missing entry gracefully
      assert {:allow, 9} = TokenBucket.hit(table, key, refill_rate, capacity, 1)
    end

    test "hit works on a fresh empty table", %{table: table} do
      key = "fresh_key"
      refill_rate = 10
      capacity = 10

      # Ensure key doesn't exist
      assert :ets.lookup(table, key) == []

      assert {:allow, 9} = TokenBucket.hit(table, key, refill_rate, capacity, 1)
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
