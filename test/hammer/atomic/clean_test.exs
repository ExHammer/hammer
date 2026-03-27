defmodule Hammer.Atomic.CleanTest do
  use ExUnit.Case, async: true

  defmodule RateAtomicLimit do
    use Hammer, backend: :atomic
  end

  defmodule RateAtomicLimitLeakyBucket do
    use Hammer, backend: :atomic, algorithm: :leaky_bucket
  end

  defmodule RateAtomicLimitTokenBucket do
    use Hammer, backend: :atomic, algorithm: :token_bucket
  end

  defmodule RateAtomicBeforeClean do
    use Hammer, backend: :atomic
  end

  defmodule RateAtomicBeforeCleanTokenBucket do
    use Hammer, backend: :atomic, algorithm: :token_bucket
  end

  defmodule RateAtomicBeforeCleanLeakyBucket do
    use Hammer, backend: :atomic, algorithm: :leaky_bucket
  end

  defmodule RateAtomicBeforeCleanRaises do
    use Hammer, backend: :atomic
  end

  defmodule RateAtomicBeforeCleanNoExpired do
    use Hammer, backend: :atomic
  end

  defmodule RateAtomicBeforeCleanMFA do
    use Hammer, backend: :atomic
  end

  defmodule CallbackHandler do
    def handle(algorithm, entries, extra) do
      send(extra, {:before_clean_mfa, algorithm, entries})
    end
  end

  # Helper function to wait for a condition to be true
  defp eventually(fun, timeout \\ 5000, interval \\ 50) do
    eventually(fun, timeout, interval, System.monotonic_time(:millisecond))
  end

  defp eventually(fun, timeout, interval, start_time) do
    if fun.() do
      :ok
    else
      now = System.monotonic_time(:millisecond)

      if now - start_time > timeout do
        flunk("Condition not met within #{timeout}ms")
      else
        Process.sleep(interval)
        eventually(fun, timeout, interval, start_time)
      end
    end
  end

  test "cleaning works for fix window/default ets backend" do
    start_supervised!({RateAtomicLimit, clean_period: 50, key_older_than: 10})

    key = "key"
    scale = 100
    count = 10

    assert {:allow, 1} = RateAtomicLimit.hit(key, scale, count)

    assert [_] = :ets.tab2list(RateAtomicLimit)

    # Wait for cleanup to occur by polling the table
    eventually(fn ->
      :ets.tab2list(RateAtomicLimit) == []
    end)
  end

  test "cleaning works for token bucket" do
    start_supervised!({RateAtomicLimitTokenBucket, clean_period: 100, key_older_than: 1000})

    key = "key"
    refill_rate = 1
    capacity = 10

    assert {:allow, 9} = RateAtomicLimitTokenBucket.hit(key, refill_rate, capacity, 1)

    assert [_] = :ets.tab2list(RateAtomicLimitTokenBucket)

    # Wait for cleanup to occur by polling the table
    eventually(fn ->
      :ets.tab2list(RateAtomicLimitTokenBucket) == []
    end)
  end

  test "cleaning works for leaky bucket" do
    start_supervised!({RateAtomicLimitLeakyBucket, clean_period: 100, key_older_than: 1000})

    key = "key"
    leak_rate = 1
    capacity = 10

    assert {:allow, 1} = RateAtomicLimitLeakyBucket.hit(key, leak_rate, capacity, 1)

    assert [_] = :ets.tab2list(RateAtomicLimitLeakyBucket)

    # Wait for cleanup to occur by polling the table
    eventually(fn ->
      :ets.tab2list(RateAtomicLimitLeakyBucket) == []
    end)
  end

  describe "before_clean callback" do
    test "receives correct algorithm atom and entries for fix_window" do
      test_pid = self()

      callback = fn algorithm, entries ->
        send(test_pid, {:before_clean, algorithm, entries})
      end

      start_supervised!(
        {RateAtomicBeforeClean, clean_period: 50, key_older_than: 10, before_clean: callback}
      )

      assert {:allow, 1} = RateAtomicBeforeClean.hit("user_1", 100, 10)

      assert_receive {:before_clean, :fix_window, entries}, 5000
      assert [%{key: {"user_1", _window}, value: 1, expired_at: expired_at}] = entries
      assert is_integer(expired_at)

      eventually(fn ->
        :ets.tab2list(RateAtomicBeforeClean) == []
      end)
    end

    test "receives correct algorithm atom and entries for token_bucket" do
      test_pid = self()

      callback = fn algorithm, entries ->
        send(test_pid, {:before_clean, algorithm, entries})
      end

      start_supervised!(
        {RateAtomicBeforeCleanTokenBucket,
         clean_period: 100, key_older_than: 1000, before_clean: callback}
      )

      assert {:allow, 9} = RateAtomicBeforeCleanTokenBucket.hit("user_1", 1, 10, 1)

      assert_receive {:before_clean, :token_bucket, entries}, 5000
      assert [%{key: "user_1", value: _level, expired_at: expired_at}] = entries
      assert is_integer(expired_at)

      eventually(fn ->
        :ets.tab2list(RateAtomicBeforeCleanTokenBucket) == []
      end)
    end

    test "receives correct algorithm atom and entries for leaky_bucket" do
      test_pid = self()

      callback = fn algorithm, entries ->
        send(test_pid, {:before_clean, algorithm, entries})
      end

      start_supervised!(
        {RateAtomicBeforeCleanLeakyBucket,
         clean_period: 100, key_older_than: 1000, before_clean: callback}
      )

      assert {:allow, 1} = RateAtomicBeforeCleanLeakyBucket.hit("user_1", 1, 10, 1)

      assert_receive {:before_clean, :leaky_bucket, entries}, 5000
      assert [%{key: "user_1", value: _fill, expired_at: expired_at}] = entries
      assert is_integer(expired_at)

      eventually(fn ->
        :ets.tab2list(RateAtomicBeforeCleanLeakyBucket) == []
      end)
    end

    test "entries are deleted even when callback raises" do
      start_supervised!(
        {RateAtomicBeforeCleanRaises,
         clean_period: 50,
         key_older_than: 10,
         before_clean: fn _algorithm, _entries -> raise "boom" end}
      )

      assert {:allow, 1} = RateAtomicBeforeCleanRaises.hit("user_1", 100, 10)

      eventually(fn ->
        :ets.tab2list(RateAtomicBeforeCleanRaises) == []
      end)
    end

    test "callback is not invoked when nothing expired" do
      test_pid = self()

      callback = fn _algorithm, _entries ->
        send(test_pid, :before_clean_called)
      end

      start_supervised!(
        {RateAtomicBeforeCleanNoExpired,
         clean_period: 50, key_older_than: :timer.hours(24), before_clean: callback}
      )

      # Don't insert any data, just wait for a clean cycle
      Process.sleep(200)
      refute_received :before_clean_called
    end

    test "MFA tuple form works" do
      test_pid = self()

      start_supervised!(
        {RateAtomicBeforeCleanMFA,
         clean_period: 50,
         key_older_than: 10,
         before_clean: {CallbackHandler, :handle, [test_pid]}}
      )

      assert {:allow, 1} = RateAtomicBeforeCleanMFA.hit("user_1", 100, 10)

      assert_receive {:before_clean_mfa, :fix_window, entries}, 5000
      assert [%{key: {"user_1", _window}, value: 1}] = entries

      eventually(fn ->
        :ets.tab2list(RateAtomicBeforeCleanMFA) == []
      end)
    end
  end
end
