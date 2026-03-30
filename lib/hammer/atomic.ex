defmodule Hammer.Atomic do
  @moduledoc """
  A rate limiter implementation using Erlang's :atomics module for atomic counters.

  This provides fast, atomic counter operations without the overhead of ETS or process messaging.
  Requires Erlang/OTP 21.2 or later.

      defmodule MyApp.RateLimit do
        use Hammer, backend: :atomic
      end

      MyApp.RateLimit.start_link(clean_period: :timer.minutes(1))

      # Allow 10 requests per second
      MyApp.RateLimit.hit("user_123", 1000, 10)

  Runtime configuration:
  - `:clean_period` - (in milliseconds) period to clean up expired entries, defaults to 1 minute
  - `:key_older_than` - (in milliseconds) maximum age for entries before they are cleaned up, defaults to 24 hours
  - `:algorithm` - the rate limiting algorithm to use, one of: `:fix_window`, `:leaky_bucket`, `:token_bucket`. Defaults to `:fix_window`
  - `:before_clean` - optional callback invoked with expired entries before they are deleted.
    Accepts a function `(algorithm :: atom(), entries :: [map()]) -> any()` or an MFA tuple
    `{module, function, extra_args}`. Each entry is a map with `:key`, `:value`, and `:expired_at` (ms).
    If the callback raises, entries are still deleted and a warning is logged.

      MyApp.RateLimit.start_link(
        clean_period: :timer.minutes(1),
        key_older_than: :timer.hours(24),
        before_clean: fn algorithm, entries ->
          Enum.each(entries, fn entry ->
            MyApp.Telemetry.emit_expired(algorithm, entry)
          end)
        end
      )

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
          | {:before_clean, Hammer.CleanUtils.before_clean()}
          | GenServer.option()

  @type config :: %{
          table: atom(),
          table_opts: list(),
          clean_period: pos_integer(),
          key_older_than: pos_integer(),
          algorithm_module: module(),
          before_clean: Hammer.CleanUtils.before_clean() | nil
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

      if function_exported?(@algorithm, :expires_at, 3) do
        def expires_at(key, scale) do
          @algorithm.expires_at(@table, key, scale)
        end
      end
    end
  end

  @doc """
  Starts the atomic rate limiter process.

  Options:
  - `:clean_period` - How often to run cleanup (ms). Default 1 minute.
  - `:key_older_than` - Max age for entries (ms). Default 24 hours.
  - `:before_clean` - Optional callback invoked with expired entries before deletion.
    Accepts a function `(algorithm :: atom(), entries :: [map()]) -> any()` or an MFA tuple
    `{module, function, extra_args}`. Each entry is a map with `:key`, `:value`, and `:expired_at` (ms).
    If the callback raises, entries are still deleted and a warning is logged.
  """
  @spec start_link([start_option]) :: GenServer.on_start()
  def start_link(opts) do
    {gen_opts, opts} = Keyword.split(opts, [:debug, :spawn_opt, :hibernate_after])

    {clean_period, opts} = Keyword.pop!(opts, :clean_period)
    {table, opts} = Keyword.pop!(opts, :table)
    {algorithm_module, opts} = Keyword.pop!(opts, :algorithm_module)
    {key_older_than, opts} = Keyword.pop(opts, :key_older_than, :timer.hours(24))
    {before_clean, opts} = Keyword.pop(opts, :before_clean)

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
      algorithm_module: algorithm_module,
      before_clean: before_clean
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
    case config.algorithm_module do
      Hammer.Atomic.FixWindow -> clean_fix_window(config)
      _ -> clean_bucket(config)
    end

    schedule(config.clean_period)
    {:noreply, config}
  end

  # FixWindow stores expires_at in milliseconds in slot 2
  defp clean_fix_window(config) do
    now = now()
    algo_module = config.algorithm_module

    expired_terms =
      :ets.foldl(
        fn {_key, atomic} = term, acc ->
          expires_at = :atomics.get(atomic, 2)
          if now - expires_at > config.key_older_than, do: [term | acc], else: acc
        end,
        [],
        config.table
      )

    maybe_invoke_before_clean(config.before_clean, algo_module, expired_terms)
    Enum.each(expired_terms, fn term -> :ets.delete_object(config.table, term) end)
  end

  # TokenBucket and LeakyBucket store last_update in seconds in slot 2
  defp clean_bucket(config) do
    now = System.system_time(:second)
    older_than = now - div(config.key_older_than, 1000)
    algo_module = config.algorithm_module

    expired_terms =
      :ets.foldl(
        fn {_key, atomic} = term, acc ->
          last_update = :atomics.get(atomic, 2)
          if last_update < older_than, do: [term | acc], else: acc
        end,
        [],
        config.table
      )

    maybe_invoke_before_clean(config.before_clean, algo_module, expired_terms)
    Enum.each(expired_terms, fn term -> :ets.delete_object(config.table, term) end)
  end

  defp maybe_invoke_before_clean(nil, _algo_module, _expired_terms), do: :ok
  defp maybe_invoke_before_clean(_callback, _algo_module, []), do: :ok

  defp maybe_invoke_before_clean(callback, algo_module, expired_terms) do
    entries =
      Enum.map(expired_terms, fn {key, atomic} ->
        algo_module.normalize_entry(key, atomic)
      end)

    Hammer.CleanUtils.invoke_before_clean(callback, algorithm_name(algo_module), entries)
  end

  defp algorithm_name(Hammer.Atomic.FixWindow), do: :fix_window
  defp algorithm_name(Hammer.Atomic.TokenBucket), do: :token_bucket
  defp algorithm_name(Hammer.Atomic.LeakyBucket), do: :leaky_bucket

  defp schedule(clean_period) do
    Process.send_after(self(), :clean, clean_period)
  end
end
