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

  @callback check_rate(
              id :: String.t(),
              scale_ms :: pos_integer,
              limit :: pos_integer,
              increment :: integer
            ) ::
              {:allow, count :: pos_integer} | {:deny, limit :: pos_integer}

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Hammer

      @backend Keyword.get(opts, :backend, Hammer.ETS)
      @config @backend.__config__(__MODULE__, opts)

      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [opts]},
          type: :worker
        }
      end

      def start_link(opts \\ []) do
        @backend.start_link(@config, opts)
      end

      def check_rate(id, scale_ms, limit) do
        @backend.check_rate(@config, id, scale_ms, limit)
      end

      def check_rate(id, scale_ms, limit, increment) do
        @backend.check_rate(@config, id, scale_ms, limit, increment)
      end
    end
  end
end
