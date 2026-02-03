defmodule Hammer.Atomic do
  @moduledoc """
  A rate limiter implementation using Erlang's :atomics module for atomic counters.

  This provides fast, atomic counter operations without the overhead of ETS or process messaging.
  Requires Erlang/OTP 21.2 or later.

  The atomic backend supports the following algorithms:

  - `:fix_window` - Fixed window rate limiting (default)
    Simple counting within fixed time windows. See [Hammer.Atomic.FixWindow](Hammer.Atomic.FixWindow.html) for more details.

  - `:leaky_bucket` - Leaky bucket rate limiting
    Smooth rate limiting with a fixed rate of tokens. See [Hammer.Atomic.LeakyBucket](Hammer.Atomic.LeakyBucket.html) for more details.

  - `:token_bucket` - Token bucket rate limiting
    Flexible rate limiting with bursting capability. See [Hammer.Atomic.TokenBucket](Hammer.Atomic.TokenBucket.html) for more details.
  """

  use GenServer
  require Logger

  @type start_option ::
          {:clean_period, pos_integer()}
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
          Hammer.Atomic.FixWindow

        :atomic ->
          Hammer.Atomic.FixWindow

        :fix_window ->
          Hammer.Atomic.FixWindow

        :sliding_window ->
          Hammer.Atomic.SlidingWindow

        :leaky_bucket ->
          Hammer.Atomic.LeakyBucket

        :token_bucket ->
          Hammer.Atomic.TokenBucket

        _module ->
          raise ArgumentError, """
          Hammer requires a valid backend to be specified. Must be one of: :atomic, :fix_window, :sliding_window, :leaky_bucket, :token_bucket.
          If none is specified, :fix_window is used.

          Example:

            use Hammer, backend: :atomic
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
        opts = Keyword.put_new(opts, :algorithm_module, @algorithm)
        Hammer.Atomic.start_link(opts)
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
  Starts the atomic rate limiter process.

  Options:
  - `:clean_period` - How often to run cleanup (ms). Default 1 minute.
  - `:key_older_than` - Max age for entries (ms). Default 24 hours.
  """
  @spec start_link([start_option]) :: GenServer.on_start()
  def start_link(opts) do
    {gen_opts, opts} = Keyword.split(opts, [:debug, :spawn_opt, :hibernate_after])

    {clean_period, opts} = Keyword.pop!(opts, :clean_period)
    {table, opts} = Keyword.pop!(opts, :table)
    {algorithm_module, opts} = Keyword.pop!(opts, :algorithm_module)
    {key_older_than, opts} = Keyword.pop(opts, :key_older_than, :timer.hours(24))

    case opts do
      [] ->
        :ok

      _ ->
        Logger.warning(
          "Unrecognized options passed to Hammer.Atomic.start_link/1: #{inspect(opts)}"
        )
    end

    config = %{
      table: table,
      table_opts: algorithm_module.ets_opts(),
      clean_period: clean_period,
      key_older_than: key_older_than,
      algorithm_module: algorithm_module
    }

    GenServer.start_link(__MODULE__, config, gen_opts)
  end

  @impl GenServer
  def init(config) do
    :ets.new(config.table, config.table_opts)

    schedule(config.clean_period)
    {:ok, config}
  end

  @doc """
  Returns the current time in milliseconds.
  """
  @spec now() :: pos_integer()
  @compile inline: [now: 0]
  def now do
    System.system_time(:millisecond)
  end

  @impl GenServer
  def handle_info(:clean, config) do
    clean(config)

    schedule(config.clean_period)
    {:noreply, config}
  end

  defp clean(config) do
    table = config.table

    now = now()

    :ets.foldl(
      fn {_key, atomic} = term, deleted ->
        expires_at = :atomics.get(atomic, 2)

        if now - expires_at > config.key_older_than do
          :ets.delete_object(table, term)
          deleted + 1
        else
          deleted
        end
      end,
      0,
      table
    )
  end

  defp schedule(clean_period) do
    Process.send_after(self(), :clean, clean_period)
  end
end
