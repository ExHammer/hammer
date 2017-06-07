defmodule Hammer do
  use GenServer

  @moduledoc """
  Documentation for Hammer.
  """

  ## Public API

  @doc """
  Starts the Hammer server.

  Args:
  - backend: Name of backend process to use

  Example:
      Hammer.start_link(%{backend: Hammer.ETS})
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
  Check if the action you wish to take is within the rate limit bounds
  and increment the buckets counter by 1 and its updated_at timestamp.

  ## Arguments:

  - `id` (String) name of the bucket
  - `scale` (Integer) of time in ms until the bucket rolls over.
    (e.g. 60_000 = empty bucket every minute)
  - `limit` (Integer) the max size of a counter the bucket can hold.

  ## Examples

  # Limit to 2500 API requests in one day.
  iex> ExRated.check_rate("my-bucket", 86400000, 2500)
  {:ok, 1}
  """
  def check_rate(id, scale, limit) do
    GenServer.call(__MODULE__, {:check_rate, id, scale, limit})
  end

  @doc """
  Inspect bucket to get count, count_remaining, ms_to_next_bucket, created_at, updated_at.
  This function is free of side-effects and should be called with the same arguments you
  would use for `check_rate` if you intended to increment and check the bucket counter.

  ## Arguments:

  - `id` (String) name of the bucket
  - `scale` (Integer) of time the bucket you want to inspect was created with.
  - `limit` (Integer) representing the max counter size the bucket was created with.

  ## Example - Reset counter for my-bucket

      ExRated.inspect_bucket("my-bucket", 86400000, 2500)
      {0, 2500, 29389699, nil, nil}
      ExRated.check_rate("my-bucket", 86400000, 2500)
      {:ok, 1}
      ExRated.inspect_bucket("my-bucket", 86400000, 2500)
      {1, 2499, 29381612, 1450281014468, 1450281014468}

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
  Delete bucket to reset the counter.

  ## Arguments:

  - `id` (String) name of the bucket

  ## Example - Reset counter for my-bucket

  iex> ExRated.check_rate("my-bucket", 86400000, 2500)
  {:ok, 1}
  iex> ExRated.delete_bucket("my-bucket")
  :ok

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
    IO.inspect("Check Rate: #{stamp}, #{inspect(key)}")
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
