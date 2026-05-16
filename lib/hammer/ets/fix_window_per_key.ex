defmodule Hammer.ETS.FixWindowPerKey do
  @moduledoc """
  This module implements a per-key fixed window rate-limiting algorithm.

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
     - If the key has an active window (`expires_at > now`), increment its counter.
     - Otherwise, start a new window: reset the counter to `increment` and set
       `expires_at = now + scale`.
  2. If the counter is `<= limit` → allow. Otherwise → deny and return time until the
     current window expires.
  3. Expired entries are cleaned up by the periodic cleanup task.

  ## When to use this vs `:fix_window` and `:sliding_window`

  The 2x boundary burst that affects `:fix_window` is **still theoretically possible**
  here, just at a per-key boundary instead of a globally synchronized one. Example:

  - 100 requests at `12:00:37` (window `[12:00:37, 12:01:37)`)
  - 100 more at `12:01:38` (window `[12:01:38, 12:02:38)`)
  - That's 200 requests in roughly one second.

  The practical benefit is that boundaries are not globally synchronized. With
  `:fix_window`, every key flips at the same wall-clock instant (e.g. every minute on
  the minute), so an attacker who knows your `scale` can time bursts deterministically.
  With `:fix_window_per_key`, each key's boundary is at a different moment, and a key
  has to wait a full `scale` between burst opportunities.

  Choose `:fix_window_per_key` when:

  - You want `:fix_window`-style simplicity and the same one-entry-per-key memory
    footprint, but find globally-synchronized boundaries undesirable.
  - You're familiar with the Redis `INCR + EXPIRE NX` rate-limiting pattern — this is
    essentially the same algorithm.

  Choose `:fix_window` when boundaries aligned to the wall clock are useful for your
  use case (clear time-based quotas like "100 requests per minute, starting on the
  minute").

  Choose `:sliding_window` when you need precise enforcement — never more than `limit`
  in *any* `scale`-length interval. It costs more memory (one entry per request) and
  CPU per check, but eliminates the boundary burst entirely.

  ## Options

  - `:clean_period` - How often to run the cleanup process (in milliseconds). Defaults
    to 1 minute. The cleanup process removes expired entries.

  ## Example

  ### Example configuration:

      MyApp.RateLimit.start_link(
        clean_period: :timer.minutes(5),
      )

  ### Example usage:

      defmodule MyApp.RateLimit do
        use Hammer, backend: :ets, algorithm: :fix_window_per_key
      end

      MyApp.RateLimit.start_link(clean_period: :timer.minutes(1))

      # Allow 10 requests per second
      MyApp.RateLimit.hit("user_123", 1000, 10)
  """
  alias Hammer.ETS

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
    now = ETS.now()

    case :ets.lookup(table, key) do
      [{^key, _count, expires_at}] when expires_at > now ->
        count = ETS.update_counter(table, key, increment, expires_at)

        if count <= limit do
          {:allow, count}
        else
          {:deny, expires_at - now}
        end

      _ ->
        new_expires_at = now + scale

        cond do
          :ets.insert_new(table, {key, increment, new_expires_at}) ->
            allow_or_deny(increment, limit, scale)

          :ets.select_replace(table, [
            {{key, :_, :"$1"}, [{:<, :"$1", {:const, now}}],
             [{:const, {key, increment, new_expires_at}}]}
          ]) == 1 ->
            allow_or_deny(increment, limit, scale)

          true ->
            hit(table, key, scale, limit, increment)
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
    now = ETS.now()

    case :ets.lookup(table, key) do
      [{^key, _count, expires_at}] when expires_at > now ->
        ETS.update_counter(table, key, increment, expires_at)

      _ ->
        new_expires_at = now + scale

        cond do
          :ets.insert_new(table, {key, increment, new_expires_at}) ->
            increment

          :ets.select_replace(table, [
            {{key, :_, :"$1"}, [{:<, :"$1", {:const, now}}],
             [{:const, {key, increment, new_expires_at}}]}
          ]) == 1 ->
            increment

          true ->
            inc(table, key, scale, increment)
        end
    end
  end

  @doc """
  Sets the counter for a given key, refreshing the window to `now + scale`.
  """
  @spec set(table :: atom(), key :: term(), scale :: pos_integer(), count :: non_neg_integer()) ::
          non_neg_integer()
  def set(table, key, scale, count) do
    new_expires_at = ETS.now() + scale
    :ets.insert(table, {key, count, new_expires_at})
    count
  end

  @doc """
  Returns the current count for a given key.

  Returns `0` if the key has no active window (either never hit, or window has expired).
  """
  @spec get(table :: atom(), key :: term(), scale :: pos_integer()) :: non_neg_integer()
  def get(table, key, _scale) do
    now = ETS.now()

    case :ets.lookup(table, key) do
      [{^key, count, expires_at}] when expires_at > now -> count
      _ -> 0
    end
  end

  @doc """
  Returns the expiration time (in milliseconds) of the current window for a given key.

  Returns `0` if the key has no active window.
  """
  @spec expires_at(table :: atom(), key :: term(), scale :: pos_integer()) :: non_neg_integer()
  def expires_at(table, key, _scale) do
    now = ETS.now()

    case :ets.lookup(table, key) do
      [{^key, _count, expires_at}] when expires_at > now -> expires_at
      _ -> 0
    end
  end

  @doc """
  Cleans up all of the expired entries from the table.
  """
  @spec clean(config :: ETS.config()) :: non_neg_integer()
  def clean(config) do
    match_spec = [{{:_, :_, :"$1"}, [], [{:<, :"$1", {:const, ETS.now()}}]}]
    :ets.select_delete(config.table, match_spec)
  end

  @doc false
  @spec select_expired(config :: ETS.config()) :: list()
  def select_expired(config) do
    match_spec = [{{:_, :_, :"$1"}, [{:<, :"$1", {:const, ETS.now()}}], [:"$_"]}]
    :ets.select(config.table, match_spec)
  end

  @doc false
  @spec normalize_expired(expired :: list()) :: list(map())
  def normalize_expired(expired) do
    Enum.map(expired, fn {key, count, expires_at} ->
      %{key: key, value: count, expired_at: expires_at}
    end)
  end
end
