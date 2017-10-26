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

  defp start_backend(_key, which) when is_list(which) do
    Enum.reduce(which, :ok, fn({key, config}, _acc) -> start_backend(key, config) end)
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
