defmodule Hammer.Atomic.FixWindow do
  @moduledoc """
  This module implements the Fix Window algorithm.

  The fixed window algorithm works by dividing time into fixed intervals or "windows"
  of a specified duration (scale). Each window tracks request counts independently.

  For example, with a 60 second window:
  - Window 1: 0-60 seconds
  - Window 2: 60-120 seconds
  - And so on...

  ## The algorithm:
  1. When a request comes in, we:
     - Calculate which window it belongs to based on current time
     - Increment the counter for that window
     - Store expiration time as end of window
  2. To check if rate limit is exceeded:
     - If count <= limit: allow request
     - If count > limit: deny and return time until window expires
  3. Old windows are automatically cleaned up after expiration

  This provides simple rate limiting but has edge cases where a burst of requests
  spanning a window boundary could allow up to 2x the limit in a short period.
  For more precise limiting, consider using the sliding window algorithm instead.

  The fixed window algorithm is a good choice when:

  - You need simple, predictable rate limiting with clear time boundaries
  - The exact precision of the rate limit is not critical
  - You want efficient implementation with minimal storage overhead
  - Your use case can tolerate potential bursts at window boundaries

  ## Common use cases include:

  - Basic API rate limiting where occasional bursts are acceptable
  - Protecting backend services from excessive load
  - Implementing fair usage policies
  - Scenarios where clear time-based quotas are desired (e.g. "100 requests per minute")

  The main tradeoff is that requests near window boundaries can allow up to 2x the
  intended limit in a short period. For example with a limit of 100 per minute:
  - 100 requests at 11:59:59
  - Another 100 requests at 12:00:01

  This results in 200 requests in 2 seconds, while still being within limits.
  If this behavior is problematic, consider using the sliding window algorithm instead.

  The fixed window algorithm supports the following options:

  - `:clean_period` - How often to run the cleanup process (in milliseconds)
    Defaults to 1 minute. The cleanup process removes expired window entries.

  ## Example

  ### Example configuration:

      MyApp.RateLimit.start_link(
        clean_period: :timer.minutes(5),
      )

  This would run cleanup every 5 minutes and clean up old windows.

  ### Example usage:

      defmodule MyApp.RateLimit do
        use Hammer, backend: :atomic, algorithm: :fix_window
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
  Checks if a key is allowed to perform an action based on the fixed window algorithm.
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
    window = div(now, scale)
    full_key = {key, window}
    expires_at = (window + 1) * scale

    case :ets.lookup(table, full_key) do
      [{_, atomic}] ->
        count = :atomics.add_get(atomic, 1, increment)
        :atomics.exchange(atomic, 2, expires_at)

        if count <= limit do
          {:allow, count}
        else
          {:deny, expires_at - now}
        end

      [] ->
        :ets.insert_new(table, {full_key, :atomics.new(2, signed: false)})
        hit(table, key, scale, limit, increment)
    end
  end

  @doc """
  Increments the counter for a given key in the fixed window algorithm.
  """
  @spec inc(
          table :: atom(),
          key :: term(),
          scale :: pos_integer(),
          increment :: pos_integer()
        ) ::
          non_neg_integer()
  def inc(table, key, scale, increment) do
    window = div(Atomic.now(), scale)
    full_key = {key, window}
    expires_at = (window + 1) * scale

    case :ets.lookup(table, full_key) do
      [{_, atomic}] ->
        :atomics.exchange(atomic, 2, expires_at)
        :atomics.add_get(atomic, 1, increment)

      [] ->
        :ets.insert(table, {full_key, :atomics.new(2, signed: false)})
        inc(table, key, scale, increment)
    end
  end

  @doc """
  Sets the counter for a given key in the fixed window algorithm.
  """
  @spec set(
          table :: atom(),
          key :: term(),
          scale :: pos_integer(),
          count :: non_neg_integer()
        ) ::
          non_neg_integer()
  def set(table, key, scale, count) do
    window = div(Atomic.now(), scale)
    full_key = {key, window}
    expires_at = (window + 1) * scale

    case :ets.lookup(table, full_key) do
      [{_, atomic}] ->
        :atomics.exchange(atomic, 2, expires_at)
        :atomics.exchange(atomic, 1, count)
        count

      [] ->
        :ets.insert(table, {full_key, :atomics.new(2, signed: false)})
        set(table, key, scale, count)
    end
  end

  @doc """
  Returns the count of requests for a given key within the last <scale> seconds.
  """
  @spec get(table :: atom(), key :: String.t(), scale :: pos_integer()) :: non_neg_integer()
  def get(table, key, scale) do
    window = div(Atomic.now(), scale)
    full_key = {key, window}

    case :ets.lookup(table, full_key) do
      [{_, atomic}] -> :atomics.get(atomic, 1)
      [] -> 0
    end
  end
end
