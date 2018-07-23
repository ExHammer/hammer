defmodule Hammer.Backend.ETS do
  @moduledoc """
  An ETS backend for Hammer

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

      Hammer.Backend.ETS.start_link(
        expiry_ms: 1000 * 60 * 60,
        cleanup_interval_ms: 1000 * 60 * 10
      )
  """

  @behaviour Hammer.Backend

  @type bucket_key :: {bucket :: integer, id :: String.t()}
  @type bucket_info ::
          {key :: bucket_key, count :: integer, created :: integer, updated :: integer}

  @ets_table_name __MODULE__

  use GenServer
  alias Hammer.Utils

  ## Public API

  def start do
    start([])
  end

  def start(args) do
    GenServer.start(__MODULE__, args, name: __MODULE__)
  end

  def start_link do
    start_link([])
  end

  @doc """
  """
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def stop do
    GenServer.call(__MODULE__, :stop)
  end

  @doc """
  Record a hit in the bucket identified by `key`
  """
  @spec count_hit(
          key :: bucket_key,
          now :: integer
        ) ::
          {:ok, count :: integer}
          | {:error, reason :: any}
  def count_hit(key, now) do
    count_hit(key, now, 1)
  end

  @doc """
  Record a hit in the bucket identified by `key`, with a custom increment
  """
  @spec count_hit(
          key :: bucket_key,
          now :: integer,
          increment :: integer
        ) ::
          {:ok, count :: integer}
          | {:error, reason :: any}
  def count_hit(key, now, increment) do
    [count, _] =
      :ets.update_counter(
        @ets_table_name,
        key,
        [{2, increment}, {4, 1, 0, now}],
        {key, 0, now, now}
      )

    {:ok, count}
  rescue
    err ->
      {:error, err}
  end

  @doc """
  Retrieve information about the bucket identified by `key`
  """
  @spec get_bucket(key :: bucket_key) ::
          {:ok, info :: bucket_info}
          | {:ok, nil}
          | {:error, reason :: any}
  def get_bucket(key) do
    case :ets.lookup(@ets_table_name, key) do
      [] -> {:ok, nil}
      [bucket] -> {:ok, bucket}
    end
  rescue
    e ->
      {:error, e}
  end

  @doc """
  Delete all buckets associated with `id`.
  """
  @spec delete_buckets(id :: String.t()) ::
          {:ok, count_deleted :: integer}
          | {:error, reason :: any}
  def delete_buckets(id) do
    # Compiled from:
    #   fun do {{bucket_number, bid},_,_,_} when bid == ^id -> true end
    count_deleted =
      :ets.select_delete(@ets_table_name, [
        {{{:"$1", :"$2"}, :_, :_, :_}, [{:==, :"$2", id}], [true]}
      ])

    {:ok, count_deleted}
  rescue
    e ->
      {:error, e}
  end

  ## GenServer Callbacks

  def init(args) do
    :ets.new(@ets_table_name, [:named_table, :ordered_set, :public])
    cleanup_interval_ms = Keyword.get(args, :cleanup_interval_ms)
    :timer.send_interval(cleanup_interval_ms, :prune)

    state = %{
      ets_table_name: @ets_table_name,
      cleanup_interval_ms: cleanup_interval_ms,
      expiry_ms: Keyword.get(args, :expiry_ms)
    }

    {:ok, state}
  end

  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
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
