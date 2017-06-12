defmodule Hammer do
  use GenServer

  @moduledoc """
  Documentation for Hammer.
  """

  @default_cleanup_rate 60 * 1000 * 10
  @default_expiry 60 * 1000 * 60 * 2

  ## Public API

  @doc """
  Starts the Hammer GenServer.
  Args:
  - `backend`: Backend module to use for storage, default `Hammer.Backend.ETS`
  - `cleanup_rate`: Milliseconds between cleanup runs, default `#{@default_cleanup_rate}`
  - `expiry`: Time in milliseconds after which to clean-up buckets, default `#{@default_expiry}`,
    should be set to longer than the maximum expected bucket time-span.
  """
  def start_link() do
    start_link([])
  end

  def start_link(args, opts \\ []) do
    args_with_defaults = Keyword.merge(
      [backend: Hammer.Backend.ETS,
       cleanup_rate: @default_cleanup_rate,
       expiry: @default_expiry],
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
  Check if the action you wish to perform is within the bounds of the rate-limit.

  Args:
  - `id`: String name of the bucket. Usually the bucket name is comprised of some fixed prefix,
    with some dynamic string appended, such as an IP address or user id.
  - `scale`: Integer indicating size of bucket in milliseconds
  - `limit`: Integer maximum count of actions within the bucket

  Returns either `{:allow,  count}`, `{:deny,   limit}` or `{:error,  reason}`

  Example:
      user_id = 42076
      case  Hammer.check_rate("file_upload:#{user_id}", 60_000, 5) do
        {:allow, _count} ->
          # do the file upload
        {:deny, limit} ->
          # render an error page or something
      end
  """
  @spec check_rate(id::String.t, scale::integer, limit::integer) :: {:allow, count::integer}
                                                                  | {:deny,  limit::integer}
                                                                  | {:error, reason}
  def check_rate(id, scale, limit) do
    GenServer.call(__MODULE__, {:check_rate, id, scale, limit})
  end

  @doc """
  Inspect bucket to get count, count_remaining, ms_to_next_bucket, created_at, updated_at.
  This function is free of side-effects and should be called with the same arguments you
  would use for `check_rate` if you intended to increment and check the bucket counter.

  Arguments:

  - `id`: String name of the bucket. Usually the bucket name is comprised of some fixed prefix,
  with some dynamic string appended, such as an IP address or user id.
  - `scale`: Integer indicating size of bucket in milliseconds
  - `limit`: Integer maximum count of actions within the bucket

  Example:

      Hammer.inspect_bucket("file_upload:2042", 60_000, 5)
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
  """
  @spec delete_bucket(id::String.t) :: :ok | :error
  def delete_bucket(id) do
    GenServer.call(__MODULE__, {:delete_bucket, id})
  end

  def stop() do
    GenServer.call(__MODULE__, :stop)
  end

  def make_rate_checker(id_prefix, scale, limit) do
    fn (id) -> check_rate("#{id_prefix}#{id}", scale, limit) end
  end

  ## GenServer Callbacks

  def init(args) do
    backend_mod = Keyword.get(args, :backend)
    cleanup_rate = Keyword.get(args, :cleanup_rate)
    expiry = Keyword.get(args, :expiry)
    :ok = apply(backend_mod, :setup, [])
    :timer.send_interval(cleanup_rate, :prune)
    state = %{backend: backend_mod, cleanup_rate: cleanup_rate, expiry: expiry}
    {:ok, state}
  end

  def handle_call({:check_rate, id, scale, limit}, _from, state) do
    %{backend: backend} = state
    {stamp, key} = Hammer.Utils.stamp_key(id, scale)
    result = case apply(backend, :count_hit, [key, stamp]) do
      {:ok, count} ->
        if (count > limit) do
          {:deny, limit}
        else
          {:allow, count}
        end
      {:error, reason} ->
         {:error, reason}
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
    %{backend: backend, expiry: expiry} = state
    now = Hammer.Utils.timestamp()
    expire_before = now - expiry
    :ok = apply(backend, :prune_expired_buckets, [now, expire_before])
    {:noreply, state}
  end

end
