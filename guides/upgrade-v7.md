# Upgrading to Hammer V7

## Elixir and Erlang/OTP Compatibility

* Hammer v7 requires Elixir 1.14 and Erlang/OTP 25 at a minimum.
* We recommend using the latest Elixir and Erlang/OTP versions.

## Changes to your Project

* Update your `mix.exs` to depend on version `7.0.0` of Hammer.

```elixir
def deps do
  [
    ...
    {:hammer, "~> 7.0.0"}
    ...
    ]
end
```

## Define a Rate Limiter

First, define a rate limiter module in your application. Use the `Hammer` module with your chosen backend and configure options as needed:

```elixir
defmodule MyApp.RateLimit do
  use Hammer, backend: :ets
end
```

This would setup the rate limiter using the `Hammer.ETS` backend. See the [Tutorial](./Tutorial.md) guide for more information on other backends.

## Update your Application Supervisor

* Pick up the value in your config file for `cleanup_interval_ms`.
* remove the `config` lines for `Hammer` as they are no longer needed in all of the `config/*.exs` files.
* In your `application.ex` file, add the following line to start the rate limiter:

```elixir
def start(_type, _args) do

  children = [
    ...
    {MyApp.RateLimit, [clean_period: 60_000]}
    ...
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

## Change to Backend Configuration

We have simplified the backend API. `Hammer.inc/4` combines the functionality of `Hammer.check_rate` and `Hammer.check_rate_inc` now.

* Remapped all the  `Hammer.check_rate/3` and  `Hammer.check_rate/4` to `Hammer.inc/4`.
* Remapped all the  `Hammer.check_rate_inc/4` and  `Hammer.check_rate_inc/5` to `Hammer.inc/4`.
* for the `Hammer.delete_buckets`, you need to remove them as there no true replacement. You could potentially use `Hammer.ETS.set/1` to reset specific key
* for the `Hammer.make_rate_checker`, you need to remove them as there no replacement.

## Changes to the Hammer.Plug

* The `Hammer.Plug` has been removed. Remove any references to it in your code.
* Migrate it by using regular Phoenix plugs in either a controller plug or an endpoint plug. See the [Tutorial](./Tutorial.md) guide for some examples.
