# Tutorial


## Installation

Add Hammer as a dependency in `mix.exs`:

```elixir
def deps do
  [{:hammer, "~> 2.1.0"}]
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

- Configure the `:hammer` application
- Use the functions in the `Hammer` module

In this example, we will use the `ETS` backend, which stores data in an
in-memory ETS table.


## Configuring Hammer

The Hammer OTP application is configured the usual way, using `Mix.Config`.
Your project probably has a `config/config.exs` file, in which you should
configure Hammer, like so:

```elixir
config :hammer,
  backend: {Hammer.Backend.ETS,
            [expiry_ms: 60_000 * 60 * 4,
             cleanup_interval_ms: 60_000 * 10]}
```

The only configuration key (so far) is `:backend`, and its value is a tuple/pair
of the backend module name, and a backend-specific keyword list of configuration
options.

Because expiry of stale buckets is so essential to the smooth operation of a
rate-limiter, all backends will accept an `:expiry_ms` option, and many will
also accept `:cleanup_interval_ms`, depending on how expiry is implemented
internally.

(For example, Redis supports native data expiry, and so doesn't require
`:cleanup_interval_ms`.)

The `:expiry_ms` value should be configured to be longer than the life of the
longest bucket you will be using, as otherwise the bucket could be deleted while
it is still counting up hits for its time period.

The size of the backend worker pool can be tweaked with the `:pool_size` and
`:pool_max_overflow` options, (which are then supplied to `poolboy`). `:pool_size`
determines the size of the pool, and `:pool_max_overflow` determines how many extra
workers can be spawned when the system is under pressure. The default for both is `4`,
which will be fine for most systems.

Luckily, even if you don't configure `:hammer` at all, the application will
default to the ETS backend anyway, with some sensible defaults.


## The Hammer Module

Once the Hammer application is running (and it should just start automatically
when your system starts), All you need to do is use the various functions in the
`Hammer` module:

- `check_rate(id::string, scale_ms::integer, limit::integer)`
- `inspect_bucket(id::string, scale_ms::integer, limit::integer)`
- `delete_buckets(id::string)`
- `make_rate_checker(id_prefix, scale_ms, limit)`

The most interesting is `check_rate`, which checks if the rate-limit for the
given `id` has been exceeded in the specified time-`scale`.

Ideally, the `id` should be a combination of some action-specific, descriptive
prefix with some data which uniquely identifies the user or client performing
the action.

Example:

```elixir
# limit file uploads to 10 per minute per user
user_id = get_user_id_somehow()
case Hammer.check_rate("upload_file:#{user_id}", 60_000, 10) do
  {:allow, _count} ->
    # upload the file
  {:deny, _limit} ->
    # deny the request
end
```

## Switching to Redis

There may come a time when ETS just doesn't cut it, for example if we end up
load-balancing across many nodes and want to keep our rate-limiter state in one
central store. [Redis](https://redis.io) is ideal for this use-case, and
fortunately Hammer supports
a [Redis backend](https://github.com/ExHammer/hammer-backend-redis).

To change our application to use the Redis backend, we only need to install the
redis backend package, and change the `:backend` tuple that is used to configure
the `:hammer` application:

```elixir
# config :hammer,
#   backend: {Hammer.Backend.ETS, []}

config :hammer,
  backend: {Hammer.Backend.Redis, [expiry_ms: 60_000 * 60 * 2,
                                   redix_config: [host: "localhost",
                                                  port: 6379],
                                   pool_size: 4,
                                   pool_max_overflow: 2]}
```

Then it should all Just Work™.


## (Advanced) using multiple backends at the same time

Hammer can be configured to start multiple backends, which can then be referred
to separately when checking a rate-limit. In this example we configure both and
ETS backend under the key `:in_memory`, and a Redis backend under the key
`:redis`...

```elixir


config :hammer,
  backend: [
    in_memory: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60 * 2]},
    redis: {Hammer.Backend.Redis, [expiry_ms: 60_000 * 60 * 2,
                                    redix_config: [host: "localhost",
                                                    port: 6379]]}
  ]
```

We can then refer to these backends separately:

```elixir
Hammer.check_rate(:in_memory, "upload:#{user_id}", 60_000, 5)
Hammer.check_rate(:redis,     "upload:#{user_id}", 60_000, 5)
```

When using multiple backends the backend specifier key is mandatory, there is no
notion of a default backend.

Note: It's currently not possible to use multiple instances of the same backend
module, so it's not possible to have two separate Redis backends for example.
We'll probably remove this restriction at some point in the future.


## Further Reading

See the docs for the [Hammer](/hammer/Hammer.html) module for full documentation
on all the functions created by `use Hammer`.

See the [Creating Backends](/hammer/creatingbackends.html) for information on
creating new backends for Hammer.
