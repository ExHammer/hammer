# Hammer

A rate-limiter for Elixir, with pluggable storage backends.

*Currently worse-than-alpha quality, do not use in production*.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `hammer` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:hammer, "~> 0.1.0"}]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/hammer](https://hexdocs.pm/hammer).


## Usage

Example:

```elixir

defmodule MyApp.RateLimiter do
  use Supervisor

  def start_link() do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    children = [
      worker(Hammer.Backend.ETS, []),
      worker(Hammer, [[backend: Hammer.Backend.ETS]])
    ]
    supervise(children, strategy: :one_for_one, name: MyApp.RateLimiter)
  end
end

defmodule MyApp.VideoUpload do

  ...

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

See the [Hammer Testbed](https://github.com/ExHammer/hammer-testbed) app for an example of
using Hammer in a Phoenix application.



## Available Backends



## Writing a Backend


The backend api is as follows:


### setup(config)

This function is called whenever the Hammer process is initialized.
Use this as a hook to do any necessary setup.

Config is a map, containing relevant config vars that were used to start Hammer.

Config:
- `expiry`: expiry time in milliseconds

Expiry is useful if the backing data store supports automatic expiry, in which
case the `prune_expired_buckets` function can be a no-op.

Returns: The atom `:ok` or tuple of `{:error, reason}`


### count_hit(key, timestamp)

- `key`: The key of the current bucket
- `timestamp`: The current timestamp (integer)

Returns: Either a Tuple of `{:ok, count}` where count is the current count of the bucket,
or `{:error, reason}`.


### get_bucket(key)

- `key`: The key of the current bucket

Returns: Either a tuple of `{:ok, bucket}`, where `bucket` is a tuple of
`{key, count, created_at, updated_at}`, key is, as usual, a tuple of `{bucket_number, id}`,
`count` is the count of hits in the bucket, `created_at` and `updated_at` are integer timestamps,
or `{:error, reason}`


### delete_buckets(id)

- `id`: rate-limit id to delete

Returns: Either `{:ok, count}`, or `{:error, reason}`


### prune_expired_buckets(timestamp)

- `timestamp`: current timestamp (integer)

Returns: Either `:ok`, or `{:error, reason}`
