defmodule Hammer.ETS do
  @moduledoc """
  An ETS backend for Hammer.

  Configuration:
  - `:table` - (atom) name of the ETS table, defaults to the module name that called `use Hammer`
  - `:cleanup_period` - how often to run the cleanup process, in milliseconds, defaults to `:timer.seconds(60)`

  Example:

      defmodule MyApp.RateLimit do
        # these are the defaults
        use Hammer, backend: :ets, table: MyApp.RateLimit, cleanup_period: :timer.seconds(60)
      end

  """
end
