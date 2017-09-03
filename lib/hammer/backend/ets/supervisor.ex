defmodule Hammer.Backend.ETS.Supervisor do
  @moduledoc """
  Supervisor for the ETS backend.
  """

  use Supervisor

  def start_link(config, opts) do
    Supervisor.start_link(__MODULE__, config, opts)
  end

  def init(config) do
    backend_config = [
      ets_table_name: Keyword.get(config, :ets_table_name),
      expiry_ms: Keyword.get(config, :expiry_ms),
      cleanup_interval_ms: Keyword.get(config, :cleanup_interval_ms)
    ]
    children = [
      worker(Hammer.Backend.ETS, [backend_config])
    ]
    supervise(children, strategy: :one_for_one, name: __MODULE__)
  end
end
