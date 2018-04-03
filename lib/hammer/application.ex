defmodule Hammer.Application do
  @moduledoc """
  Hammer application, responsible for starting the backend worker pools.
  Configured with the `:hammer` environment key:

  - `:backend`, Either a tuple of `{module, config}`, or a keyword-list
    of separate, named backends. Examples:
    `{Hammer.Backend.ETS, []}`, `[ets: {Hammer.Backend.ETS, []}, ...]`
  - `:suppress_logs`, if set to `true`, stops all log messages from Hammer

  Example of a single backend:

      config :hammer,
        backend: {Hammer.Backend.ETS, [expiry: 60_000 * 60 * 2]}

  Example of config for multiple-backends:

      config :hammer,
        backend: [
          ets: {
            Hammer.Backend.ETS,
            [
              ets_table_name: :hammer_backend_ets_buckets,
              expiry_ms: 60_000 * 60 * 2,
              cleanup_interval_ms: 60_000 * 2,
              pool_size: 2,
              pool_max_overflow: 4
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

  use Application
  require Logger

  def start(_type, _args) do
    config =
      Application.get_env(
        :hammer,
        :backend,
        {Hammer.Backend.ETS, []}
      )

    Hammer.Supervisor.start_link(config, name: Hammer.Supervisor)
  end
end
