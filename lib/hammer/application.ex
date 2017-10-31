defmodule Hammer.Application do
  @moduledoc """
  Hammer application, responsible for starting the ETS backend.
  """

  use Application
  require Logger

  def start(_type, _args) do
    start_backend(:sup, Application.get_env(
      :hammer,
      :backend,
      {Hammer.Backend.ETS, []}
    ))

  end

  # example multipe backends:
  #
  # config :hammer,
  #  backend: [
  #    ets: {
  #      Hammer.Backend.ETS,
  #      [
  #        ets_table_name: :hammer_backend_ets_buckets,
  #        expiry_ms: 60_000 * 60 * 2,
  #        cleanup_interval_ms: 60_000 * 2
  #      ]
  #    },
  #    redis: {
  #      Hammer.Backend.Redis,
  #      [
  #        expiry_ms: 60_000 * 60 * 2,
  #        redix_config: [host: "localhost", port: 6379]
  #      ]
  #    },
  #    sentinel: {
  #      Hammer.Backend.Redis,
  #      [
  #        expiry_ms: 60_000 * 60 * 2,
  #        redix_config:
  #          [
  #            sentinels: [ [host: "localhost", port: 26379 ], [host: "localhost", port: 26379 ] ],
  #            group: "mymaster"
  #          ]
  #      ]
  #    }
  #  ]
  #
  defp start_backend(_key, which) when is_list(which) do
    Enum.reduce(which, :ok, fn({key, config}, _acc) ->
      start_backend(key, config)
    end)
  end
  defp start_backend(key, {backend_module, backend_config}) do
    Logger.info("Starting Hammer with backend '#{backend_module}'")
    supervisor_module = String.to_atom(
      Atom.to_string(backend_module) <> ".Supervisor"
    )
    supervisor_module.start_link(
      backend_config,
      name: String.to_atom("hammer_backend_" <> Atom.to_string(key))
    )
  end
end
