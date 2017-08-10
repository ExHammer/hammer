# Hammer

A rate-limiter for Elixir, with pluggable storage backends.


[![Build Status](https://travis-ci.org/ExHammer/hammer.svg?branch=master)](https://travis-ci.org/ExHammer/hammer)

[![Coverage Status](https://coveralls.io/repos/github/ExHammer/hammer/badge.svg?branch=master)](https://coveralls.io/github/ExHammer/hammer?branch=master)

## Installation

Hammer is [available in Hex](https://hex.pm/packages/hammer), the package can be installed
by adding `hammer` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:hammer, "~> 0.2.0"}]
end
```


## Documentation

On hexdocs: [https://hexdocs.pm/hammer/frontpage.html](https://hexdocs.pm/hammer/frontpage.html)

The [Tutorial](https://hexdocs.pm/hammer/tutorial.html) is an especially good place to start.

## Usage

To use Hammer, you need to do two things:

- Start a backend process
- `use` the `Hammer` module

The example below combines both in a `MyApp.RateLimiter` module:

```elixir

defmodule MyApp.RateLimiter do
  use Supervisor
  use Hammer, backend: Hammer.Backend.ETS

  def start_link() do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    children = [
      worker(Hammer.Backend.ETS, [[expiry_ms: 1000 * 60 * 60
                                   cleanup_interval_ms: 1000 * 60 * 10]]),
    ]
    supervise(children, strategy: :one_for_one, name: MyApp.RateLimiter)
  end
end
```

The `Hammer` module provides the following functions (via `use`):

- `check_rate(id, scale_ms, limit)`
- `inspect_bucket(id, scale_ms, limit)`
- `delete_buckets(id)`

The rate-limiter is then used in the app by calling the `check_rate` function:


```elixir

defmodule MyApp.VideoUpload do

  alias MyApp.RateLimiter

  def upload(video_data, user_id) do
    case RateLimiter.check_rate("upload_video:#{user_id}", 60_000, 5) do
      {:allow, _count} ->
        # upload the video, somehow
      {:deny, _limit} ->
        # deny the request
    end
  end

end

```

See the [Tutorial](doc_src/Tutorial.md) for more.

See the [Hammer Testbed](https://github.com/ExHammer/hammer-testbed) app for an example of
using Hammer in a Phoenix application.


## Available Backends

- Hammer.Backend.ETS (provided with Hammer)
- [Hammer.Backend.Redis](https://github.com/ExHammer/hammer-backend-redis)
