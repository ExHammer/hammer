defmodule Hammer do
  use GenServer

  @moduledoc """
  Documentation for Hammer.
  """

  ## Public API

  @doc """
  """
  def start_link(args, opts \\ []) do
    args_with_defaults = Keyword.merge(
      [backend: Hammer.ETS,
       cleanup_rate: 60 * 1000],  # Is timeout necessary?
      args,
      fn (_k, _a, b) -> b end
    )
    GenServer.start_link(
      __MODULE__,
      args_with_defaults,
      Keyword.merge(opts, name: __MODULE__)
    )
  end

  @doc """
  """
  def check_rate(id, scale, limit) do
    GenServer.call(__MODULE__, {:check_rate, id, scale, limit})
  end

  @doc """
  """
  @spec inspect_bucket(id::String.t, scale::integer, limit::integer) :: {count::integer,
                                                                         count_remaining::integer,
                                                                         ms_to_next_bucket::integer,
                                                                         created_at :: integer | nil,
                                                                         updated_at :: integer | nil}
  def inspect_bucket(id, scale, limit) do
    GenServer.call(__MODULE__, {:inspect_bucket, id, scale, limit})
  end

  @doc """
  """
  @spec delete_bucket(id::String.t) :: :ok | :error
  def delete_bucket(id) do
    GenServer.call(__MODULE__, {:delete_bucket, id})
  end

  def stop() do
    GenServer.call(__MODULE__, :stop)
  end

  ## GenServer Callbacks

  def init(args) do
    backend_mod = Keyword.get(args, :backend)
    cleanup_rate = Keyword.get(args, :cleanup_rate)
    apply(backend_mod, :setup, [])
    :timer.send_interval(cleanup_rate, :prune)
    {:ok, %{backend: backend_mod}}
  end

  def handle_call({:check_rate, id, scale, limit}, _from, state) do
    %{backend: backend} = state
    {stamp, key} = Hammer.Utils.stamp_key(id, scale)
    result = case apply(backend, :count_hit, [key, stamp]) do
      {:ok, count} ->
        if (count > limit) do
          {:error, limit}
        else
          {:ok, count}
        end
      {:error, _reason} ->
         {:error, limit}
    end
    {:reply, result, state}
  end

  def handle_call({:inspect_bucket, id, scale, limit}, _from, state) do
    %{backend: backend} = state
    {stamp, key} = Hammer.Utils.stamp_key(id, scale)
    ms_to_next_bucket = (elem(key, 0) * scale) + scale - stamp
    result = case apply(backend, :get_bucket, [key]) do
      nil ->
        {0, limit, ms_to_next_bucket, nil, nil}
      {_, count, created_at, updated_at} ->
        count_remaining = if limit > count, do: limit - count, else: 0
        {count, count_remaining, ms_to_next_bucket, created_at, updated_at}
    end
    {:reply, result, state}
  end

  def handle_call({:delete_bucket, id}, _from, state) do
    %{backend: backend} = state
    result = apply(backend, :delete_bucket, [id])
    {:reply, result, state}
  end

  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end

  def handle_info(:prune, state) do
    %{backend: backend} = state
    apply(backend, :prune_expired_buckets, [])
    {:noreply, state}
  end

end
