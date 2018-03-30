# Hammer, a Rate-Limiter for Elixir

Hammer is a rate-limiter for the [Elixir](https://elixir-lang.org/) language.
It's killer feature is a pluggable backend system, allowing you to use whichever
storage suits your needs. Currently, backends for ETS and
[Redis](https://github.com/ExHammer/hammer-backend-redis) are available.


```elixir
    case Hammer.check_rate("file_upload:#{user_id}", 60_000, 10) do
      {:allow, _count} ->
        # ...
      {:deny, _limit} ->
        # ...
    end
```

To get started with Hammer, read the [Tutorial](/hammer/tutorial.html).

A primary goal of the Hammer project is to make it easy to implement new storage
backends. See the [documentation on creating
backends](/hammer/creatingbackends.html) for more details.
