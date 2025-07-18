defmodule Hammer.ETS.TokenBucket do
  @moduledoc """
  This module implements the Token Bucket algorithm.
  The token bucket algorithm works by modeling a bucket that:
  - Fills with tokens at a constant rate (the refill rate)
  - Has a maximum capacity of tokens (the bucket size)
  - Each request consumes one or more tokens
  - If there are enough tokens, the request is allowed
  - If not enough tokens, the request is denied

  For example, with a refill rate of 10 tokens/second and bucket size of 100:
  - Tokens are added at 10 per second up to max of 100
  - Each request needs tokens to proceed
  - If bucket has enough tokens, request allowed and tokens consumed
  - If not enough tokens, request denied until bucket refills

  ## The algorithm:
  1. When a request comes in, we:
     - Calculate tokens added since last request based on time elapsed
     - Add new tokens to bucket (up to max capacity)
     - Try to consume tokens for the request
     - Store new token count and timestamp
  2. To check if rate limit is exceeded:
     - If enough tokens: allow request and consume tokens
     - If not enough: deny and return time until enough tokens refill
  3. Old entries are automatically cleaned up after expiration

  This provides smooth rate limiting with ability to handle bursts up to bucket size.
  The token bucket is a good choice when:

  - You need to allow temporary bursts of traffic
  - Want to enforce an average rate limit
  - Need to support different costs for different operations
  - Want to avoid the sharp edges of fixed windows

  Common use cases include:

  - API rate limiting with burst tolerance
  - Network traffic shaping
  - Resource allocation control
  - Gaming systems with "energy" mechanics
  - Scenarios needing flexible rate limits

  The main advantages are:
  - Natural handling of bursts
  - Flexible token costs for different operations
  - Smooth rate limiting behavior
  - Simple to reason about

  The tradeoffs are:
  - Need to track token count and last update time
  - May need tuning of bucket size and refill rate
  - More complex than fixed windows

  For example with 100 tokens/minute limit and 500 bucket size:
  - Can handle bursts using saved up tokens
  - Automatically smooths out over time
  - Different operations can cost different amounts
  - More flexible than fixed request counts

  The token bucket algorithm supports the following options:

  - `:clean_period` - How often to run the cleanup process (in milliseconds)
    Defaults to 1 minute. The cleanup process removes expired bucket entries.

  - `:key_older_than` - Optional maximum age for bucket entries (in milliseconds)
    If set, entries older than this will be removed during cleanup.
    This helps prevent memory growth from abandoned buckets.

  ## Example
  ### Example configuration:

      MyApp.RateLimit.start_link(
        clean_period: :timer.minutes(5),
        key_older_than: :timer.hours(24)
      )

  This would run cleanup every 5 minutes and remove buckets not used in 24 hours.

  ### Example usage:

      defmodule MyApp.RateLimit do
        use Hammer, backend: :ets, algorithm: :token_bucket
      end

      MyApp.RateLimit.start_link(clean_period: :timer.minutes(1))

      # Allow 10 tokens per second with max capacity of 100
      MyApp.RateLimit.hit("user_123", 10, 100, 1)
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
  Checks if a key is allowed to perform an action, and consume the bucket by the given amount.
  """
  @spec hit(
          table :: atom(),
          key :: term(),
          refill_rate :: pos_integer(),
          capacity :: pos_integer(),
          cost :: pos_integer()
        ) :: {:allow, non_neg_integer()} | {:deny, non_neg_integer()}
  def hit(table, key, refill_rate, capacity, cost \\ 1) do
    now = System.system_time(:second)

    # Try to insert new empty bucket if doesn't exist
    :ets.insert_new(table, {key, capacity, now})

    [{^key, current_level, last_update}] = :ets.lookup(table, key)
    new_tokens = trunc((now - last_update) * refill_rate)

    current_tokens = min(capacity, current_level + new_tokens)

    if current_tokens >= cost do
      final_level = current_tokens - cost
      :ets.insert(table, {key, final_level, now})
      {:allow, final_level}
    else
      {:deny, 1000}
    end
  end

  @doc """
  Returns the current level of the bucket for a given key.
  """
  @spec get(table :: atom(), key :: term()) :: non_neg_integer()
  def get(table, key) do
    case :ets.lookup(table, key) do
      [] ->
        0

      [{^key, level, _last_update}] ->
        level

      _ ->
        0
    end
  end

  @doc """
  Cleans up all of the old entries from the table based on the `key_older_than` option.
  """
  @spec clean(config :: ETS.config()) :: non_neg_integer()
  def clean(config) do
    now = ETS.now()
    older_than = now - config.key_older_than

    match_spec = [{{:_, :_, :"$1"}, [], [{:<, :"$1", {:const, older_than}}]}]
    :ets.select_delete(config.table, match_spec)
  end
end
