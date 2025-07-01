defmodule Hammer do
  @moduledoc """
  Hammer is a rate-limiting library for Elixir.

  It provides a simple way for creating rate limiters, and comes with a built-in ETS backend.

      defmodule MyApp.RateLimit do
        use Hammer, backend: :ets
      end

      # Start the rate limiter, in case of ETS it will create the ETS table and schedule cleanups
      MyApp.RateLimit.start_link(clean_period: :timer.minutes(10))

      # Check the rate limit allowing 10 requests per second
      MyApp.RateLimit.hit("some-key", _scale = :timer.seconds(1), _limit = 10)
  """

  @type key :: term
  @type scale :: pos_integer
  @type limit :: pos_integer
  @type count :: pos_integer
  @type increment :: non_neg_integer

  @doc """
  Checks if a key is allowed to perform an action, and increment the counter.

  Same as `hit/4` with `increment` set to 1.
  """
  @callback hit(key, scale, limit) :: {:allow, count} | {:deny, timeout}

  @doc """
  Optional callback to check if a key is allowed to perform an action, and increment the counter.

  Returns `{:allow, count}` if the action is allowed, or `{:deny, timeout}` if the action is denied.

  This is the only required callback.
  """
  @callback hit(key, scale, limit, increment) :: {:allow, count} | {:deny, timeout}

  @doc """
  Same as `inc/3` with `increment` set to 1.
  """
  @callback inc(key, scale) :: count

  @doc """
  Optional callback for incrementing a counter value for a key without performing limit check.

  Returns the new counter value.
  """
  @callback inc(key, scale, increment) :: count

  @doc """
  Optional callback for setting the counter value for a key.

  Returns the new counter value.
  """
  @callback set(key, scale, count) :: count

  @doc """
  Optional callback for getting the counter value for a key.

  Returns the current counter value.
  """
  @callback get(key, scale) :: count

  @optional_callbacks hit: 4, inc: 2, inc: 3, set: 3, get: 2

  @doc """
  Use the Hammer library in a module to create a rate limiter.

      defmodule MyApp.RateLimit do
        use Hammer, backend: :ets
      end

  """
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Hammer
      @hammer_opts opts

      backend =
        Keyword.get(opts, :backend) ||
          raise ArgumentError, """
          Hammer requires a backend to be specified. Example:

              use Hammer, backend: :ets
          """

      # this allows :ets to be aliased to Hammer.ETS
      backend =
        case backend do
          :ets -> Hammer.ETS
          :atomic -> Hammer.Atomic
          backend -> backend
        end

      @before_compile backend
    end
  end
end
