# Hammer

[![Build Status](https://github.com/ExHammer/hammer/actions/workflows/ci.yml/badge.svg)](https://github.com/ExHammer/hammer/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/hammer.svg)](https://hex.pm/packages/hammer)
[![Documentation](https://img.shields.io/badge/documentation-gray)](https://hexdocs.pm/hammer)
[![Total Download](https://img.shields.io/hexpm/dt/hammer.svg)](https://hex.pm/packages/hammer)
[![License](https://img.shields.io/hexpm/l/hammer.svg)](https://github.com/ExHammer/hammer/blob/master/LICENSE.md)

**Hammer** is a rate-limiter for Elixir with pluggable storage backends. Hammer enables users to set limits on actions performed within specified time intervals, applying per-user or global limits on API requests, file uploads, and more.

---

> [!NOTE]
>
> This README is for the unreleased master branch, please reference the [official documentation on hexdocs](https://hexdocs.pm/hammer) for the latest stable release.

---

## Installation

Hammer is [available in Hex](https://hex.pm/packages/hammer). Install by adding `:hammer` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:hammer, "~> 7.0"}
  ]
end
```

## Available Backends

Atomic backends are single-node rate limiting but will be the fastest option.

- [Hammer.ETS](https://hexdocs.pm/hammer/Hammer.ETS.html) (default, can be [distributed](./guides/distributed-ets.md))
- [Hammer.Atomic](https://hexdocs.pm/hammer/Hammer.Atomic.html)
- [Hammer.Redis](https://github.com/ExHammer/hammer-backend-redis)
- [Hammer.Mnesia](https://github.com/ExHammer/hammer-backend-mnesia)

## Available Algorithms:

Each backend supports multiple algorithms. Not all of them are available for all backends. The following table shows which algorithms are available for which backends.

| Algorithm | Backend |
| --------- | ------- |
| [Hammer.Atomic.FixWindow](https://hexdocs.pm/hammer/Hammer.Atomic.FixWindow.html) | [Hammer.Atomic](https://hexdocs.pm/hammer/Hammer.Atomic.html) |
| [Hammer.Atomic.LeakyBucket](https://hexdocs.pm/hammer/Hammer.Atomic.LeakyBucket.html) | [Hammer.Atomic](https://hexdocs.pm/hammer/Hammer.Atomic.html) |
| [Hammer.Atomic.TokenBucket](https://hexdocs.pm/hammer/Hammer.Atomic.TokenBucket.html) | [Hammer.Atomic](https://hexdocs.pm/hammer/Hammer.Atomic.html) |
| [Hammer.ETS.FixWindow](https://hexdocs.pm/hammer/Hammer.ETS.FixWindow.html) | [Hammer.ETS](https://hexdocs.pm/hammer/Hammer.ETS.html) |
| [Hammer.ETS.LeakyBucket](https://hexdocs.pm/hammer/Hammer.ETS.LeakyBucket.html) | [Hammer.ETS](https://hexdocs.pm/hammer/Hammer.ETS.html) |
| [Hammer.ETS.TokenBucket](https://hexdocs.pm/hammer/Hammer.ETS.TokenBucket.html) | [Hammer.ETS](https://hexdocs.pm/hammer/Hammer.ETS.html) |
| [Hammer.ETS.SlidingWindow](https://hexdocs.pm/hammer/Hammer.ETS.SlidingWindow.html) | [Hammer.Redis](https://hexdocs.pm/hammer/Hammer.ETS.html) |
| [Hammer.Redis.FixedWindow](https://hexdocs.pm/hammer/Hammer.Redis.FixedWindow.html) | [Hammer.Redis](https://hexdocs.pm/hammer/Hammer.Redis.html) |

## Default Algorithm

By default, Hammer backends use the **fixed window counter** to track actions within set time windows, resetting the count at the start of each new window. For example, with a limit of 10 uploads per minute, a user could upload up to 10 files between 12:00:00 and 12:00:59, and up to 10 more between 12:01:00 and 12:01:59. Notice that the user can upload 20 videos in a second if the uploads are timed at the window edges. If this is an issue, it can be worked around with a "bursty" counter which can be implemented with the current API by making two checks, one for the original interval with the total limit, and one for a shorter interval with a fraction of the limit. That would smooth out the number of requests allowed.

## Algorithm Comparison

Here's a comparison of the different rate limiting algorithms to help you choose:

### [Fixed Window](https://hexdocs.pm/hammer/Hammer.Atomic.FixWindow.html)
- Simplest implementation with lowest overhead
- Good for basic rate limiting with clear time boundaries
- Potential edge case: Up to 2x requests possible at window boundaries
- Best for: Basic API limits where occasional bursts are acceptable

### [Leaky Bucket](https://hexdocs.pm/hammer/Hammer.Atomic.LeakyBucket.html)
- Provides smooth, consistent request rate
- Requests "leak" out at constant rate
- Good for traffic shaping and steady throughput
- Best for: Network traffic control, queue processing

### [Token Bucket](https://hexdocs.pm/hammer/Hammer.Atomic.TokenBucket.html)
- Allows controlled bursts while maintaining average rate
- Tokens regenerate at fixed rate
- More flexible than fixed windows
- Best for: APIs needing burst tolerance, gaming mechanics

### [Sliding Window](https://hexdocs.pm/hammer/Hammer.ETS.SlidingWindow.html)
- Most precise rate limiting
- No boundary conditions like fixed windows
- Higher overhead than other algorithms
- Best for: Strict rate enforcement, critical systems

Selection Guide:
- Need simple implementation? → Fixed Window
- Need smooth output rate? → Leaky Bucket
- Need burst tolerance? → Token Bucket
- Need precise limits? → Sliding Window

## Creating a Rate Limiter

- **Limit:** Maximum number of actions allowed in a window.
- **Scale:** Duration of the time window (in milliseconds).
- **Key:** Unique identifier (e.g., user ID) to scope the rate limiting.

## Example Usage

```elixir
defmodule MyApp.RateLimit do
  use Hammer, backend: :ets
end

MyApp.RateLimit.start_link()

user_id = 42
key = "upload_video:#{user_id}"
scale = :timer.minutes(1)
limit = 3

case MyApp.RateLimit.hit(key, scale, limit) do
  {:allow, _count} ->
    # upload the video
    :ok

  {:deny, retry_after} ->
    # deny the request
    {:error, :rate_limit, _message = "try again in #{retry_after}ms"}
end
```

## Benchmarks

See the [BENCHMARKS.md](https://github.com/ExHammer/hammer/blob/master/BENCHMARKS.md) for more details.

## Acknowledgements

Hammer was originally inspired by the [ExRated](https://github.com/grempe/ex_rated) library, by [grempe](https://github.com/grempe).

## License

Copyright (c) 2023 June Kelly
Copyright (c) 2023-2024 See [CONTRIBUTORS.md](https://github.com/ExHammer/hammer/blob/master/CONTRIBUTORS.md)

This library is MIT licensed. See the [LICENSE](https://github.com/ExHammer/hammer/blob/master/LICENSE.md) for details.
