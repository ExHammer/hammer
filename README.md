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


## API

### `Hammer.start_link(args, genserver_opts)`

Start the Hammer GenServer process.

The `args` are a keyword-list of:

- `backend`: The backend module to use (default: `Hammer.ETS`)
- `cleanup_rate`: time in milliseconds between cleanup runs (default: `60000`)

The `genserver_opts` are the usual GenServer options, except `name`, which is
ignored (subject to change in a later release).

Returns: The usual GenServer return values.


### `Hammer.check_rate(id, scale, limit)`

Check if a rate-limit has been reached.

- `id`: String id of the limit to be checked (example: `"file_upload"`)
- `scale`: Integer timescale to limit within, in milliseconds (example: `30000`)
- `limit`: Integer limit to apply within the timescale (example: `10`)

Returns: Either `{:ok, count}` where `count` is the number of hits in the current timescale,
or if the limit has been reached, `{:error, limit}` where `limit` is the limit that has been reached.


### `Hammer.inspect_bucket(id, scale, limit)`

Get a data-structure describing the current "bucket" for the rate-limit.

- `id`: String id of the limit to be checked (example: `"file_upload"`)
- `scale`: Integer timescale to limit within, in milliseconds (example: `30000`)
- `limit`: Integer limit to apply within the timescale (example: `10`)

Returns: A tuple of `{count, count_remaining, ms_to_next_bucket, created_at, updated_at}`,


### `Hammer.delete_bucket(id)`

Deletes the current bucket for the given `id`.

*Note, this is subject to change*

- `id`: String id of the limit to be deleted (example: `"file_upload"`)

Returns: Either `:ok` or `:error`


### `Hammer.stop()`

Stop the Hammer GenServer.



## Backend API
