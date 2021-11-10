<p align="center"><img src="logo/horizontal.png" alt="hammer" height="150px"></p>

# Hammer

A fork of [ExHammer/hammer](https://github.com/ExHammer/hammer) altered to
focus purely on using a Redis backend.


## Installation

This fork of Hammer is currently only available on github.
The package can be installed by adding `hammer` to your list of dependencies
along with the github url in `mix.exs`:

```elixir
def deps do
  [{:hammer, github: "turnhub/hammer"}]
end
```


## Documentation

The core API of Hammer remains unchanged, so the official documentation can be
referenced for most functions.

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

The Redis backend is configured via `Mix.Config` using a Redis URL:

```elixir
config :hammer,
  redis_url: "redis://localhost:6379/1?expiry_ms=7200000&pool_size=4&pool_max_overflow=0"
```


## Getting Help

If you're having trouble, open an issue on this repo
