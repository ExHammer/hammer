# Tutorial

Hammer is a rate limiting library for Elixir that can help you control the frequency of specific actions in your application, such as limiting API requests, login attempts, or file uploads. This tutorial will guide you through setting up Hammer, defining a rate limiter, and applying rate limiting in your app.

## Installation

Add Hammer as a dependency in `mix.exs`:

```elixir
def deps do
  [{:hammer, "~> 7.0.0"}]
end
```

Then, run:

```sh
mix deps.get
```

## Core Concepts

When rate-limiting an action, you specify a maximum number of allowed occurrences (the limit) within a certain time frame (the scale). For example, you might allow only 5 login attempts per minute for each user. The limit is typically enforced based on a unique identifier (like a user ID or IP address) but can also be applied globally.

In Hammer:
- `limit` is the maximum number of actions permitted.
- `scale` is the time period (in milliseconds) for that limit.
- `key` is a unique identifier for the rate limit, combining the action name with a user identifier (like "login_attempt:42" for user 42) is a common approach.

Hammer uses a fixed window counter approach. It divides time into fixed-size windows of `scale` size and counts the number of requests in each window, blocking any requests that exceed the `limit`.

## Usage

To use Hammer, you need to:

- Define a rate limiter module.
- Add the Hammer backend to your application's supervision tree.

In this example, we'll use the Hammer.ETS backend, which stores data in an in-memory ETS table.

### Step 1: Define a Rate Limiter

First, define a rate limiter module in your application. Use the `Hammer` module with your chosen backend and configure options as needed:

```elixir
defmodule MyApp.RateLimit do
  # Specify the backend and table for ETS storage
  use Hammer, backend: :ets, table: __MODULE__
end
```

Here:
- `:backend` specifies the storage backend (`:ets` for in-memory storage, `Hammer.Redis` for Redis, etc.).
- `:table` is the ETS table name to create and use (default is `__MODULE__` so it can be ommited).

### Step 2: Start the Rate Limiter

Add the rate limiter to your application's supervision tree or start it manually by calling `MyApp.RateLimit.start_link/1` with any runtime options:

```elixir
MyApp.RateLimit.start_link(clean_period: :timer.minutes(1))
```

- `:clean_period` is an optional parameter for `:ets` backend that specifies how often to clean expired buckets in the ETS table.

## Using the Rate Limiter

With the rate limiter running, you can use `check_rate/3` or `check_rate/4` to enforce rate limits.

### Example: Basic Rate Limit Check

Suppose you want to limit file uploads to 10 per minute per user. Here's how you could use `check_rate/3`:

```elixir
user_id = 42
key = "upload_file:#{user_id}"
scale = :timer.minutes(1)
limit = 10

case MyApp.RateLimit.check_rate(key, scale, limit) do
  {:allow, _count} -> # proceed with file upload
  {:deny, _limit} -> # deny the request
end
```

### Customizing Rate Increments

If you want to specify a custom increment—useful when each action has a "cost"—you can use `check_rate/4`. Here's an example for a bulk upload scenario:

```elixir
user_id = 42
key = "upload_file:#{user_id}"
scale = :timer.minutes(1)
limit = 10
number_of_files = 3

case MyApp.RateLimit.check_rate(key, scale, limit, number_of_files) do
  {:allow, _count} -> # upload all files
  {:deny, _limit} -> # deny the request
end
```

## Using Hammer with Redis

To persist rate-limiting data across multiple nodes, you can use the Redis backend. Install the `Hammer.Redis` backend and update your rate limiter configuration:

```elixir
defmodule MyApp.RateLimit do
  use Hammer, backend: Hammer.Redis, name: __MODULE__
end
```

Then, start the rate limiter with Redis configuration:

```elixir
MyApp.RateLimit.start_link(host: "redix.myapp.com")
```

Configuration options are the same as [Redix](https://hexdocs.pm/redix/Redix.html#start_link/1), except for `:name`, which comes from the module definition.
