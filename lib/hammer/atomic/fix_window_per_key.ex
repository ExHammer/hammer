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

    with [{_, atomic} = entry] <- :ets.lookup(table, key),
         expires_at = :atomics.get(atomic, 2),
         true <- expires_at > now or retire(table, entry) do
      count = :atomics.add_get(atomic, 1, increment)
      if count <= limit, do: {:allow, count}, else: {:deny, expires_at - now}
    else
      _no_active_window -> hit_new_window(table, key, now, scale, limit, increment)
    end
  end

  defp hit_new_window(table, key, now, scale, limit, increment) do
    cond do
      not open_window(table, key, increment, now + scale) ->
        hit(table, key, scale, limit, increment)

      increment <= limit ->
        {:allow, increment}

      true ->
        {:deny, scale}
    end
  end

  # A window is one atomics ref, and a ref is never reset: when it expires it
  # is retired from the table and a fresh ref takes its place. Both steps are
  # single atomic ETS operations, so there is no lock to hold and nothing for
  # other processes to wait on, however the caller dies.
  #
  # `delete_object/2` only removes the exact expired ref, so it cannot take
  # out a window a faster process has already opened. A hit that looked the
  # old ref up while it was still live and lands after it was retired is
  # counted in the old window, which is the window its clock placed it in.
  #
  # Always returns false, so it reads as "no active window" in `with`.
  defp retire(table, entry) do
    :ets.delete_object(table, entry)
    false
  end

  # Publishes a window that already holds `count`. The ref is filled in before
  # it is inserted, so no process can see it empty. Returns false if another
  # process opened the window first; the caller then counts against theirs.
  defp open_window(table, key, count, expires_at) do
    :ets.insert_new(table, {key, new_window(count, expires_at)})
  end

  defp new_window(count, expires_at) do
    atomic = :atomics.new(2, signed: false)
    :atomics.put(atomic, 1, count)
    :atomics.put(atomic, 2, expires_at)
    atomic
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

    with [{_, atomic} = entry] <- :ets.lookup(table, key),
         true <- :atomics.get(atomic, 2) > now or retire(table, entry) do
      :atomics.add_get(atomic, 1, increment)
    else
      _no_active_window ->
        if open_window(table, key, increment, now + scale) do
          increment
        else
          inc(table, key, scale, increment)
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
    # A fresh window replaces whatever is there in one step, so a concurrent
    # hit sees either the old window or the new one, never a half-written mix.
    :ets.insert(table, {key, new_window(count, Atomic.now() + scale)})
    count
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
