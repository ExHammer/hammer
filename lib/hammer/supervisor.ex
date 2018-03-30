defmodule Hammer.Supervisor do
  @moduledoc """
  Top-level Supervisor for the Hammer application.
  Starts a set of poolboy pools based on provided configuration,
  which are latter called to by the `Hammer` module.
  See the Application module for configuration examples.
  """

  use Supervisor

  def start_link(config, opts) do
    Supervisor.start_link(__MODULE__, config, opts)
  end

  # Single backend
  def init(config) when is_tuple(config) do
    children = [
      to_pool_spec(:hammer_backend_single_pool, config)
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # Multiple backends
  def init(config) when is_list(config) do
    children =
      config
      |> Enum.map(fn {k, c} -> to_pool_spec(:"hammer_backend_#{k}_pool", c) end)

    Supervisor.init(children, strategy: :one_for_one)
  end

  # Private helpers
  defp to_pool_spec(name, {mod, args}) do
    opts = [
      name: {:local, name},
      worker_module: mod,
      size: 4,
      max_overflow: 4
    ]

    :poolboy.child_spec(name, opts, args)
  end
end
