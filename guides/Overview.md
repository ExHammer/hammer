# Overview

Hammer is a rate-limiter for the [Elixir](https://elixir-lang.org/) language.
It's killer feature is a pluggable backend system, allowing you to use whichever
storage suits your needs. Currently, backends for ETS,
[Redis](https://github.com/ExHammer/hammer-backend-redis), and [Mnesia](https://github.com/ExHammer/hammer-backend-mnesia) are available.


```elixir
    case Hammer.check_rate("file_upload:#{user_id}", 60_000, 10) do
      {:allow, _count} ->
        Upload.file(data)
      {:deny, _limit} ->
        render_error_page()
    end
```

To get started with Hammer, read the [Tutorial](/hammer/tutorial.html).

See the [Hammer.Application module](/hammer/Hammer.Application.html) for full
documentation of configuration options.

A primary goal of the Hammer project is to make it easy to implement new storage
backends. See the [documentation on creating
backends](/hammer/creatingbackends.html) for more details.

## New! Hammer-Plug

We've just released a new helper-library to make adding rate-limiting to your Phoenix
(or other plug-based) application even easier: [Hammer.Plug](https://github.com/ExHammer/hammer-plug).
