defmodule Hammer.Dummy do
  use GenServer
  @moduledoc """
  A dummy backend for Hammer
  """

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def stop(server) do
    GenServer.call(server, :stop)
  end

  def ping() do
    GenServer.call(__MODULE__, :ping)
  end

  ## GenServer Callbacks

  def init(_args) do
    {:ok, %{}}
  end

  def handle_call(:ping, _from, state) do
    {:reply, :dummy_pong, state}
  end

  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end

end
