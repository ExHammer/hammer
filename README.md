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

## Default Algorithm

By default, Hammer uses a **fixed window counter** to track actions within set time windows, resetting the count at the start of each new window. For example, with a limit of 10 uploads per minute, a user could upload up to 10 files between 12:00:00 and 12:00:59, and up to 10 more between 12:01:00 and 12:01:59. Notice that the user can upload 20 videos in a second if the uploads are timed at the window edges. If this is an issue, it can be worked around with a "bursty" counter which can be implemented with the current API by making two checks, one for the original interval with the total limit, and one for a shorter interval with a fraction of the limit. That would smooth out the number of requests allowed.

## Core Concepts

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

## Available Backends

- [Hammer.ETS](https://hexdocs.pm/hammer/Hammer.ETS.html) (default, can be [distributed](./guides/distributed-ets.md))
- [Hammer.Redis](https://github.com/ExHammer/hammer-backend-redis)
- [Hammer.Mnesia](https://github.com/ExHammer/hammer-backend-mnesia)

## Acknowledgements

Hammer was originally inspired by the [ExRated](https://github.com/grempe/ex_rated) library, by [grempe](https://github.com/grempe).

## License

Copyright (c) 2023 June Kelly

This library is MIT licensed. See the [LICENSE](https://github.com/ExHammer/hammer/blob/master/LICENSE.md) for details.
