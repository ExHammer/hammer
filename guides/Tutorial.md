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

```console
$ mix deps.get
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
  use Hammer, backend: :ets
end
```

Here:
- `:backend` specifies the storage backend (`:ets` for in-memory storage, `Hammer.Redis` for Redis, etc.).

### Step 2: Start the Rate Limiter

Add the rate limiter to your application's supervision tree or start it manually by calling `MyApp.RateLimit.start_link/1` with any runtime options:

```elixir
MyApp.RateLimit.start_link(clean_period: :timer.minutes(1))
```

- `:clean_period` is an optional parameter for `:ets` backend that specifies how often to clean expired buckets in the ETS table.

## Using the Rate Limiter

With the rate limiter running, you can use `hit/3` or `hit/4` to enforce rate limits.

### Example: Basic Rate Limit Check

Suppose you want to limit file uploads to 10 per minute per user.

```elixir
user_id = 42
key = "upload_file:#{user_id}"
scale = :timer.minutes(1)
limit = 10

case MyApp.RateLimit.hit(key, scale, limit) do
  {:allow, _current_count} -> # proceed with file upload
  {:deny, _ms_until_next_window} -> # deny the request
end
```

### Customizing Rate Increments

If you want to specify a custom increment—useful when each action has a "cost"—you can use `hit/4`. Here's an example for a bulk upload scenario:

```elixir
user_id = 42
key = "upload_file:#{user_id}"
scale = :timer.minutes(1)
limit = 10
number_of_files = 3

case MyApp.RateLimit.hit(key, scale, limit, number_of_files) do
  {:allow, _current_count} -> # upload all files
  {:deny, _ms_until_next_window} -> # deny the request
end
```
## Using Hammer as a Plug in Phoenix

you can easily use Hammer as a plug by using the controller plug in Phoenix:

```elixir
plug :rate_limit_videos when action in ...

defp rate_limit_videos(conn, _opts) do
  user_id = conn.assigns.current_user.id
  key = "videos:#{user_id}"
  scale = :timer.minutes(1)
  limit = 10

  case MyApp.RateLimit.hit(key, scale, limit) do
    {:allow, _count} ->
      conn

    {:deny, retry_after} ->
      conn
      |> put_resp_header("retry-after", Integer.to_string(div(retry_after, 1000)))
      |> send_resp(429, [])
      |> halt()
  end
end
```

Or you could add it to your endpoint:

```elixir
defmodule MyAppWeb.Endpoint do
  use Phoenix.Endpoint

  plug RemoteIp
  plug :rate_limit

  # ...

  defp rate_limit(conn, _opts) do
    key = "web_requests:#{:inet.ntoa(conn.remote_ip)}"
    scale = :timer.minutes(1)
    limit = 1000

    case MyApp.RateLimit.hit(key, scale, limit) do
      {:allow, _count} ->
        conn

      {:deny, retry_after} ->
        retry_after_seconds = div(retry_after, 1000)

        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after_seconds))
        |> send_resp(429, [])
        |> halt()
    end
  end
end
```

## Using Hammer with Redis

To persist rate-limiting data across multiple nodes, you can use the Redis backend. Install the `Hammer.Redis` backend and update your rate limiter configuration:

```elixir
defmodule MyApp.RateLimit do
  use Hammer, backend: Hammer.Redis
end
```

Then, start the rate limiter pool with Redis configuration:

```elixir
MyApp.RateLimit.start_link(host: "redix.myapp.com")
```

Configuration options are the same as [Redix](https://hexdocs.pm/redix/Redix.html#start_link/1), except for `:name`, which comes from the module definition.
