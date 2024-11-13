# Hammer

<img src="assets/horizontal.svg" alt="hammer" height="150px">

[![Build Status](https://github.com/ExHammer/hammer/actions/workflows/ci.yml/badge.svg)](https://github.com/ExHammer/hammer/actions/workflows/ci.yml) [![Hex.pm](https://img.shields.io/hexpm/v/hammer.svg)](https://hex.pm/packages/hammer) [![Documentation](https://img.shields.io/badge/documentation-gray)](https://hexdocs.pm/hammer)
[![Total Download](https://img.shields.io/hexpm/dt/hammer.svg)](https://hex.pm/packages/hammer)
[![License](https://img.shields.io/hexpm/l/hammer.svg)](https://github.com/ExHammer/hammer/blob/master/LICENSE.md)

A rate-limiter for Elixir, with pluggable storage backends.

## Hammer-Plug

We have a helper-library to make adding rate-limiting to your Phoenix
(or other plug-based) application even easier: [Hammer.Plug](https://github.com/ExHammer/hammer-plug).

## Installation

Hammer is [available in Hex](https://hex.pm/packages/hammer), the package can be installed
by adding `:hammer` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:hammer, "~> 6.1"}
  ]
end
```

## Documentation

On HexDocs: [https://hexdocs.pm/hammer/frontpage.html](https://hexdocs.pm/hammer/frontpage.html)

The [Tutorial](https://hexdocs.pm/hammer/tutorial.html) is an especially good place to start.

## Usage

Example:

```elixir
defmodule MyApp.VideoUpload do

  def upload(video_data, user_id) do
    case Hammer.check_rate("upload_video:#{user_id}", 60_000, 5) do
      {:allow, _count} ->
        # upload the video, somehow
      {:deny, _limit} ->
        # deny the request
    end
  end

end
```

The `Hammer` module provides the following functions:

- `check_rate(id, scale_ms, limit)`
- `check_rate_inc(id, scale_ms, limit, increment)`
- `inspect_bucket(id, scale_ms, limit)`
- `delete_buckets(id)`

Backends are configured via `Mix.Config`:

```elixir
config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60 * 4,
                                 cleanup_interval_ms: 60_000 * 10]}
```

See the [Tutorial](https://hexdocs.pm/hammer/tutorial.html) for more.

See the [Hammer Testbed](https://github.com/ExHammer/hammer-testbed) app for an example of
using Hammer in a Phoenix application.

## Available Backends

- [Hammer.Backend.ETS](https://hexdocs.pm/hammer/Hammer.Backend.ETS.html) (provided with Hammer for testing and dev purposes, not very good for production use)
- [Hammer.Backend.Redis](https://github.com/ExHammer/hammer-backend-redis)
- [Hammer.Backend.Mnesia](https://github.com/ExHammer/hammer-backend-mnesia) (beta)

## Getting Help

If you're having trouble, either open an issue on this repo
## Acknowledgements

Hammer was inspired by the [ExRated](https://github.com/grempe/ex_rated) library, by [grempe](https://github.com/grempe).

## License

Copyright (c) 2023 June Kelly

This library is MIT licensed. See the [LICENSE](https://github.com/ExHammer/hammer/blob/master/LICENSE.md) for details.
