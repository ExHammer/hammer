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

  @callback check_rate(id :: String.t(), scale_ms :: pos_integer, limit :: pos_integer) ::
              {:allow, count :: pos_integer} | {:deny, limit :: pos_integer}

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Hammer

      {backend, config} = Keyword.pop!(opts, :backend)

      @backend backend
      @config config

      @before_compile backend

      def __backend__, do: @backend
    end
  end
end
