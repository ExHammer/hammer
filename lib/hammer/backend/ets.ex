defmodule Hammer.Backend.ETS do
  @moduledoc """
  An ETS backend for Hammer

  The public API of this module is used by Hammer to store information about rate-limit 'buckets'.
  A bucket is identified by a `key`, which is a tuple `{bucket_number, id}`.
  The essential schema of a bucket is: `{key, count, created_at, updated_at}`, although backends
  are free to store and retrieve this data in whichever way they wish.

  Use `start` or `start_link` to start the server:

      {:ok, pid} = Hammer.Backend.ETS.start_link(args)

  `args` is a keyword list:
  - `ets_table_name`: (atom) table name to use, defaults to `:hammer_ets_buckets`
  - `expiry_ms`: (integer) time in ms before a bucket is auto-deleted,
    should be larger than the expected largest size/duration of a bucket
  - `cleanup_interval_ms`: (integer) time between cleanup runs,

  Example:

      Hammer.Backend.ETS.start_link(
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
    GenServer.call(pid, {:count_hit, key, now})
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
    ets_table_name = Keyword.get(args, :ets_table_name, :hammer_ets_buckets)
    cleanup_interval_ms = Keyword.get(args, :cleanup_interval_ms)
    expiry_ms = Keyword.get(args, :expiry_ms)

    case :ets.info(ets_table_name) do
      :undefined ->
        :ets.new(ets_table_name, [:named_table, :ordered_set, :public])

      _ ->
        nil
    end

    :timer.send_interval(cleanup_interval_ms, :prune)

    state = %{
      ets_table_name: ets_table_name,
      cleanup_interval_ms: cleanup_interval_ms,
      expiry_ms: expiry_ms
    }

    {:ok, state}
  end

  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end

  def handle_call({:count_hit, key, now}, _from, state) do
    %{ets_table_name: tn} = state

    try do
      if :ets.member(tn, key) do
        [count, _, _] = :ets.update_counter(tn, key, [{2, 1}, {3, 0}, {4, 1, 0, now}])
        {:reply, {:ok, count}, state}
      else
        true = :ets.insert(tn, {key, 1, now, now})
        {:reply, {:ok, 1}, state}
      end
    rescue
      e ->
        {:reply, {:error, e}, state}
    end
  end

  def handle_call({:get_bucket, key}, _from, state) do
    %{ets_table_name: tn} = state

    try do
      result =
        case :ets.lookup(tn, key) do
          [] ->
            {:ok, nil}

          [bucket] ->
            {:ok, bucket}
        end

      {:reply, result, state}
    rescue
      e ->
        {:reply, {:error, e}, state}
    end
  end

  def handle_call({:delete_buckets, id}, _from, state) do
    %{ets_table_name: tn} = state
    # Compiled from:
    #   fun do {{bucket_number, bid},_,_,_} when bid == ^id -> true end
    try do
      count_deleted =
        :ets.select_delete(tn, [{{{:"$1", :"$2"}, :_, :_, :_}, [{:==, :"$2", id}], [true]}])

      {:reply, {:ok, count_deleted}, state}
    rescue
      e ->
        {:reply, {:error, e}, state}
    end
  end

  def handle_info(:prune, state) do
    %{expiry_ms: expiry_ms, ets_table_name: tn} = state
    now = Utils.timestamp()
    expire_before = now - expiry_ms

    :ets.select_delete(tn, [
      {{:_, :_, :_, :"$1"}, [{:<, :"$1", expire_before}], [true]}
    ])

    {:noreply, state}
  end
end
