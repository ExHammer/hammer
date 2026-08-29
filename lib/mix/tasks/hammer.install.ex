defmodule Mix.Tasks.Hammer.Install.Docs do
  @moduledoc false

  @spec short_doc() :: String.t()
  def short_doc do
    "Installs Hammer: generates a rate limiter module and adds it to the supervision tree"
  end

  @spec example() :: String.t()
  def example do
    "mix hammer.install --backend ets"
  end

  @spec long_doc() :: String.t()
  def long_doc do
    """
    #{short_doc()}

    Generates `MyApp.RateLimit` (`use Hammer, backend: ...`) and adds it as a child of
    the application supervisor. Hammer has no global configuration: limits are defined at
    each call site with `MyApp.RateLimit.hit(key, scale, limit)`, so after installing,
    see the Hammer tutorial for how to compose keys and wire the limiter into a plug.

    ## Example

    ```sh
    #{example()}
    ```

    ## Options

    * `--backend` or `-b` - The backend to use. One of `ets` (default), `atomic` or `redis`.
      `redis` also adds the `hammer_backend_redis` dependency.
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Hammer.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"

    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    alias Igniter.Project.Deps

    @backends ~w(ets atomic redis)
    @redis_dep {:hammer_backend_redis, "~> 7.0"}

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :hammer,
        example: __MODULE__.Docs.example(),
        only: nil,
        schema: [backend: :string],
        defaults: [backend: "ets"],
        aliases: [b: :backend]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      backend = igniter.args.options[:backend]

      if backend in @backends do
        install(igniter, backend)
      else
        Igniter.add_issue(
          igniter,
          "Unknown backend #{inspect(backend)} for `mix hammer.install`. " <>
            "Expected one of: #{Enum.join(@backends, ", ")}."
        )
      end
    end

    defp install(igniter, backend) do
      module = Igniter.Project.Module.module_name(igniter, "RateLimit")
      app_module = Igniter.Project.Module.module_name_prefix(igniter)

      igniter
      |> add_backend_dep(backend)
      |> Igniter.Project.Module.find_and_update_or_create_module(
        module,
        module_body(app_module, module, backend),
        &{:ok, &1}
      )
      |> Igniter.Project.Application.add_new_child({module, child_opts(backend)})
    end

    defp add_backend_dep(igniter, "redis"),
      do: Deps.add_dep(igniter, @redis_dep, on_exists: :skip)

    defp add_backend_dep(igniter, _backend), do: igniter

    defp module_body(app_module, module, backend) do
      """
      @moduledoc \"\"\"
      Rate limiter for #{inspect(app_module)}, backed by `#{backend_option(backend)}`.

      Check and increment a limit with `hit/3`, for example allowing 10 requests per second:

          #{inspect(module)}.hit("some-key", :timer.seconds(1), 10)

      See `Hammer` for the full API and the Hammer tutorial for usage patterns.
      \"\"\"

      use Hammer, backend: #{backend_option(backend)}
      """
    end

    defp backend_option("ets"), do: ":ets"
    defp backend_option("atomic"), do: ":atomic"
    defp backend_option("redis"), do: "Hammer.Redis"

    defp child_opts("redis"), do: [url: "redis://localhost:6379"]

    defp child_opts(_backend) do
      {:code, quote(do: [clean_period: :timer.minutes(1)])}
    end
  end
else
  defmodule Mix.Tasks.Hammer.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"

    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'hammer.install' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
