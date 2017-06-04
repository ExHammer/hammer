defmodule Hammer.Dummy do
  require Logger
  use GenServer
  @moduledoc """
  A dummy backend for Hammer
  """

  ## Public API

  def start_link() do
    start_link(%{})
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def stop(server) do
    GenServer.call(server, :stop)
  end

  def ping() do
    GenServer.call(__MODULE__, :ping)
  end

  def setup() do
    GenServer.call(__MODULE__, :setup)
  end

  def bucket_exists?(key) do
    GenServer.call(__MODULE__, :bucket_exists?, key)
  end

  def increment_bucket(key) do
    GenServer.call(__MODULE__, :increment_bucket, key)
  end

  def inspect_bucket(key) do
    GenServer.call(__MODULE__, :inspect_bucket, key)
  end

  def delete_bucket(key) do
    GenServer.call(__MODULE__, :delete_bucket, key)
  end

  def prune_expired_buckets() do
    GenServer.call(__MODULE__, :prune_expired_buckets)
  end


  ## GenServer Callbacks

  def init(_args) do
    {:ok, %{buckets: %{}}}
  end

  def handle_call(:ping, _from, state) do
    {:reply, :dummy_pong, state}
  end

  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end

  def handle_call(:setup, _from, state) do
    Logger.log(:info, "Setup #{__MODULE__}")
    {:reply, :ok, state}
  end

  def handle_call(:bucket_exists?, key, %{buckets: buckets}=state) do
    has_bucket = Map.has_key?(buckets, key)
    {:reply, has_bucket, state}
  end

  def handle_call(:delete_bucket, key, %{buckets: buckets}=state) do
    new_buckets = Map.delete(buckets, key)
    {:reply, :ok, Map.put(state, :buckets, new_buckets)}
  end

  ### Incomplete, experiment over

end
