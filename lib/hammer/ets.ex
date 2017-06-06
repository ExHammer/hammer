defmodule Hammer.ETS do
  use GenServer
  @moduledoc """
  An ETS backend for Hammer
  """

  ## Public API

  def start_link() do
    start_link(%{})
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def stop() do
    GenServer.call(__MODULE__, :stop)
  end

  def ping() do
    GenServer.call(__MODULE__, :ping)
  end

  def setup() do
    GenServer.call(__MODULE__, :setup)
  end

  def count_hit(key, stamp) do
    GenServer.call(__MODULE__, {:count_hit, key, stamp})
  end

  def get_bucket(key) do
    GenServer.call(__MODULE__, {:get_bucket, key})
  end

  def delete_bucket(id) do
    GenServer.call(__MODULE__, {:delete_bucket, id})
  end

  def prune_expired_buckets() do
    GenServer.call(__MODULE__, :prune_expired_buckets)
  end


  ## GenServer Callbacks

  def init(args) do
    ets_table_name = Map.get(args, :ets_table_name, :hammer_ets_buckets)
    state = %{ets_table_name: ets_table_name}
    {:ok, state}
  end

  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end

  def handle_call(:setup, _from, state) do
    %{ets_table_name: tn} = state
    :ets.new(tn, [:named_table, :ordered_set, :private])
    {:reply, :ok, state}
  end

  def handle_call({:count_hit, key, stamp}, _from, state) do
    %{ets_table_name: tn} = state
    case :ets.member(tn, key) do
      false ->
        true = :ets.insert(tn, {key, 1, stamp, stamp})
        {:reply, {:ok, 1}, state}
      true ->
        [count, _, _] = :ets.update_counter(tn, key, [{2,1},{3,0},{4,1,0, stamp}])
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

  # TODO: re-assess this api
  def handle_call({:delete_bucket, id}, _from, state) do
    %{ets_table_name: tn} = state
    # fun do {{bucket_number, bid},_,_,_} when bid == ^id -> true end
    case :ets.select_delete(
      tn, [{{{:"$1", :"$2"}, :_, :_, :_}, [{:==, :"$2", id}], [true]}]
    ) do
      1 ->
        {:reply, :ok, state}
      _ ->
        {:reply, :error, state}
    end
  end

  def handle_call(:prune_expired_buckets, _from, state) do
    {:reply, :ok, state}
  end


  ## Private Helpers


end
