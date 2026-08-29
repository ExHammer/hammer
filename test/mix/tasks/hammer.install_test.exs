defmodule Mix.Tasks.Hammer.InstallTest do
  use ExUnit.Case, async: true
  import Igniter.Test

  alias Igniter.Project.Deps

  @mix_exs """
  defmodule Test.MixProject do
    use Mix.Project

    def project do
      [
        app: :test,
        version: "0.1.0",
        elixir: "~> 1.17",
        start_permanent: Mix.env() == :prod,
        deps: deps()
      ]
    end

    def application do
      [
        extra_applications: [:logger],
        mod: {Test.Application, []}
      ]
    end

    defp deps do
      [
        {:hammer, "~> 7.0"}
      ]
    end
  end
  """

  @application """
  defmodule Test.Application do
    use Application

    def start(_type, _args) do
      children = [
        TestWeb.Endpoint
      ]

      Supervisor.start_link(children, strategy: :one_for_one, name: Test.Supervisor)
    end
  end
  """

  defp project do
    test_project(files: %{"mix.exs" => @mix_exs, "lib/test/application.ex" => @application})
  end

  defp rate_limit_module(backend) do
    """
    defmodule Test.RateLimit do
      @moduledoc \"\"\"
      Rate limiter for Test, backed by `#{backend}`.

      Check and increment a limit with `hit/3`, for example allowing 10 requests per second:

          Test.RateLimit.hit("some-key", :timer.seconds(1), 10)

      See `Hammer` for the full API and the Hammer tutorial for usage patterns.
      \"\"\"

      use Hammer, backend: #{backend}
    end
    """
  end

  describe "default (ets) backend" do
    test "creates the rate limiter module" do
      project()
      |> Igniter.compose_task("hammer.install", [])
      |> assert_creates("lib/test/rate_limit.ex", rate_limit_module(":ets"))
    end

    test "adds the rate limiter to the supervision tree" do
      project()
      |> Igniter.compose_task("hammer.install", [])
      |> assert_has_patch("lib/test/application.ex", """
      + |    {Test.RateLimit, [clean_period: :timer.minutes(1)]},
      """)
    end

    test "does not add any extra dependency" do
      project()
      |> Igniter.compose_task("hammer.install", [])
      |> assert_unchanged("mix.exs")
    end
  end

  describe "atomic backend" do
    test "generates the module and child spec with the atomic backend" do
      project()
      |> Igniter.compose_task("hammer.install", ["--backend", "atomic"])
      |> assert_creates("lib/test/rate_limit.ex", rate_limit_module(":atomic"))
      |> assert_has_patch("lib/test/application.ex", """
      + |    {Test.RateLimit, [clean_period: :timer.minutes(1)]},
      """)
      |> assert_unchanged("mix.exs")
    end
  end

  describe "redis backend" do
    test "adds the hammer_backend_redis dependency" do
      project()
      |> Igniter.compose_task("hammer.install", ["-b", "redis"])
      |> assert_has_patch("mix.exs", """
      + |      {:hammer_backend_redis, "~> 7.0"},
      """)
    end

    test "does not duplicate an existing hammer_backend_redis dependency" do
      project()
      |> Deps.add_dep({:hammer_backend_redis, "~> 7.1"})
      |> apply_igniter!()
      |> Igniter.compose_task("hammer.install", ["--backend", "redis"])
      |> assert_unchanged("mix.exs")
    end

    test "generates the module with the Redis backend" do
      project()
      |> Igniter.compose_task("hammer.install", ["--backend", "redis"])
      |> assert_creates("lib/test/rate_limit.ex", rate_limit_module("Hammer.Redis"))
    end

    test "starts the rate limiter with a Redis url" do
      project()
      |> Igniter.compose_task("hammer.install", ["--backend", "redis"])
      |> assert_has_patch("lib/test/application.ex", """
      + |    {Test.RateLimit, [url: "redis://localhost:6379"]},
      """)
    end
  end

  test "rejects an unknown backend" do
    project()
    |> Igniter.compose_task("hammer.install", ["--backend", "mnesia"])
    |> assert_has_issue(
      "Unknown backend \"mnesia\" for `mix hammer.install`. Expected one of: ets, atomic, redis."
    )
    |> refute_creates("lib/test/rate_limit.ex")
    |> assert_unchanged("lib/test/application.ex")
  end

  test "is idempotent when the rate limiter already exists" do
    project()
    |> Igniter.compose_task("hammer.install", [])
    |> apply_igniter!()
    |> Igniter.compose_task("hammer.install", [])
    |> assert_unchanged()
  end
end
