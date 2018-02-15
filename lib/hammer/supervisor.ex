defmodule Hammer.Supervisor do
  @moduledoc """
  Top-level Supervisor for the Hammer application

  Example of config for multiple-backends:

      config :hammer,
      backend: [
        ets: {
          Hammer.Backend.ETS,
          [
            ets_table_name: :hammer_backend_ets_buckets,
            expiry_ms: 60_000 * 60 * 2,
            cleanup_interval_ms: 60_000 * 2
          ]
        },
        redis: {
          Hammer.Backend.Redis,
          [
            expiry_ms: 60_000 * 60 * 2,
            redix_config: [host: "localhost", port: 6379]
          ]
        }
      ]
  """

  use Supervisor

  def start_link(config, opts) do
    Supervisor.start_link(__MODULE__, config, opts)
  end

  def init(config) when is_tuple(config) do
    children = [
      to_child_spec(config)
    ]
    Supervisor.init(children, strategy: :one_for_one, name: __MODULE__)
  end
  def init(config) when is_list(config) do
    children = config
    |> Enum.map(fn ({_k, c}) -> to_child_spec(c) end)
    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end

  defp to_child_spec({mod, args}) do
    supervisor_module = String.to_atom(
      Atom.to_string(mod) <> ".Supervisor"
    )
    Supervisor.child_spec(
      {supervisor_module, args},
      id: supervisor_module
    )
  end
end
