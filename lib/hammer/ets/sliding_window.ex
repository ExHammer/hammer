defmodule Hammer.ETS.SlidingWindow do
  @moduledoc """
  This module implements the Rate Limiting Sliding Window algorithm.

  The sliding window algorithm works by tracking requests within a moving time window.
  Unlike a fixed window that resets at specific intervals, the sliding window
  provides a smoother rate limiting experience by considering the most recent
  window of time.

  For example, with a 60 second window:
  - At time t, we look back 60 seconds and count all requests in that period
  - At time t+1, we look back 60 seconds from t+1, dropping any requests older than that
  - This creates a "sliding" effect where the window gradually moves forward in time

  ## The algorithm:
  1. When a request comes in, we store it with the current timestamp
  2. To check if rate limit is exceeded, we:
     - Count all requests within the last <scale> seconds
     - If count <= limit: allow the request
     - If count > limit: deny and return time until oldest request expires
  3. Old entries outside the window are automatically cleaned up

  This provides more precise rate limiting compared to fixed windows, avoiding
  the edge case where a burst of requests spans a fixed window boundary.

  The sliding window algorithm is a good choice when:

  - You need precise rate limiting without allowing bursts at window boundaries
  - Accuracy of the rate limit is critical for your application
  - You can accept slightly higher storage overhead compared to fixed windows
  - You want to avoid sudden changes in allowed request rates

  ## Common use cases include:

  - API rate limiting where consistent request rates are important
  - Financial transaction rate limiting
  - User action throttling requiring precise control
  - Gaming or real-time applications needing smooth rate control
  - Security-sensitive rate limiting scenarios

  The main advantages over fixed windows are:

  - No possibility of 2x burst at window boundaries
  - Smoother rate limiting behavior
  - More predictable request patterns

  The tradeoffs are:
  - Slightly more complex implementation
  - Higher storage requirements (need to store individual request timestamps)
  - More computation required to check limits (need to count requests in window)

  For example, with a limit of 100 requests per minute:
  - Fixed window might allow 200 requests across a boundary (100 at 11:59, 100 at 12:00)
  - Sliding window ensures no more than 100 requests in ANY 60 second period

  The sliding window algorithm supports the following options:

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
        use Hammer, backend: :ets, algorithm: :sliding_window
      end

      MyApp.RateLimit.start_link(clean_period: :timer.minutes(1))

      # Allow 10 requests in any 1 second window
      MyApp.RateLimit.hit("user_123", 1000, 10)
  """
  alias Hammer.ETS.SlidingWindow

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
  Checks if a key is allowed to perform an action based on the sliding window algorithm.
  """
  @spec hit(
          table :: atom(),
          key :: term(),
          scale :: pos_integer(),
          limit :: pos_integer()
        ) :: {:allow, non_neg_integer()} | {:deny, non_neg_integer()}
  def hit(table, key, scale, limit) do
    now = now()

    # need to convert scale to milliseconds
    scale_ms = scale * 1000
    expires_at = scale_ms + now

    remove_old_entries_for_key(table, key, now)

    :ets.insert_new(table, {{key, now}, expires_at})
    count = SlidingWindow.get(table, key, scale)

    if count <= limit do
      {:allow, count}
    else
      # Get the earliest expiration time from all entries for this key
      earliest_expiry = get_earliest_expiry(table, key, now)
      earliest_expiry_ms = round((earliest_expiry - now) / 1000)
      {:deny, earliest_expiry_ms}
    end
  end

  @doc """
  Returns the count of requests for a given key
  """
  @spec get(table :: atom(), key :: term(), scale :: pos_integer()) :: non_neg_integer()
  def get(table, key, _scale) do
    now = now()

    match_spec = [
      {
        {{:"$1", :_}, :"$2"},
        [{:"=:=", {:const, key}, :"$1"}],
        [{:>, :"$2", {:const, now}}]
      }
    ]

    :ets.select_count(table, match_spec)
  end

  @doc """
  Cleans up all of the old entries from the table based on the `key_older_than` option.
  """
  @spec clean(config :: Hammer.ETS.config()) :: non_neg_integer()
  def clean(config) do
    now = now()
    table = config.table
    match_spec = [{{:_, :"$1"}, [], [{:<, :"$1", {:const, now}}]}]

    :ets.select_delete(table, match_spec)
  end

  defp get_earliest_expiry(table, key, now) do
    match_spec = [
      {
        {{:"$1", :_}, :"$2"},
        [{:"=:=", {:const, key}, :"$1"}, {:>, :"$2", {:const, now}}],
        [:"$2"]
      }
    ]

    table |> :ets.select(match_spec) |> Enum.min()
  end

  defp remove_old_entries_for_key(table, key, now) do
    match_spec = [
      {{{:"$1", :_}, :"$2"}, [{:"=:=", {:const, key}, :"$1"}], [{:<, :"$2", {:const, now}}]}
    ]

    :ets.select_delete(table, match_spec)
  end

  @compile inline: [now: 0]
  defp now do
    System.system_time(:microsecond)
  end
end
