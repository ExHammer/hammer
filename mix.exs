defmodule Hammer.Mixfile do
  use Mix.Project

  @source_url "https://github.com/ExHammer/hammer"
  @version "6.1.0"

  def project do
    [
      app: :hammer,
      description: "A rate-limiter with plugable backends.",
      package: package(),
      version: @version,
      elixir: "~> 1.6",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    [mod: {Hammer.Application, []}, extra_applications: [:logger, :runtime_tools]]
  end

  defp package do
    [
      name: :hammer,
      maintainers: ["Shane Kilkelly (shane@kilkelly.me)"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp deps do
    [
      {:poolboy, "~> 1.5"},
      {:ex_doc, "~> 0.28", only: :dev},
      {:dialyxir, "~> 1.1", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.14", only: :test}
    ]
  end

  defp docs do
    [
      main: "readme",
      extra_section: "GUIDES",
      extras: [
        "CHANGELOG.md",
        {:"README.md", title: "Readme"},
        {:"guides/Frontpage.md", title: "Overview"},
        "guides/Tutorial.md",
        "guides/CreatingBackends.md"
      ],
      source_url: @source_url,
      source_ref: "v#{@version}",
      homepage_url: @source_url,
      assets: "assets"
    ]
  end
end
