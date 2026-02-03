defmodule Hammer.Atomic.LeakyBucket do
  @moduledoc """
  This module implements the Leaky Bucket algorithm.

  The leaky bucket algorithm works by modeling a bucket that:
  - Fills up with requests at the input rate
  - "Leaks" requests at a constant rate
  - Has a maximum capacity (the bucket size)

  For example, with a leak rate of 10 requests/second and bucket size of 100:
  - Requests add to the bucket's current level
  - The bucket leaks 10 requests per second steadily
  - If bucket reaches capacity (100), new requests are denied
  - Once bucket level drops, new requests are allowed again

  ## The algorithm:
  1. When a request comes in, we:
     - Calculate how much has leaked since last request
     - Subtract leaked amount from current bucket level
     - Try to add new request to bucket
     - Store new bucket level and timestamp
  2. To check if rate limit is exceeded:
     - If new bucket level <= capacity: allow request
     - If new bucket level > capacity: deny and return time until enough leaks
  3. Old entries are automatically cleaned up after expiration

  This provides smooth rate limiting with ability to handle bursts up to bucket size.
  The leaky bucket is a good choice when:

  - You need to enforce a constant processing rate
  - Want to allow temporary bursts within bucket capacity
  - Need to smooth out traffic spikes
  - Want to prevent resource exhaustion

  ## Common use cases include:

  - API rate limiting needing consistent throughput
  - Network traffic shaping
  - Service protection from sudden load spikes
  - Queue processing rate control
  - Scenarios needing both burst tolerance and steady-state limits

  The main advantages are:
  - Smooth, predictable output rate
  - Configurable burst tolerance
  - Natural queueing behavior

  The tradeoffs are:
  - More complex implementation than fixed windows
  - Need to track last request time and current bucket level
  - May need tuning of bucket size and leak rate parameters

  For example, with 100 requests/sec limit and 500 bucket size:
  - Can handle bursts of up to 500 requests
  - But long-term average rate won't exceed 100/sec
  - Provides smoother traffic than fixed windows

  The leaky bucket algorithm supports the following options:

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
        use Hammer, backend: :atomic, algorithm: :leaky_bucket
      end

      MyApp.RateLimit.start_link(clean_period: :timer.minutes(1))

      # Allow 100 requests/sec leak rate with max capacity of 500
      MyApp.RateLimit.hit("user_123", 100, 500, 1)
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

  # Pack timestamp (seconds) and fill level into one 64-bit value for atomic CAS.
  # High 32 bits: timestamp, Low 32 bits: fill level
  @compile {:inline, pack: 2, unpack: 1}
  defp pack(timestamp, fill) do
    (timestamp &&& 0xFFFFFFFF) <<< 32 ||| (fill &&& 0xFFFFFFFF)
  end

  defp unpack(packed) do
    timestamp = packed >>> 32 &&& 0xFFFFFFFF
    fill = packed &&& 0xFFFFFFFF
    {timestamp, fill}
  end

  @doc """
  Checks if a key is allowed to perform an action, and increment the counter by the given amount.
  """
  @spec hit(
          table :: atom(),
          key :: term(),
          leak_rate :: pos_integer(),
          capacity :: pos_integer(),
          cost :: pos_integer()
        ) :: {:allow, non_neg_integer()} | {:deny, non_neg_integer()}
  def hit(table, key, leak_rate, capacity, cost) do
    now = System.system_time(:second)

    case :ets.lookup(table, key) do
      [{_, atomic}] ->
        do_hit(atomic, now, leak_rate, capacity, cost)

      [] ->
        atomic = :atomics.new(2, signed: false)

        if :ets.insert_new(table, {key, atomic}) do
          # Initialize with empty bucket at current time
          initial_packed = pack(now, 0)
          :atomics.put(atomic, 1, initial_packed)
          :atomics.put(atomic, 2, now)
        end

        hit(table, key, leak_rate, capacity, cost)
    end
  end

  defp do_hit(atomic, now, leak_rate, capacity, cost) do
    current_packed = :atomics.get(atomic, 1)
    {last_update, current_fill} = unpack(current_packed)

    leaked = trunc((now - last_update) * leak_rate)

    # Subtract leakage from current level (don't go below 0)
    current_fill = max(0, current_fill - leaked)

    if current_fill < capacity do
      final_level = current_fill + cost
      new_packed = pack(now, final_level)

      case :atomics.compare_exchange(atomic, 1, current_packed, new_packed) do
        :ok ->
          # Update slot 2 for cleanup tracking (non-critical, just for age-based cleanup)
          :atomics.put(atomic, 2, now)
          {:allow, final_level}

        _current_value ->
          # CAS failed, another process modified the value; retry
          do_hit(atomic, now, leak_rate, capacity, cost)
      end
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

      [{_, atomic}] ->
        packed = :atomics.get(atomic, 1)
        {_timestamp, fill} = unpack(packed)
        fill

      _ ->
        0
    end
  end
end
