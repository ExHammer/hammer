defmodule Hammer.Backend.Memory do
  @moduledoc """
  An in-memory backend for Hammer.

  Note: This backend is suitable for development, testing, and small
  single-node deployments, but should not be used for production workloads.

  The public API of this module is used by Hammer to store information about
  rate-limit 'buckets'. A bucket is identified by a `key`, which is a tuple
  `{bucket_number, id}`. The essential schema of a bucket is:
  `{key, count, created_at, updated_at}`, although backends are free to
  store and retrieve this data in whichever way they wish.

  Use `start` or `start_link` to start the server:

      {:ok, pid} = Hammer.Backend.ETS.start_link(args)

  `args` is a keyword list:
  - `expiry_ms`: (integer) time in ms before a bucket is auto-deleted,
    should be larger than the expected largest size/duration of a bucket
  - `cleanup_interval_ms`: (integer) time between cleanup runs,

  Example:

      Hammer.Backend.Memory.start_link(
        expiry_ms: 1000 * 60 * 60,
        cleanup_interval_ms: 1000 * 60 * 10
      )
  """

  @behaviour Hammer.Backend

  @type bucket_key :: {bucket :: integer, id :: String.t()}
  @type bucket_info ::
          {key :: bucket_key, count :: integer, created :: integer, updated :: integer}

  use GenServer
  alias Hammer.Utils

  ## Public API

  def start do
    start([])
  end

  def start(args) do
    GenServer.start(__MODULE__, args)
  end

  def start_link do
    start_link([])
  end

  @doc """
  """
  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def stop do
    GenServer.call(__MODULE__, :stop)
  end

  @doc """
  Record a hit in the bucket identified by `key`
  """
  @spec count_hit(
          pid :: pid(),
          key :: bucket_key,
          now :: integer
        ) ::
          {:ok, count :: integer}
          | {:error, reason :: any}
  def count_hit(pid, key, now) do
    GenServer.call(pid, {:count_hit, key, now, 1})
  end

  @doc """
  Record a hit in the bucket identified by `key`, with a custom increment
  """
  @spec count_hit(
          pid :: pid(),
          key :: bucket_key,
          now :: integer,
          increment :: integer
        ) ::
          {:ok, count :: integer}
          | {:error, reason :: any}
  def count_hit(pid, key, now, increment) do
    GenServer.call(pid, {:count_hit, key, now, increment})
  end

  @doc """
  Retrieve information about the bucket identified by `key`
  """
  @spec get_bucket(
          pid :: pid(),
          key :: bucket_key
        ) ::
          {:ok, info :: bucket_info}
          | {:ok, nil}
          | {:error, reason :: any}
  def get_bucket(pid, key) do
    GenServer.call(pid, {:get_bucket, key})
  end

  @doc """
  Delete all buckets associated with `id`.
  """
  @spec delete_buckets(
          pid :: pid(),
          id :: String.t()
        ) ::
          {:ok, count_deleted :: integer}
          | {:error, reason :: any}
  def delete_buckets(pid, id) do
    GenServer.call(pid, {:delete_buckets, id})
  end

  ## GenServer Callbacks

  def init(args) do
    cleanup_interval_ms = Keyword.get(args, :cleanup_interval_ms)
    expiry_ms = Keyword.get(args, :expiry_ms)

    if !expiry_ms do
      raise RuntimeError, "Missing required config: expiry_ms"
    end

    if !cleanup_interval_ms do
      raise RuntimeError, "Missing required config: cleanup_interval_ms"
    end

    :timer.send_interval(cleanup_interval_ms, :prune)

    state = %{
      buckets: %{},
      cleanup_interval_ms: cleanup_interval_ms,
      expiry_ms: expiry_ms
    }

    {:ok, state}
  end

  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end

  def handle_call({:count_hit, key, now, increment}, _from, state) do
    %{buckets: buckets} = state

    try do
      case Map.get(buckets, key) do
        nil ->
          # Insert key => {count, created_at, updated_at}
          updated_buckets = Map.put(buckets, key, {increment, now, now})
          {:reply, {:ok, increment}, %{state | buckets: updated_buckets}}

        {count, created_at, _updated_at} ->
          # Update count and updated_at fields
          new_count = count + increment
          updated_buckets = Map.put(buckets, key, {new_count, created_at, now})
          {:reply, {:ok, new_count}, %{state | buckets: updated_buckets}}
      end
    rescue
      e ->
        IO.puts ">> err, #{e}"
        {:reply, {:error, e}, state}
    end
  end

  def handle_call({:get_bucket, key}, _from, state) do
    %{buckets: buckets} = state

    try do
      result =
        case Map.get(buckets, key) do
          nil ->
            {:ok, nil}

          bucket ->
            {:ok, bucket}
        end

      {:reply, result, state}
    rescue
      e ->
        {:reply, {:error, e}, state}
    end
  end

  def handle_call({:delete_buckets, id}, _from, state) do
    %{buckets: buckets} = state

    try do
      buckets =
        Enum.filter(
          buckets,
          fn {{_n, i}, _v} -> i == id end
        )

      {:reply, {:ok, 1}, %{state | buckets: buckets}}
    rescue
      e ->
        {:reply, {:error, e}, state}
    end
  end

  def handle_info(:prune, state) do
    %{buckets: buckets, expiry_ms: expiry_ms} = state
    now = Utils.timestamp()
    expire_before = now - expiry_ms

    try do
      filtered_buckets =
        Enum.filter(
          buckets,
          fn {_k, {_count, _created_at, updated_at}} ->
            updated_at < expire_before
          end
        )
        |> Enum.into(%{})

      {:noreply, %{state | buckets: filtered_buckets}}
    rescue
      e ->
        {:noreply, state}
    end
  end
end
