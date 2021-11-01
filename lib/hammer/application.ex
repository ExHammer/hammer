defmodule Hammer.Application do
  @moduledoc """
  Hammer application, responsible for starting the backend worker pools.
  Configured with the `:hammer` environment key:

  - `:backend`, A tuple of `{module, config}`
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

  """

  use Application
  require Logger

  def start(_type, _args) do
    config =
      Application.get_env(
        :hammer,
        :backend,
        {Hammer.Backend.Redis, []}
      )

    Hammer.Supervisor.start_link(config, name: Hammer.Supervisor)
  end
end
