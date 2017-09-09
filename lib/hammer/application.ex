defmodule Hammer.Application do
  @moduledoc """
  Hammer application, responsible for starting the ETS backend.
  """

  use Application

  def start(_type, _args) do
    {backend_module, backend_config} = Application.get_env(
      :hammer,
      :backend,
      {Hammer.Backend.ETS, []}
    )
    supervisor_module = String.to_atom(
      Atom.to_string(backend_module) <> ".Supervisor"
    )
    supervisor_module.start_link(
      backend_config,
      name: :hammer_backend_sup
    )
  end

end
