defmodule Hammer.ETS do
  @moduledoc """
  An ETS backend for Hammer.

  To use the ETS backend, you need to start the process that creates and cleans the ETS table. The table is named after the module.

      defmodule MyApp.RateLimit do
        use Hammer, backend: :ets
      end

      MyApp.RateLimit.start_link(clean_period: :timer.minutes(1))

      # Allow 10 requests per second
      MyApp.RateLimit.hit("user_123", 1000, 10)

  Runtime configuration:
  - `:clean_period` - (in milliseconds) period to clean up expired entries, defaults to 1 minute
  - `:key_older_than` - (in milliseconds) maximum age for entries before they are cleaned up, defaults to 1 hour
  - `:algorithm` - the rate limiting algorithm to use, one of: `:fix_window`, `:sliding_window`, `:leaky_bucket`, `:token_bucket`. Defaults to `:fix_window`

  The ETS backend supports the following algorithms:
    - `:fix_window` - Fixed window rate limiting (default)
      Simple counting within fixed time windows. See [Hammer.ETS.FixWindow](Hammer.ETS.FixWindow.html) for more details.

  - `:leaky_bucket` - Leaky bucket rate limiting
    Smooth rate limiting with a fixed rate of tokens. See [Hammer.ETS.LeakyBucket](Hammer.ETS.LeakyBucket.html) for more details.

  - `:token_bucket` - Token bucket rate limiting
    Flexible rate limiting with bursting capability. See [Hammer.ETS.TokenBucket](Hammer.ETS.TokenBucket.html) for more details.
  """

  use GenServer
  require Logger

  @type start_option ::
          {:clean_period, pos_integer()}
          | {:table, atom()}
          | {:algorithm, module()}
          | {:key_older_than, pos_integer()}
          | GenServer.option()

  @type config :: %{
          table: atom(),
          table_opts: list(),
          clean_period: pos_integer(),
          key_older_than: pos_integer(),
          algorithm: module()
        }

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defmacro __before_compile__(%{module: module}) do
    hammer_opts = Module.get_attribute(module, :hammer_opts)

    algorithm =
      case Keyword.get(hammer_opts, :algorithm) do
        nil ->
          Hammer.ETS.FixWindow

        :ets ->
          Hammer.ETS.FixWindow

        :fix_window ->
          Hammer.ETS.FixWindow

        :sliding_window ->
          Hammer.ETS.SlidingWindow

        :leaky_bucket ->
          Hammer.ETS.LeakyBucket

        :token_bucket ->
          Hammer.ETS.TokenBucket

        _module ->
          raise ArgumentError, """
          Hammer requires a valid backend to be specified. Must be one of: :ets,:fix_window, :sliding_window, :leaky_bucket, :token_bucket.
          If none is specified, :fix_window is used.

          Example:

            use Hammer, backend: :ets
          """
      end

    Code.ensure_loaded!(algorithm)

    quote do
      @table __MODULE__
      @algorithm unquote(algorithm)

      def child_spec(opts) do
        %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, type: :worker}
      end

      def start_link(opts) do
        opts = Keyword.put(opts, :table, @table)
        opts = Keyword.put_new(opts, :clean_period, :timer.minutes(1))
        opts = Keyword.put_new(opts, :algorithm, @algorithm)
        Hammer.ETS.start_link(opts)
      end

      if function_exported?(@algorithm, :hit, 4) do
        def hit(key, scale, limit) do
          @algorithm.hit(@table, key, scale, limit)
        end
      end

      if function_exported?(@algorithm, :hit, 5) do
        def hit(key, scale, limit, increment \\ 1) do
          @algorithm.hit(@table, key, scale, limit, increment)
        end
      end

      if function_exported?(@algorithm, :inc, 4) do
        def inc(key, scale, increment \\ 1) do
          @algorithm.inc(@table, key, scale, increment)
        end
      end

      if function_exported?(@algorithm, :set, 4) do
        def set(key, scale, count) do
          @algorithm.set(@table, key, scale, count)
        end
      end

      if function_exported?(@algorithm, :get, 3) do
        def get(key, scale) do
          @algorithm.get(@table, key, scale)
        end
      end

      if function_exported?(@algorithm, :get, 2) do
        def get(key, scale) do
          @algorithm.get(@table, key)
        end
      end
    end
  end

  @doc """
  Starts the process that creates and cleans the ETS table.

  Accepts the following options:
    - `:clean_period` - How often to run the cleanup process (in milliseconds). Defaults to 1 minute.
    - `:key_older_than` - Optional maximum age for bucket entries (in milliseconds). Defaults to 24 hours.
      Entries older than this will be removed during cleanup.
    - optional `:debug`, `:spawn_opts`, and `:hibernate_after` GenServer options
  """
  @spec start_link([start_option]) :: GenServer.on_start()
  def start_link(opts) do
    {gen_opts, opts} = Keyword.split(opts, [:debug, :spawn_opt, :hibernate_after])

    {clean_period, opts} = Keyword.pop!(opts, :clean_period)
    {table, opts} = Keyword.pop!(opts, :table)
    {algorithm, opts} = Keyword.pop!(opts, :algorithm)
    {key_older_than, opts} = Keyword.pop(opts, :key_older_than, :timer.hours(24))

    case opts do
      [] ->
        :ok

      _ ->
        Logger.warning(
          "Unrecognized options passed to #{inspect(table)}.start_link/1: #{inspect(opts)}"
        )
    end

    config = %{
      table: table,
      table_opts: algorithm.ets_opts(),
      clean_period: clean_period,
      key_older_than: key_older_than,
      algorithm: algorithm
    }

    GenServer.start_link(__MODULE__, config, gen_opts)
  end

  @compile inline: [update_counter: 4]
  def update_counter(table, key, op, expires_at) do
    :ets.update_counter(table, key, op, {key, 0, expires_at})
  end

  @compile inline: [now: 0]
  @spec now() :: pos_integer()
  def now do
    System.system_time(:millisecond)
  end

  @impl GenServer
  def init(config) do
    :ets.new(config.table, config.table_opts)

    schedule(config.clean_period)
    {:ok, config}
  end

  @impl GenServer
  def handle_info(:clean, config) do
    algorithm = config.algorithm
    algorithm.clean(config)
    schedule(config.clean_period)
    {:noreply, config}
  end

  defp schedule(clean_period) do
    Process.send_after(self(), :clean, clean_period)
  end
end
