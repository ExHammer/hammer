defmodule Hammer.Backend.ETS do
  @moduledoc "TODO"

  use GenServer
  @behaviour Hammer.Backend
  @table :hammer_ets_buckets

  @doc "TODO"
  def start_link(opts) do
    {gen_opts, opts} =
      Keyword.split(opts, [:debug, :name, :timeout, :spawn_opt, :hibernate_after])

    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @impl Hammer.Backend
  def count_hit(key, increment, expires_at) do
    {:ok, :ets.update_counter(@table, key, increment, {key, 0, expires_at})}
  end

  @impl Hammer.Backend
  def get_bucket(key) do
    count =
      case :ets.lookup(@table, key) do
        [{^key, count, _expires_at}] -> count
        [] -> 0
      end

    {:ok, count}
  end

  @impl Hammer.Backend
  def delete_buckets(id) do
    ms = [{{{:"$1", :_}, :_, :_}, [], [{:==, :"$1", {:const, id}}]}]
    {:ok, :ets.select_delete(@table, ms)}
  end

  @impl GenServer
  def init(opts) do
    cleanup_interval_ms = Keyword.fetch!(opts, :cleanup_interval_ms)

    @table =
      :ets.new(@table, [
        :named_table,
        :set,
        :public,
        {:read_concurrency, true},
        {:write_concurrency, true},
        {:decentralized_counters, true}
      ])

    schedule(cleanup_interval_ms)
    {:ok, %{cleanup_interval_ms: cleanup_interval_ms}}
  end

  @impl GenServer
  def handle_info(:clean, state) do
    cleanup()
    schedule(state.cleanup_interval_ms)
    {:noreply, state}
  end

  defp cleanup do
    now = System.system_time(:millisecond)
    ms = [{{{:_, :_}, :_, :"$1"}, [], [{:<, :"$1", {:const, now}}]}]
    :ets.select_delete(@table, ms)
  end

  defp schedule(period) do
    Process.send_after(self(), :clean, period)
  end
end
