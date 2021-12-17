defmodule Hammer.Supervisor do
  @moduledoc """
  Top-level Supervisor for the Hammer application.
  Starts a set of poolboy pools based on provided configuration,
  which are latter called to by the `Hammer` module.
  See the Application module for configuration examples.
  """

  use Supervisor

  def start_link(config, opts) do
    Supervisor.start_link(__MODULE__, config, opts)
  end

  # Single backend
  def init(config) do
    children = [
      to_pool_spec(:hammer_backend_single_pool, config)
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # Private helpers
  defp parse_redis_url(redis_url) do
    uri = redis_url
          |> URI.parse
          |> Map.from_struct

    Map.merge(uri, %{ decoded_query: URI.decode_query(uri.query) })
    |> Map.take([:decoded_query, :host, :port])
  end

  defp to_pool_spec(name, redis_url) do
    %{
      decoded_query: decoded_query,
      host: host,
      port: port,
    } = parse_redis_url(redis_url)

    pool_size = decoded_query["pool_size"] || 4
    pool_max_overflow = decoded_query["pool_max_overflow"] || 0
    expiry_ms = decoded_query["expiry_ms"] && String.to_integer(decoded_query["expiry_ms"]) || 60_000 * 60 * 2

    opts = [
      name: {:local, name},
      worker_module: Hammer.Backend.Redis,
      size: pool_size,
      max_overflow: pool_max_overflow
    ]

    args = [
      expiry_ms: expiry_ms,
      redix_config: [host: host, port: port]
    ]

    :poolboy.child_spec(name, opts, args)
  end
end
