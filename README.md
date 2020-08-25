<p align="center"><img src="logo/horizontal.png" alt="hammer" height="150px"></p>

# Hammer

A rate-limiter for Elixir, with pluggable storage backends.

[![Build Status](https://travis-ci.org/ExHammer/hammer.svg?branch=master)](https://travis-ci.org/ExHammer/hammer)

[![Coverage Status](https://coveralls.io/repos/github/ExHammer/hammer/badge.svg?branch=master)](https://coveralls.io/github/ExHammer/hammer?branch=master)


## New! Hammer-Plug

We've just released a new helper-library to make adding rate-limiting to your Phoenix
(or other plug-based) application even easier: [Hammer.Plug](https://github.com/ExHammer/hammer-plug).



## Installation

Hammer is [available in Hex](https://hex.pm/packages/hammer), the package can be installed
by adding `hammer` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:hammer, "~> 6.0"}]
end
```


## Documentation

On hexdocs: [https://hexdocs.pm/hammer/frontpage.html](https://hexdocs.pm/hammer/frontpage.html)

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

You can specify runtime config via an mfa function

config :hammer,
  backend: {MyApp.Hammer, :config, []}

defmodule MyApp.Hammer do
  def config() do
    {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60 * 4,
                          cleanup_interval_ms: 60_000 * 10]}
  end
end


See the [Tutorial](https://hexdocs.pm/hammer/tutorial.html) for more.

See the [Hammer Testbed](https://github.com/ExHammer/hammer-testbed) app for an example of
using Hammer in a Phoenix application.


## Available Backends

- Hammer.Backend.ETS (provided with Hammer for testing and dev purposes, not very good for production use)
- [Hammer.Backend.Redis](https://github.com/ExHammer/hammer-backend-redis)
- [Hammer.Backend.Mnesia](https://github.com/ExHammer/hammer-backend-mnesia) (beta)

## Getting Help

If you're having trouble, either open an issue on this repo, or reach out to the maintainers ([@shanekilkelly](https://twitter.com/shanekilkelly)) on Twitter.


## Acknowledgements

Hammer was inspired by the [ExRated](https://github.com/grempe/ex_rated) library, by [grempe](https://github.com/grempe).
