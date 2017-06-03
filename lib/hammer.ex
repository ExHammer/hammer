defmodule Hammer do
  use GenServer

  @moduledoc """
  Documentation for Hammer.
  """

  @doc """
  Starts the Hammer server.

  Args:
  - backend: Name of backend process to use

  Example:
      Hammer.start_link(%{backend: Hammer.ETS})
  """
  def start_link(args, _opts \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def stop(server) do
    GenServer.call(server, :stop)
  end

  def ping() do
    GenServer.call(__MODULE__, :ping)
  end

  ## GenServer Callbacks

  def init(args) do
    %{backend: backend_mod} = args
    {:ok, %{backend: backend_mod}}
  end

  def handle_call(:ping, _from, %{backend: backend_mod}=state) do
    result = apply(backend_mod, :ping, [])
    {:reply, result, state}
  end
end
