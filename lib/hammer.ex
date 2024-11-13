defmodule Hammer do
  @moduledoc """
  Hammer is a rate-limiting library for Elixir.

  It provides a simple API for creating rate limiters, and comes with a built-in ETS backend.

      defmodule MyApp.RateLimit do
        use Hammer, backend: :ets
      end

      # Start the rate limiter, in case of ETS it will create the ETS table and schedule the cleanup
      MyApp.RateLimit.start_link()

      # Allow 10 requests per second
      MyApp.RateLimit.check_rate("some-key", _scale_ms = 1000, _limit = 10)

  """

  @type key :: term
  @type scale :: pos_integer
  @type limit :: pos_integer
  @type count :: pos_integer
  @type increment :: non_neg_integer

  @callback hit(key, scale, increment) :: count
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

      def check_rate(key, scale, limit, increment \\ 1) do
        count = hit(key, scale, increment)
        if count <= limit, do: {:allow, count}, else: {:deny, limit}
      end

      def reset(key, scale), do: set(key, scale, 0)
    end
  end
end
