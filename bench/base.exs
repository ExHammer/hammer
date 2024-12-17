# MIX_ENV=bench LIMIT=1 SCALE=5000 RANGE=10000 PARALLEL=500 mix run bench/basic.exs
# inspired from https://github.com/PragTob/rate_limit/blob/master/bench/basic.exs
profile? = !!System.get_env("PROFILE")
parallel = String.to_integer(System.get_env("PARALLEL", "1"))
limit = String.to_integer(System.get_env("LIMIT", "1000000"))
scale = String.to_integer(System.get_env("SCALE", "60000"))
range = String.to_integer(System.get_env("RANGE", "1_000"))

IO.puts("""
parallel: #{parallel}
limit: #{limit}
scale: #{scale}
range: #{range}
""")

# TODO: clean up ETS table before/after each scenario
defmodule ETSFixWindowRateLimiter do
  use Hammer, backend: :ets, algorithm: :fix_window
end

defmodule ETSSlidingWindowRateLimiter do
  use Hammer, backend: :ets, algorithm: :sliding_window
end

defmodule ETSLeakyBucketRateLimiter do
  use Hammer, backend: :ets, algorithm: :leaky_bucket
end

defmodule ETSTokenBucketRateLimiter do
  use Hammer, backend: :ets, algorithm: :token_bucket
end

defmodule AtomicFixWindowRateLimiter do
  use Hammer, backend: :atomic, algorithm: :fix_window
end

defmodule AtomicTokenBucketRateLimiter do
  use Hammer, backend: :atomic, algorithm: :token_bucket
end

defmodule AtomicLeakyBucketRateLimiter do
  use Hammer, backend: :atomic, algorithm: :leaky_bucket
end

PlugAttack.Storage.Ets.start_link(:plug_attack_sites, clean_period: :timer.minutes(10))

ETSFixWindowRateLimiter.start_link(clean_period: :timer.minutes(10))
ETSSlidingWindowRateLimiter.start_link(clean_period: :timer.minutes(10))
ETSTokenBucketRateLimiter.start_link(clean_period: :timer.minutes(10))
ETSLeakyBucketRateLimiter.start_link(clean_period: :timer.minutes(10))
AtomicFixWindowRateLimiter.start_link(clean_period: :timer.minutes(10))
AtomicTokenBucketRateLimiter.start_link(clean_period: :timer.minutes(10))
AtomicLeakyBucketRateLimiter.start_link(clean_period: :timer.minutes(10))

Benchee.run(
  %{
    "hammer_sliding_window" => fn key -> ETSSlidingWindowRateLimiter.hit("sites:#{key}", scale, limit) end,
    "hammer_fix_window" => fn key -> ETSFixWindowRateLimiter.hit("sites:#{key}", scale, limit) end,
    "hammer_leaky_bucket" => fn key -> ETSLeakyBucketRateLimiter.hit("sites:#{key}", scale, limit) end,
    "hammer_token_bucket" => fn key -> ETSTokenBucketRateLimiter.hit("sites:#{key}", scale, limit) end,
    "hammer_atomic_fix_window" => fn key -> AtomicFixWindowRateLimiter.hit("sites:#{key}", scale, limit) end,
    "hammer_atomic_token_bucket" => fn key -> AtomicTokenBucketRateLimiter.hit("sites:#{key}", scale, limit) end,
    "hammer_atomic_leaky_bucket" => fn key -> AtomicLeakyBucketRateLimiter.hit("sites:#{key}", scale, limit) end,
    "plug_attack" => fn key ->
      PlugAttack.Rule.throttle(_key = key,
        storage: {PlugAttack.Storage.Ets, :plug_attack_sites},
        limit: limit,
        period: scale
      )
    end,
    "ex_rated" => fn key -> ExRated.check_rate("sites:#{key}", scale, limit) end,
    "rate_limiter" => fn key ->
      key = "sites:#{key}"
      rate_limiter = RateLimiter.get(key) || RateLimiter.new(key, scale, limit)
      RateLimiter.hit(rate_limiter)
    end
  },
  formatters: [{Benchee.Formatters.Console, extended_statistics: true}],
  before_each: fn _ -> :rand.uniform(range) end,
  print: [fast_warning: false],
  time: 6,
  # fill the table with some data
  warmup: 14,
  profile_after: profile?,
  parallel: parallel
)
