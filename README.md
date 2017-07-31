# Hammer

A rate-limiter for Elixir, with pluggable storage backends.


## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `hammer` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:hammer, "~> 0.1.0"}]
end
```

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
