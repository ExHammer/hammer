defmodule Hammer.Backend.ETS.Supervisor do
  @moduledoc """
  Supervisor for the ETS backend.
  """

  @config_options [:ets_table_name, :expiry_ms, :cleanup_interval_ms]

  use Supervisor

  def start_link(config, opts) do
    Supervisor.start_link(__MODULE__, config, opts)
  end

  def init(config) do
    backend_config = config |> Enum.filter(
      fn({k, _v}) -> Enum.member?(@config_options, k) end
    )
    children = [
      worker(Hammer.Backend.ETS, [backend_config], name: Hammer.Backend.ETS)
    ]
    supervise(children, strategy: :one_for_one, name: __MODULE__)
  end
end
