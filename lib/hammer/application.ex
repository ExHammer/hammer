defmodule Hammer.Application do
  @moduledoc """
  Hammer application, responsible for starting the ETS backend.
  """

  use Application

  def start(_type, _args) do
    Hammer.Backend.ETS.Supervisor.start_link(
      Application.get_env(:hammer, :ets),
      name: :hammer_backend_ets_sup
    )
  end

end
