defmodule Hammer do
  @moduledoc """
  Hammer is a rate-limiting library for Elixir.

  It provides a simple API for creating rate limiters, and comes with a built-in ETS backend.

      defmodule MyApp.RateLimit do
        use Hammer, backend: :ets
      end

      # Start the rate limiter, in case of ETS it will create the ETS table and schedule cleanups
      MyApp.RateLimit.start_link(clean_period: :timer.minutes(10))

      # Check the rate limit allowing 10 requests per second
      MyApp.RateLimit.check_rate("some-key", _scale = :timer.seconds(1), _limit = 10)

      # Wait for the next window
      MyApp.RateLimit.wait(_scale = :timer.seconds(1))

      # Reset the rate limiter
      MyApp.RateLimit.reset("some-key", _scale = :timer.seconds(1))

  """

  @type key :: term
  @type scale :: pos_integer
  @type limit :: pos_integer
  @type count :: pos_integer
  @type increment :: non_neg_integer

  @callback hit(key, scale, limit, increment) :: {:allow, count} | {:deny, timeout}
  @callback inc(key, scale, increment) :: count
  @callback set(key, scale, count) :: count
  @callback get(key, scale) :: count

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
      backend = with :ets <- backend, do: Hammer.ETS
      @before_compile backend

      def reset(key, scale), do: set(key, scale, 0)
    end
  end
end
