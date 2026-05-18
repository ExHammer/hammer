defmodule Hammer.Atomic.FixWindowPerKey do
  @moduledoc """
  This module implements a per-key fixed window rate-limiting algorithm using
  Erlang's `:atomics` module for atomic counters.

  Like the standard fixed window algorithm, requests are counted within a window of
  duration `scale`. Unlike the standard fixed window — which aligns every key to the
  same wall-clock boundary (multiples of `scale` since the Unix epoch) — this variant
  anchors each key's window to that key's **first hit**.

  For example, with a scale of 60 seconds:

  - User A's first request at `12:00:37` → A's window runs until `12:01:37`
  - User B's first request at `12:00:51` → B's window runs until `12:01:51`

  Once a key's window expires, the next hit for that key opens a fresh window starting
  at that moment.

  ## The algorithm

  1. When a request comes in for a key:
     - If the key has an active window (`expires_at > now`), increment its atomic
       counter.
     - Otherwise, start a new window: reset the counter to `increment` and set
       `expires_at = now + scale`.
  2. If the counter is `<= limit` → allow. Otherwise → deny and return time until the
     current window expires.

  ## When to use this vs `:fix_window` and `:sliding_window`

  The 2x boundary burst that affects `:fix_window` is **still theoretically possible**
  here, just at a per-key boundary instead of a globally synchronized one. The
  practical benefit is that boundaries are not globally synchronized, so they are
  harder to exploit deterministically, and a key has to wait a full `scale` between
  burst opportunities.

  This is essentially the same algorithm as the common Redis `INCR + EXPIRE NX`
  rate-limiting pattern.

  ## Options

  - `:clean_period` - How often to run the cleanup process (in milliseconds). Defaults
    to 1 minute.
  - `:key_older_than` - Maximum age for entries (in milliseconds) past their expiry
    before they are removed during cleanup. Defaults to 24 hours.

  ## Example

  ### Example configuration:

      MyApp.RateLimit.start_link(
        clean_period: :timer.minutes(5),
      )

  ### Example usage:

      defmodule MyApp.RateLimit do
        use Hammer, backend: :atomic, algorithm: :fix_window_per_key
      end

      MyApp.RateLimit.start_link(clean_period: :timer.minutes(1))

      # Allow 10 requests per second
      MyApp.RateLimit.hit("user_123", 1000, 10)
  """
  alias Hammer.Atomic

  @doc false
  @spec ets_opts() :: list()
  def ets_opts do
    [
      :named_table,
      :set,
      :public,
      {:read_concurrency, true},
      {:write_concurrency, true},
      {:decentralized_counters, true}
    ]
  end

  @doc """
  Checks if a key is allowed to perform an action based on the per-key fixed window
  algorithm.
  """
  @spec hit(
          table :: atom(),
          key :: term(),
          scale :: pos_integer(),
          limit :: pos_integer(),
          increment :: pos_integer()
        ) :: {:allow, non_neg_integer()} | {:deny, non_neg_integer()}
  def hit(table, key, scale, limit, increment) do
    now = Atomic.now()

    case :ets.lookup(table, key) do
      [{_, atomic}] ->
        do_hit(atomic, now, scale, limit, increment)

      [] ->
        :ets.insert_new(table, {key, :atomics.new(2, signed: false)})
        hit(table, key, scale, limit, increment)
    end
  end

  # Sentinel written to expires_at slot while a reset is in progress.
  # All other processes that see this value spin-retry until the winner
  # has written both the new counter and the real expires_at.
  @reset_lock 0xFFFFFFFFFFFFFFFF

  defp do_hit(atomic, now, scale, limit, increment) do
    expires_at = :atomics.get(atomic, 2)

    cond do
      expires_at == @reset_lock ->
        do_hit(atomic, now, scale, limit, increment)

      expires_at > now ->
        count = :atomics.add_get(atomic, 1, increment)
        if count <= limit, do: {:allow, count}, else: {:deny, expires_at - now}

      true ->
        case :atomics.compare_exchange(atomic, 2, expires_at, @reset_lock) do
          :ok ->
            :atomics.put(atomic, 1, increment)
            :atomics.put(atomic, 2, now + scale)
            allow_or_deny(increment, limit, scale)

          _ ->
            do_hit(atomic, now, scale, limit, increment)
        end
    end
  end

  defp allow_or_deny(increment, limit, scale) do
    if increment <= limit, do: {:allow, increment}, else: {:deny, scale}
  end

  @doc """
  Increments the counter for a given key without performing a limit check.
  """
  @spec inc(
          table :: atom(),
          key :: term(),
          scale :: pos_integer(),
          increment :: pos_integer()
        ) :: non_neg_integer()
  def inc(table, key, scale, increment) do
    now = Atomic.now()

    case :ets.lookup(table, key) do
      [{_, atomic}] ->
        do_inc(atomic, now, scale, increment)

      [] ->
        :ets.insert_new(table, {key, :atomics.new(2, signed: false)})
        inc(table, key, scale, increment)
    end
  end

  defp do_inc(atomic, now, scale, increment) do
    expires_at = :atomics.get(atomic, 2)

    cond do
      expires_at == @reset_lock ->
        do_inc(atomic, now, scale, increment)

      expires_at > now ->
        :atomics.add_get(atomic, 1, increment)

      true ->
        case :atomics.compare_exchange(atomic, 2, expires_at, @reset_lock) do
          :ok ->
            :atomics.put(atomic, 1, increment)
            :atomics.put(atomic, 2, now + scale)
            increment

          _ ->
            do_inc(atomic, now, scale, increment)
        end
    end
  end

  @doc """
  Sets the counter for a given key, refreshing the window to `now + scale`.
  """
  @spec set(
          table :: atom(),
          key :: term(),
          scale :: pos_integer(),
          count :: non_neg_integer()
        ) :: non_neg_integer()
  def set(table, key, scale, count) do
    new_expires_at = Atomic.now() + scale

    case :ets.lookup(table, key) do
      [{_, atomic}] ->
        :atomics.exchange(atomic, 1, count)
        :atomics.exchange(atomic, 2, new_expires_at)
        count

      [] ->
        :ets.insert(table, {key, :atomics.new(2, signed: false)})
        set(table, key, scale, count)
    end
  end

  @doc """
  Returns the current count for a given key.

  Returns `0` if the key has no active window (either never hit, or window has
  expired).
  """
  @spec get(table :: atom(), key :: term(), scale :: pos_integer()) :: non_neg_integer()
  def get(table, key, _scale) do
    now = Atomic.now()

    case :ets.lookup(table, key) do
      [{_, atomic}] ->
        expires_at = :atomics.get(atomic, 2)
        if expires_at > now, do: :atomics.get(atomic, 1), else: 0

      [] ->
        0
    end
  end

  @doc """
  Returns the expiration time (in milliseconds) of the current window for a given key.

  Returns `0` if the key has no active window.
  """
  @spec expires_at(table :: atom(), key :: term(), scale :: pos_integer()) :: non_neg_integer()
  def expires_at(table, key, _scale) do
    now = Atomic.now()

    case :ets.lookup(table, key) do
      [{_, atomic}] ->
        expires_at = :atomics.get(atomic, 2)
        if expires_at > now, do: expires_at, else: 0

      [] ->
        0
    end
  end

  @doc false
  @spec normalize_entry(key :: term(), atomic :: reference()) :: map()
  def normalize_entry(key, atomic) do
    count = :atomics.get(atomic, 1)
    expires_at = :atomics.get(atomic, 2)
    %{key: key, value: count, expired_at: expires_at}
  end
end
