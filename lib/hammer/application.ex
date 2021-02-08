defmodule Hammer.Application do
  @moduledoc """
  Hammer application, responsible for starting the backend worker pools.

  Configured with the `:hammer` environment key:

  - `:backend`, Either a tuple of `{module, config}`, or a keyword-list
    of separate, named backends. Examples:
    `{Hammer.Backend.ETS, []}`, `[ets: {Hammer.Backend.ETS, []}, ...]`
  - `:suppress_logs`, if set to `true`, stops all log messages from Hammer

  ### General Backend Options

  Different backends take different options, but all will accept the following
  options, and with the same effect:

  - `:expiry_ms` (int): expiry time in milliseconds, after which a bucket will
    be deleted. The exact mechanism for cleanup will vary by backend. This configuration
    option is mandatory
  - `:pool_size` (int): size of the backend worker pool (default=2)
  - `:pool_max_overflow` int(): number of extra workers the pool is permitted
    to spawn when under pressure. The worker pool (managed by the poolboy library)
    will automatically create and destroy workers up to the max-overflow limit
    (default=0)

  Example of a single backend:

      config :hammer,
        backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60 * 2]}

  Example of config for multiple-backends:

      config :hammer,
        backend: [
          ets: {
            Hammer.Backend.ETS,
            [
              ets_table_name: :hammer_backend_ets_buckets,
              expiry_ms: 60_000 * 60 * 2,
              cleanup_interval_ms: 60_000 * 2,
            ]
          },
          redis: {
            Hammer.Backend.Redis,
            [
              expiry_ms: 60_000 * 60 * 2,
              redix_config: [host: "localhost", port: 6379],
              pool_size: 4,
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
