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

  # The bucket is one 64-bit value, so that a hit is a single atomic CAS:
  #
  #   high 22 bits: low 22 bits of the millisecond clock
  #   low 42 bits:  level in thousandths of a token
  #
  # Thousandths make the refill exact: `elapsed_ms * refill_rate` is a whole
  # number of them, so nothing is rounded and no time is ever credited twice.
  # 42 bits hold any capacity up to 2^32 tokens.
  #
  # 22 bits of clock wrap every 70 minutes. Slot 2 holds the full millisecond
  # time of that clock, so a gap of any length can be measured: see `elapsed/3`.
  @clock_bits 22
  @clock_mask 0x3FFFFF
  @clock_half 0x200000
  @level_bits 42
  @level_mask 0x3FFFFFFFFFF
  # Below this, slot 2 cannot be a millisecond time (it would be 1974): it is
  # the whole seconds that 7.5.1 and earlier kept there.
  @legacy_stamp 0x2000000000
  @compile {:inline, pack: 2, unpack: 1}
  defp pack(clock, level) do
    (clock &&& @clock_mask) <<< @level_bits ||| (level &&& @level_mask)
  end

  defp unpack(packed) do
    {packed >>> (64 - @clock_bits), packed &&& @level_mask}
  end

  @doc """
  Checks if a key is allowed to perform an action, and consume the bucket by the given amount.

  On `{:deny, retry_after}`, `retry_after` is the time in milliseconds until the bucket
  holds enough tokens to pay `cost`. A `cost` larger than `capacity` is never allowed.
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
        :atomics.put(atomic, 1, pack(now, capacity * 1000))
        :atomics.put(atomic, 2, now)

        :ets.insert_new(table, {key, atomic})

        hit(table, key, refill_rate, capacity, cost)
    end
  end

  defp do_hit(atomic, now, refill_rate, capacity, cost) do
    # Slot 2 is read first: see `elapsed/3`.
    stamp = :atomics.get(atomic, 2)
    current_packed = :atomics.get(atomic, 1)
    {clock, level} = unpack(current_packed)

    elapsed = elapsed(now, clock, stamp)
    level = min(capacity * 1000, level + trunc(max(elapsed, 0) * refill_rate))
    price = cost * 1000

    if level >= price do
      final_level = level - price

      # All of `elapsed` was credited, so the clock moves to `now`. With no
      # time elapsed it stays put: the stored clock may be ahead of `now`, and
      # winding it back would credit that stretch a second time.
      new_clock = if elapsed > 0, do: now, else: clock
      new_packed = pack(new_clock, final_level)

      case :atomics.compare_exchange(atomic, 1, current_packed, new_packed) do
        :ok ->
          advance_stamp(atomic, now, elapsed)
          {:allow, div(final_level, 1000)}

        _current_value ->
          # CAS failed, another process modified the value; retry
          do_hit(atomic, now, refill_rate, capacity, cost)
      end
    else
      # Nothing refills until our time has caught up with a clock ahead of it.
      {:deny, retry_after(price - level, refill_rate, max(-elapsed, 0))}
    end
  end

  # Milliseconds since the bucket's clock; negative when that clock is ahead
  # of `now` (a concurrent hit read the time after us, or the wall clock
  # stepped back).
  #
  # The packed clock has only the low 22 bits of the time. Slot 2 holds the
  # full time of the same clock, so when the two agree the difference is exact
  # however long the bucket sat idle.
  #
  # They are two writes, the packed state first. When they disagree a hit has
  # moved the packed clock and not yet slot 2, so the packed clock is recent
  # and its 22 bits are enough: the difference is taken modulo 2^22 and read
  # as signed. Trusting slot 2 there would credit the whole idle period a
  # second time, on top of the refill already in the packed level.
  #
  # Slot 2 is read before the packed state for the same reason. Read the other
  # way round, a fresh slot 2 next to a stale packed clock looks like a hit in
  # flight and the stale clock would be taken for a recent one.
  #
  # What is left: a process killed between the two writes leaves them
  # disagreeing. If the bucket is then idle for 35 minutes or more, that one
  # gap is misread, as a shorter refill or as a clock ahead, until the next
  # hit that moves the clock.
  #
  # A bucket written by 7.5.1 or earlier has whole seconds in slot 2; it reads
  # as idle for decades and starts over full.
  defp elapsed(now, _clock, stamp) when stamp < @legacy_stamp, do: now - stamp
  defp elapsed(now, clock, stamp) when (stamp &&& @clock_mask) == clock, do: now - stamp

  defp elapsed(now, clock, _lagging_stamp) do
    case now - clock &&& @clock_mask do
      elapsed when elapsed < @clock_half -> elapsed
      behind -> behind - (@clock_mask + 1)
    end
  end

  # Follow a packed clock that moved (it does not when no time elapsed). Slot
  # 2 only moves forward, so overlapping hits finishing out of order leave it
  # at the latest clock, which is the one the packed state holds.
  defp advance_stamp(atomic, now, elapsed) when elapsed > 0 do
    stamp = :atomics.get(atomic, 2)

    if stamp < now and :atomics.compare_exchange(atomic, 2, stamp, now) != :ok do
      advance_stamp(atomic, now, elapsed)
    end
  end

  defp advance_stamp(_atomic, _now, _elapsed), do: nil

  # Milliseconds until the bucket has gained `deficit` more thousandths of a
  # token, rounded up so that sleeping it is sufficient for any cost the
  # bucket can hold. `ahead` is the time before the refill starts at all.
  #
  # A rate of 0 never gets there. There is no honest wait to report, so keep
  # the flat second this bucket always answered with.
  defp retry_after(deficit, rate, ahead) when rate > 0 do
    ahead + max(ceil(deficit / rate), 1)
  end

  defp retry_after(_deficit, _rate, _ahead), do: 1000

  @doc """
  Returns the current level of the bucket for a given key.
  """
  @spec get(table :: atom(), key :: term()) :: non_neg_integer()
  def get(table, key) do
    case :ets.lookup(table, key) do
      [{_, atomic}] ->
        {_clock, level} = unpack(:atomics.get(atomic, 1))
        div(level, 1000)

      _ ->
        0
    end
  end

  @doc false
  @spec normalize_entry(key :: term(), atomic :: reference()) :: map()
  def normalize_entry(key, atomic) do
    {_clock, level} = unpack(:atomics.get(atomic, 1))
    %{key: key, value: div(level, 1000), expired_at: :atomics.get(atomic, 2)}
  end
end
