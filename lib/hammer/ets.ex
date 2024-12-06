defmodule Hammer.ETS do
  @moduledoc """
  An ETS backend for Hammer.

  To use the ETS backend, you need to start the process that creates and cleans the ETS table. The table is named after the module.

      defmodule MyApp.RateLimit do
        use Hammer, backend: :ets
      end

      MyApp.RateLimit.start_link(clean_period: :timer.minutes(1))

  Runtime configuration:
  - `:clean_period` - (in milliseconds) period to clean up expired entries, defaults to 1 minute
  """

  use GenServer
  require Logger

  defmacro __before_compile__(_env) do
    quote do
      @table __MODULE__

      def child_spec(opts) do
        %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, type: :worker}
      end

      def start_link(opts) do
        opts = Keyword.put(opts, :table, @table)
        opts = Keyword.put_new(opts, :clean_period, :timer.minutes(1))
        Hammer.ETS.start_link(opts)
      end

      @impl Hammer
      def hit(key, scale, limit, increment \\ 1) do
        Hammer.ETS.hit(@table, key, scale, limit, increment)
      end

      @impl Hammer
      def inc(key, scale, increment \\ 1) do
        Hammer.ETS.inc(@table, key, scale, increment)
      end

      @impl Hammer
      def set(key, scale, count) do
        Hammer.ETS.set(@table, key, scale, count)
      end

      @impl Hammer
      def get(key, scale) do
        Hammer.ETS.get(@table, key, scale)
      end
    end
  end

  @type start_option :: {:clean_period, timeout} | GenServer.option()

  @doc """
  Starts the process that creates and cleans the ETS table.

  Accepts the following options:
    - `:clean_period` for how often to perform garbage collection
    - optional `:debug`, `:spawn_opts`, and `:hibernate_after` GenServer options
  """
  @spec start_link([start_option]) :: GenServer.on_start()
  def start_link(opts) do
    {gen_opts, opts} = Keyword.split(opts, [:debug, :spawn_opt, :hibernate_after])

    {clean_period, opts} = Keyword.pop!(opts, :clean_period)
    {table, opts} = Keyword.pop!(opts, :table)

    case opts do
      [] ->
        :ok

      _ ->
        Logger.warning(
          "Unrecognized options passed to #{inspect(table)}.start_link/1: #{inspect(opts)}"
        )
    end

    config = %{table: table, clean_period: clean_period}
    GenServer.start_link(__MODULE__, config, gen_opts)
  end

  @doc false
  @spec hit(
          table :: atom(),
          key :: String.t(),
          scale :: integer(),
          limit :: integer(),
          increment :: integer()
        ) :: {:allow, integer()} | {:deny, integer()}
  def hit(table, key, scale, limit, increment) do
    now = now()
    window = div(now, scale)
    full_key = {key, window}
    expires_at = (window + 1) * scale
    count = update_counter(table, full_key, increment, expires_at)

    if count <= limit do
      {:allow, count}
    else
      {:deny, expires_at - now}
    end
  end

  @doc false
  @spec inc(table :: atom(), key :: String.t(), scale :: integer(), increment :: integer()) ::
          integer()
  def inc(table, key, scale, increment) do
    window = div(now(), scale)
    full_key = {key, window}
    expires_at = (window + 1) * scale
    update_counter(table, full_key, increment, expires_at)
  end

  @doc false
  @spec set(table :: atom(), key :: String.t(), scale :: integer(), count :: integer()) ::
          integer()
  def set(table, key, scale, count) do
    window = div(now(), scale)
    full_key = {key, window}
    expires_at = (window + 1) * scale
    update_counter(table, full_key, {2, 1, 0, count}, expires_at)
  end

  @doc false
  @spec get(table :: atom(), key :: String.t(), scale :: integer()) :: integer()
  def get(table, key, scale) do
    window = div(now(), scale)
    full_key = {key, window}

    case :ets.lookup(table, full_key) do
      [{_full_key, count, _expires_at}] -> count
      [] -> 0
    end
  end

  @compile inline: [update_counter: 4]
  defp update_counter(table, key, op, expires_at) do
    :ets.update_counter(table, key, op, {key, 0, expires_at})
  end

  @compile inline: [now: 0]
  defp now do
    System.system_time(:millisecond)
  end

  @impl GenServer
  def init(config) do
    :ets.new(config.table, [
      :named_table,
      :set,
      :public,
      {:read_concurrency, true},
      {:write_concurrency, true},
      {:decentralized_counters, true}
    ])

    schedule(config.clean_period)
    {:ok, config}
  end

  @impl GenServer
  def handle_info(:clean, config) do
    clean(config.table)
    schedule(config.clean_period)
    {:noreply, config}
  end

  defp schedule(clean_period) do
    Process.send_after(self(), :clean, clean_period)
  end

  defp clean(table) do
    ms = [{{{:_, :_}, :_, :"$1"}, [], [{:<, :"$1", {:const, now()}}]}]
    :ets.select_delete(table, ms)
  end
end
