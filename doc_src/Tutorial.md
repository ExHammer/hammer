# Tutorial


## Installation

Add Hammer as a dependency in `mix.exs`:

```elixir
def deps do
  [{:hammer, "~> 0.1.0"}]
end
```


## Core Concepts

When we want to rate-limit some action, we want to ensure that the number of
actions permitted is limited within a specified time-period. For example, a
maximum of five times within on minute. Usually the limit is enforced per-user,
per-client, or per some other unique-ish value, such as IP address. It's much
rarer, but not unheard-of, to limit the action globally without taking the
identity of the user or client into account.

In the Hammer API, the maximum number of actions is the `limit`, and the
timespan (in milliseconds) is the `scale_ms`. The combination of the name of the
action with some unique identifier is the `id`.

Hammer uses a [Token Bucket](https://en.wikipedia.org/wiki/Token_bucket)
algorithm to count the number of actions occurring in a "bucket". If the count
within the bucket is lower than the limit, then the action is allowed, otherwise
it is denied.


## Usage

To use Hammer, you need to do two things:

- Start a backend process
- `use` the `Hammer` module

In this example, we will use the `ETS` backend, which stores data in an
in-memory ETS table.


## Starting a Backend Process

Hammer backends are typically implemented as OTP GenServer modules. You just
need to start the process as part of your application's OTP supervision tree.

By convention, the Backend `start_link` functions accept a Keyword list of
configuration options, at the minimum `expiry_ms` and `cleanup_interval_ms`.
Each backends may require additional, more specific configuration, such as
details of how to connect to a database.

Because the number of buckets stored will continue to grow while your
application is running it is essental to clean up old buckets regularly. The
`expiry_ms` option determines how long an individual "bucket" should be kept in
storage before being cleaned up (deleted), while `cleanup_interval_ms`
determines the time between cleanup runs.

Starting the `Hammer.Backend.ETS` process as a worker might look like this:

```elixir
  worker(Hammer.Backend.ETS, [[expiry_ms: 1000 * 60 * 60,
                               cleanup_rate_ms: 1000 * 60 * 10]]),
```


## `use`-ing The Hammer Module

To bring the functions of the `Hammer` module into scope, use the `use` macro (ahem),
and specify the `:backend` module which should be used.


```elixir
use Hammer, backend: Hammer.Backend.ETS
```

This will create four functions, all configured to use the specified backend:

- `check_rate(id::string, scale_ms::integer, limit::integer)`
- `inspect_bucket(id::string, scale_ms::integer, limit::integer)`
- `delete_buckets(id::string)`
- `make_rate_checker(id_prefix, scale_ms, limit)`

The most interesting is `check_rate`, which checks if the rate-limit for the given `id`
has been exceeded in the specified time-`scale`.

Ideally, the `id` should be a combination of some action-specific, descriptive prefix
with some data which uniquely identifies the user or client performing the action.

Example:

```elixir
# limit file uploads to 10 per minute per user
user_id = get_user_id_somehow()
case check_rate("upload_file:#{user_id}", 60_000, 10) do
  {:allow, _count} ->
    # upload the file, somehow
  {:deny, _limit} ->
    # deny the request
end
```


## A Realistic Example

The example below shows a `MyApp.RateLimiter` module, which acts as both a Supervisor to the
`Hammer.Backend.ETS` process, and contains the rate-limiting API via `use Hammer...`

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

Of course, the `MyApp.RateLimiter` supervisor should be added to the application's
supervision tree like so:

```elixir
# probably somewhere in application.ex

  children = [
    ...
    supervisor(HammerTestbed.RateLimiter, [])
    ...
  ]
```


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

## Switching to Redis

There may come a time when ETS just doesn't cut it, for example if we end up load-balancing across many nodes and want to keep our rate-limiter state in one central store. [Redis](https://redis.io) is ideal for this use-case, and fortunately Hammer supports a [Redis backend](https://github.com/ExHammer/hammer-backend-redis).

To change our application to use the Redis backend, we need to do the following:

- Install and set up Redis (excercise for the reader)
- Add the `hammer_backend_redis` dependency
- Start the `Hammer.Backend.Redis` process
- Change the backend it the `use Hammer` macro

Here we go...

Add `hammer_backend_redis` to your mix dependencies:

```elixir
defp deps do
  [
    ...
    {:hammer, "~> 1.0.0"},
    {:hammer_backend_redis, "~> 1.0.0"},
    ...
  ]
end
```

Change the `MyApp.RateLimiter` module to use the `Hammer.Backend.Redis` instead of `Hammer.Backend.ETS`:

```elixir
defmodule MyApp.RateLimiter do
  use Supervisor
  use Hammer, backend: Hammer.Backend.Redis

  def start_link() do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    children = [
      worker(Hammer.Backend.Redis, [[expiry_ms: 1000 * 60 * 60
                                     redix_config: [host: "localhost"]]]),
    ]
    supervise(children, strategy: :one_for_one, name: MyApp.RateLimiter)
  end
end
```

## Further Reading

See the docs for the [Hammer](/hammer/Hammer.html) module for full documentation on all the
functions created by `use Hammer`.

See the [Creating Backends](/hammer/creatingbackends.html) for information on creating new backends
for Hammer.
