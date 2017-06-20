defmodule Hammer.Backend.ETS do
  use GenServer
  @moduledoc """
  An ETS backend for Hammer

  The public API of this module is used by Hammer to store information about rate-limit 'buckets'.
  A bucket is identified by a `key`, which is a tuple `{bucket_number, id}`.
  The essential schema of a bucket is: `{key, count, created_at, updated_at}`, although backends
  are free to store and retrieve this data in whichever way they wish.

  """

  ## Public API

  def start_link() do
    start_link([])
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def stop() do
    GenServer.call(__MODULE__, :stop)
  end

  @doc """
  Setup function, called once when the Hammer server is initialised
  """
  @spec setup(config::map)
        :: :ok
          | {:error, reason::String.t}
  def setup(config) do
    GenServer.call(__MODULE__, {:setup, config})
  end

  @doc """
  Record a hit in the bucket identified by `key`
  """
  @spec count_hit(key::{bucket::integer, id::String.t}, now::integer)
        :: {:ok, count::integer}
         | {:error, reason::String.t}
  def count_hit(key, now) do
    GenServer.call(__MODULE__, {:count_hit, key, now})
  end

  @doc """
  Retrieve information about the bucket identified by `key`
  """
  @spec get_bucket(key::{bucket::integer, id::String.t})
        :: nil
         | {key::{bucket::integer, id::String.t}, count::integer, created::integer, updated::integer}
  def get_bucket(key) do
    GenServer.call(__MODULE__, {:get_bucket, key})
  end

  @doc """
  Delete all buckets associated with `id`.
  """
  @spec delete_buckets(id::String.t)
        :: {:ok, count_deleted::integer}
         | {:error, reason::String.t}
  def delete_buckets(id) do
    GenServer.call(__MODULE__, {:delete_buckets, id})
  end

  @doc """
  Delete 'old' buckets which were last updated before `expire_now`.
  """
  @spec prune_expired_buckets(now::integer, expire_before::integer)
        :: :ok
         | {:error, reason::String.t}
  def prune_expired_buckets(now, expire_before) do
    GenServer.call(__MODULE__, {:prune_expired_buckets, now, expire_before})
  end


  ## GenServer Callbacks

  def init(args) do
    ets_table_name = Keyword.get(args, :ets_table_name, :hammer_ets_buckets)
    state = %{ets_table_name: ets_table_name}
    {:ok, state}
  end

  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end

  def handle_call({:setup, _config}, _from, state) do
    %{ets_table_name: tn} = state
    :ets.new(tn, [:named_table, :ordered_set, :private])
    {:reply, :ok, state}
  end

  def handle_call({:count_hit, key, now}, _from, state) do
    %{ets_table_name: tn} = state
    case :ets.member(tn, key) do
      false ->
        true = :ets.insert(tn, {key, 1, now, now})
        {:reply, {:ok, 1}, state}
      true ->
        [count, _, _] = :ets.update_counter(tn, key, [{2,1},{3,0},{4,1,0, now}])
        {:reply, {:ok, count}, state}
    end
  end

  def handle_call({:get_bucket, key}, _from, state) do
    %{ets_table_name: tn} = state
    result = case :ets.lookup(tn, key) do
      [] ->
        nil
      [bucket] ->
        bucket
    end
    {:reply, result, state}
  end

  def handle_call({:delete_buckets, id}, _from, state) do
    %{ets_table_name: tn} = state
    # fun do {{bucket_number, bid},_,_,_} when bid == ^id -> true end
    count_deleted = :ets.select_delete(
      tn, [{{{:"$1", :"$2"}, :_, :_, :_}, [{:==, :"$2", id}], [true]}]
    )
    {:reply, {:ok, count_deleted}, state}
  end

  def handle_call({:prune_expired_buckets, _now, expire_before}, _from, state) do
    %{ets_table_name: tn} = state
    :ets.select_delete(tn, [{{:_, :_, :_, :"$1"}, [{:<, :"$1", expire_before}], [true]}])
    {:reply, :ok, state}
  end

end
