defmodule Hammer.Atomic.TokenBucket do
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

  ## Common use cases include:

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
        use Hammer, backend: :atomic, algorithm: :token_bucket
      end

      MyApp.RateLimit.start_link(clean_period: :timer.minutes(1))

      # Allow 10 tokens per second with max capacity of 100
      MyApp.RateLimit.hit("user_123", 10, 100, 1)
  """

  import Bitwise

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

  # Pack the clock and the fill level into one 64-bit value for atomic CAS.
  # High 32 bits: low 32 bits of the millisecond clock, Low 32 bits: fill level
  @clock_mask 0xFFFFFFFF
  @clock_half 0x80000000
  @compile {:inline, pack: 2, unpack: 1}
  defp pack(timestamp, fill) do
    (timestamp &&& @clock_mask) <<< 32 ||| (fill &&& 0xFFFFFFFF)
  end

  defp unpack(packed) do
    timestamp = packed >>> 32 &&& @clock_mask
    fill = packed &&& 0xFFFFFFFF
    {timestamp, fill}
  end

  @doc """
  Checks if a key is allowed to perform an action, and consume the bucket by the given amount.

  On `{:deny, retry_after}`, `retry_after` is the time in milliseconds until the bucket
  holds enough tokens to pay `cost`.
  """
  @spec hit(
          table :: atom(),
          key :: term(),
          refill_rate :: pos_integer(),
          capacity :: pos_integer(),
          cost :: pos_integer()
        ) :: {:allow, non_neg_integer()} | {:deny, non_neg_integer()}
  def hit(table, key, refill_rate, capacity, cost \\ 1) do
    now = System.system_time(:millisecond)

    case :ets.lookup(table, key) do
      [{_, atomic}] ->
        do_hit(atomic, now, refill_rate, capacity, cost)

      [] ->
        # Initialize the atomic before publishing it in ETS. Once insert_new
        # succeeds, other processes can look it up immediately, and reading
        # an uninitialized (zero) packed value would look like an empty bucket
        # at timestamp 0.
        atomic = :atomics.new(2, signed: false)
        :atomics.put(atomic, 1, pack(now, capacity))
        :atomics.put(atomic, 2, div(now, 1000))

        :ets.insert_new(table, {key, atomic})

        hit(table, key, refill_rate, capacity, cost)
    end
  end

  defp do_hit(atomic, now, refill_rate, capacity, cost) do
    current_packed = :atomics.get(atomic, 1)
    {last_update, current_fill} = unpack(current_packed)

    elapsed = elapsed(atomic, now, last_update)
    new_tokens = trunc(elapsed * refill_rate / 1000)
    current_tokens = min(capacity, current_fill + new_tokens)

    if current_tokens >= cost do
      final_level = current_tokens - cost

      # Advance the clock only by the time whose tokens were credited, so the
      # sub-token remainder carries into the next hit; stamping `now` would
      # discard it, and a caller hitting faster than one token period would
      # never refill. The exception is a refill that overflowed the bucket:
      # the surplus is discarded, so the clock snaps to `now` or an idle
      # bucket banks unbounded credit.
      new_last_update =
        cond do
          new_tokens == 0 -> last_update
          current_tokens == capacity -> now
          true -> last_update + trunc(new_tokens * 1000 / refill_rate)
        end

      new_packed = pack(new_last_update, final_level)

      case :atomics.compare_exchange(atomic, 1, current_packed, new_packed) do
        :ok ->
          # Update slot 2 for cleanup tracking (non-critical, just for age-based cleanup)
          :atomics.put(atomic, 2, div(now, 1000))
          {:allow, final_level}

        _current_value ->
          # CAS failed, another process modified the value; retry
          do_hit(atomic, now, refill_rate, capacity, cost)
      end
    else
      {:deny, retry_after(cost - current_tokens, refill_rate)}
    end
  end

  # The packed clock only has the low 32 bits of the time, so the difference
  # is taken modulo 2^32 and read as signed. A negative difference means a
  # concurrent hit that read the time after us has already stored a later
  # clock: no time has passed as far as this bucket is concerned.
  #
  # That leaves about 24.8 days before a real gap stops fitting. Slot 2 holds
  # the whole-second time of the last allowed hit, unwrapped, so a bucket idle
  # for longer than that is recognised there and its true idle time is used.
  defp elapsed(atomic, now, last_update) do
    idle = now - :atomics.get(atomic, 2) * 1000

    case now - last_update &&& @clock_mask do
      _wrapped when idle >= @clock_half -> idle
      elapsed when elapsed < @clock_half -> elapsed
      _behind -> 0
    end
  end

  # Milliseconds until the bucket has gained `deficit` more tokens, rounded up
  # so that sleeping it is always sufficient.
  #
  # A rate of 0 never gets there. There is no honest wait to report, so keep
  # the flat second this bucket always answered with.
  defp retry_after(deficit, rate) when rate > 0, do: max(ceil(deficit * 1000 / rate), 1)
  defp retry_after(_deficit, _rate), do: 1000

  @doc """
  Returns the current level of the bucket for a given key.
  """
  @spec get(table :: atom(), key :: term()) :: non_neg_integer()
  def get(table, key) do
    case :ets.lookup(table, key) do
      [] ->
        0

      [{_, atomic}] ->
        packed = :atomics.get(atomic, 1)
        {_timestamp, fill} = unpack(packed)
        fill

      _ ->
        0
    end
  end

  @doc false
  @spec normalize_entry(key :: term(), atomic :: reference()) :: map()
  def normalize_entry(key, atomic) do
    packed = :atomics.get(atomic, 1)
    {_timestamp, fill} = unpack(packed)
    last_update = :atomics.get(atomic, 2)
    %{key: key, value: fill, expired_at: last_update * 1000}
  end
end
