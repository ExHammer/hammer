defmodule Hammer.ETS do
  @moduledoc """
  An ETS backend for Hammer.

  Configuration:
  - `:table` - (atom) name of the ETS table, defaults to the module name that called `use Hammer`

  Example:

      defmodule MyApp.RateLimit do
        # these are the defaults
        use Hammer, backend: :ets, table: MyApp.RateLimit
      end

  """

  use GenServer

  @type start_option :: {:table, atom} | {:clean_period, timeout} | GenServer.option()

  @doc """
  Starts the process that creates and cleans the ETS table.

  Accepts the following options:
    - `GenServer.options()`
    - `:table` for the ETS table name, defaults to the module name
    - `:clean_period` for how often to perform garbage collection
  """
  @spec start_link([start_option]) :: GenServer.on_start()
  def start_link(opts) do
    {gen_opts, opts} =
      Keyword.split(opts, [:debug, :name, :timeout, :spawn_opt, :hibernate_after])

    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Checks the rate-limit for a key.
  """
  @spec check_rate(:ets.table(), key, scale, limit, increment) :: {:allow, count} | {:deny, limit}
        when key: term,
             scale: pos_integer,
             limit: pos_integer,
             increment: pos_integer,
             count: pos_integer
  def check_rate(table, key, scale, limit, increment \\ 1) do
    bucket = div(now(), scale)
    full_key = {key, bucket}
    expires_at = (bucket + 1) * scale
    count = :ets.update_counter(table, full_key, increment, {full_key, 0, expires_at})
    if count <= limit, do: {:allow, count}, else: {:deny, limit}
  end

  @impl true
  def init(opts) do
    clean_period = Keyword.fetch!(opts, :clean_period)
    table = Keyword.fetch!(opts, :table)

    ^table =
      :ets.new(table, [
        :named_table,
        :set,
        :public,
        {:read_concurrency, true},
        {:write_concurrency, true},
        {:decentralized_counters, true}
      ])

    schedule(clean_period)
    {:ok, %{table: table, clean_period: clean_period}}
  end

  @impl true
  def handle_info(:clean, state) do
    clean(state.table)
    schedule(state.clean_period)
    {:noreply, state}
  end

  defp schedule(clean_period) do
    Process.send_after(self(), :clean, clean_period)
  end

  defp clean(table) do
    ms = [{{{:_, :_}, :_, :"$1"}, [], [{:<, :"$1", {:const, now()}}]}]
    :ets.select_delete(table, ms)
  end

  @compile inline: [now: 0]
  defp now do
    System.system_time(:millisecond)
  end
end
