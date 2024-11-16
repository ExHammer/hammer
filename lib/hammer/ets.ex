defmodule Hammer.ETS do
  @moduledoc """
  An ETS backend for Hammer.

      defmodule MyApp.RateLimit do
        use Hammer, backend: :ets, table: MyApp.RateLimit
      end

      MyApp.RateLimit.start_link(clean_period: :timer.minutes(10))

  Compile-time configuration:
  - `:table` - (atom) name of the ETS table, defaults to the module name that called `use Hammer`

  Runtime configuration:
  - `:clean_period` - (in milliseconds) period to clean up expired entries, defaults to 10 minutes
  """

  use GenServer

  defmacro __before_compile__(%{module: module} = _env) do
    hammer_opts = Module.get_attribute(module, :hammer_opts)
    table = Keyword.get(hammer_opts, :table, module)

    quote do
      @table unquote(table)

      def child_spec(opts) do
        %{
          id: unquote(module),
          start: {unquote(module), :start_link, [opts]},
          type: :worker
        }
      end

      def start_link(opts) do
        opts = Keyword.put(opts, :table, @table)
        opts = Keyword.put_new(opts, :clean_period, :timer.minutes(10))
        Hammer.ETS.start_link(opts)
      end

      def hit(key, scale, limit, increment \\ 1) do
        Hammer.ETS.hit(@table, key, scale, limit, increment)
      end

      def inc(key, scale, increment \\ 1) do
        Hammer.ETS.inc(@table, key, scale, increment)
      end

      def set(key, scale, count) do
        Hammer.ETS.set(@table, key, scale, count)
      end

      def get(key, scale) do
        Hammer.ETS.get(@table, key, scale)
      end
    end
  end

  @type start_option :: {:clean_period, timeout} | GenServer.option()

  @doc """
  Starts the process that creates and cleans the ETS table.

  Accepts the following options:
    - some `GenServer.options()`
    - `:clean_period` for how often to perform garbage collection
  """
  @spec start_link([start_option]) :: GenServer.on_start()
  def start_link(opts) do
    {gen_opts, opts} = Keyword.split(opts, [:debug, :spawn_opt, :hibernate_after])
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc false
  def hit(table, key, scale, limit, increment) do
    now = now()
    window = div(now, scale)
    full_key = {key, window}
    expires_at = (window + 1) * scale
    count = :ets.update_counter(table, full_key, increment, {full_key, 0, expires_at})

    if count <= limit do
      {:allow, count}
    else
      until_next_window = max(expires_at - now, 0)
      {:deny, until_next_window}
    end
  end

  @doc false
  def inc(table, key, scale, increment) do
    window = div(now(), scale)
    full_key = {key, window}
    expires_at = (window + 1) * scale
    :ets.update_counter(table, full_key, increment, {full_key, 0, expires_at})
  end

  @doc false
  def set(table, key, scale, count) do
    window = div(now(), scale)
    full_key = {key, window}
    expires_at = (window + 1) * scale
    :ets.update_counter(table, full_key, {2, 1, 0, count}, {full_key, 0, expires_at})
  end

  @doc false
  def get(table, key, scale) do
    window = div(now(), scale)
    full_key = {key, window}

    case :ets.lookup(table, full_key) do
      [{_full_key, count, _expires_at}] -> count
      [] -> 0
    end
  end

  @impl GenServer
  def init(opts) do
    clean_period = Keyword.fetch!(opts, :clean_period)
    table = Keyword.fetch!(opts, :table)
    {:continue, {:init, %{table: table, clean_period: clean_period}}
  end

  # TODO retry and log errors
  @impl GenServer
  def handle_continue(:init, state) do
    :ets.new(state.table, [
      :named_table,
      :set,
      :public,
      {:read_concurrency, true},
      {:write_concurrency, true},
      {:decentralized_counters, true}
    ])

    schedule(state.clean_period)
    {:ok, state}
  end

  @impl GenServer
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
