defmodule Hammer.Application do
  @moduledoc """
  Hammer application, responsible for starting the ETS backend.
  Configured with the `:hammer` environment key:

  - `:backend`, Either a tuple of `{module, config}`, or a keyword-list
    of separate, named backends. Examples:
    `{Hammer.Backend.ETS, []}`, `[ets: {Hammer.Backend.ETS, []}, ...]`
  - `:suppress_logs`, if set to `true`, stops all log messages from Hammer

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
