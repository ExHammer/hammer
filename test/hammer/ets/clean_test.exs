defmodule Hammer.ETS.CleanTest do
  use ExUnit.Case, async: true

  defmodule RateLimit do
    use Hammer, backend: :ets
  end

  defmodule RateLimitSlidingWindow do
    use Hammer, backend: :ets, algorithm: :sliding_window
  end

  defmodule RateLimitLeakyBucket do
    use Hammer, backend: :ets, algorithm: :leaky_bucket
  end

  defmodule RateLimitTokenBucket do
    use Hammer, backend: :ets, algorithm: :token_bucket
  end

  defmodule RateLimitBeforeClean do
    use Hammer, backend: :ets
  end

  defmodule RateLimitBeforeCleanSlidingWindow do
    use Hammer, backend: :ets, algorithm: :sliding_window
  end

  defmodule RateLimitBeforeCleanLeakyBucket do
    use Hammer, backend: :ets, algorithm: :leaky_bucket
  end

  defmodule RateLimitBeforeCleanTokenBucket do
    use Hammer, backend: :ets, algorithm: :token_bucket
  end

  defmodule RateLimitBeforeCleanRaises do
    use Hammer, backend: :ets
  end

  defmodule RateLimitBeforeCleanNoExpired do
    use Hammer, backend: :ets
  end

  defmodule RateLimitBeforeCleanMFA do
    use Hammer, backend: :ets
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
    start_supervised!({RateLimit, clean_period: 100})

    key = "key"
    scale = 100
    count = 10

    assert {:allow, 1} = RateLimit.hit(key, scale, count)

    assert [_] = :ets.tab2list(RateLimit)

    # Wait for cleanup to occur by polling the table
    eventually(fn ->
      :ets.tab2list(RateLimit) == []
    end)
  end

  test "cleaning works for sliding window" do
    start_supervised!({RateLimitSlidingWindow, clean_period: 100})

    key = "key"
    scale = 100
    count = 10

    assert {:allow, 1} = RateLimitSlidingWindow.hit(key, scale, count)

    assert [_] = :ets.tab2list(RateLimitSlidingWindow)

    # Wait for cleanup to occur by polling the table
    eventually(fn ->
      :ets.tab2list(RateLimitSlidingWindow) == []
    end)
  end

  test "cleaning works for token bucket" do
    start_supervised!({RateLimitTokenBucket, clean_period: 100, key_older_than: 1000})

    key = "key"
    refill_rate = 1
    capacity = 10

    assert {:allow, 9} = RateLimitTokenBucket.hit(key, refill_rate, capacity, 1)

    assert [_] = :ets.tab2list(RateLimitTokenBucket)

    # Wait for cleanup to occur by polling the table
    eventually(fn ->
      :ets.tab2list(RateLimitTokenBucket) == []
    end)
  end

  test "cleaning works for leaky bucket" do
    start_supervised!({RateLimitLeakyBucket, clean_period: 100, key_older_than: 1000})

    key = "key"
    leak_rate = 1
    capacity = 10

    assert {:allow, 1} = RateLimitLeakyBucket.hit(key, leak_rate, capacity, 1)

    assert [_] = :ets.tab2list(RateLimitLeakyBucket)

    # Wait for cleanup to occur by polling the table
    eventually(fn ->
      :ets.tab2list(RateLimitLeakyBucket) == []
    end)
  end

  describe "before_clean callback" do
    test "receives correct algorithm atom and entries for fix_window" do
      test_pid = self()

      callback = fn algorithm, entries ->
        send(test_pid, {:before_clean, algorithm, entries})
      end

      start_supervised!({RateLimitBeforeClean, clean_period: 100, before_clean: callback})

      assert {:allow, 1} = RateLimitBeforeClean.hit("user_1", 100, 10)

      assert_receive {:before_clean, :fix_window, entries}, 5000
      assert [%{key: "user_1", value: 1, expired_at: expired_at}] = entries
      assert is_integer(expired_at)

      eventually(fn ->
        :ets.tab2list(RateLimitBeforeClean) == []
      end)
    end

    test "receives correct algorithm atom and entries for sliding_window" do
      test_pid = self()

      callback = fn algorithm, entries ->
        send(test_pid, {:before_clean, algorithm, entries})
      end

      start_supervised!(
        {RateLimitBeforeCleanSlidingWindow, clean_period: 100, before_clean: callback}
      )

      assert {:allow, 1} = RateLimitBeforeCleanSlidingWindow.hit("user_1", 100, 10)

      assert_receive {:before_clean, :sliding_window, entries}, 5000
      assert [%{key: "user_1", value: 1, expired_at: expired_at}] = entries
      assert is_integer(expired_at)

      eventually(fn ->
        :ets.tab2list(RateLimitBeforeCleanSlidingWindow) == []
      end)
    end

    test "receives correct algorithm atom and entries for token_bucket" do
      test_pid = self()

      callback = fn algorithm, entries ->
        send(test_pid, {:before_clean, algorithm, entries})
      end

      start_supervised!(
        {RateLimitBeforeCleanTokenBucket,
         clean_period: 100, key_older_than: 1000, before_clean: callback}
      )

      assert {:allow, 9} = RateLimitBeforeCleanTokenBucket.hit("user_1", 1, 10, 1)

      assert_receive {:before_clean, :token_bucket, entries}, 5000
      assert [%{key: "user_1", value: _level, expired_at: expired_at}] = entries
      assert is_integer(expired_at)

      eventually(fn ->
        :ets.tab2list(RateLimitBeforeCleanTokenBucket) == []
      end)
    end

    test "receives correct algorithm atom and entries for leaky_bucket" do
      test_pid = self()

      callback = fn algorithm, entries ->
        send(test_pid, {:before_clean, algorithm, entries})
      end

      start_supervised!(
        {RateLimitBeforeCleanLeakyBucket,
         clean_period: 100, key_older_than: 1000, before_clean: callback}
      )

      assert {:allow, 1} = RateLimitBeforeCleanLeakyBucket.hit("user_1", 1, 10, 1)

      assert_receive {:before_clean, :leaky_bucket, entries}, 5000
      assert [%{key: "user_1", value: _fill, expired_at: expired_at}] = entries
      assert is_integer(expired_at)

      eventually(fn ->
        :ets.tab2list(RateLimitBeforeCleanLeakyBucket) == []
      end)
    end

    test "entries are deleted even when callback raises" do
      start_supervised!(
        {RateLimitBeforeCleanRaises,
         clean_period: 100, before_clean: fn _algorithm, _entries -> raise "boom" end}
      )

      assert {:allow, 1} = RateLimitBeforeCleanRaises.hit("user_1", 100, 10)

      eventually(fn ->
        :ets.tab2list(RateLimitBeforeCleanRaises) == []
      end)
    end

    test "callback is not invoked when nothing expired" do
      test_pid = self()

      callback = fn _algorithm, _entries ->
        send(test_pid, :before_clean_called)
      end

      start_supervised!(
        {RateLimitBeforeCleanNoExpired, clean_period: 100, before_clean: callback}
      )

      # Don't insert any data, just wait for a clean cycle
      Process.sleep(200)
      refute_received :before_clean_called
    end

    test "MFA tuple form works" do
      test_pid = self()

      start_supervised!(
        {RateLimitBeforeCleanMFA,
         clean_period: 100, before_clean: {CallbackHandler, :handle, [test_pid]}}
      )

      assert {:allow, 1} = RateLimitBeforeCleanMFA.hit("user_1", 100, 10)

      assert_receive {:before_clean_mfa, :fix_window, entries}, 5000
      assert [%{key: "user_1", value: 1}] = entries

      eventually(fn ->
        :ets.tab2list(RateLimitBeforeCleanMFA) == []
      end)
    end
  end
end
