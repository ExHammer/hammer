defmodule Hammer.Mixfile do
  use Mix.Project

  @source_url "https://github.com/ExHammer/hammer"
  @version "6.1.0"

  def project do
    [
      app: :hammer,
      description: "A rate-limiter with plugable backends.",
      version: @version,
      elixir: "~> 1.6",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      test_coverage: [summary: [threshold: 70]]
    ]
  end

  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    [mod: {Hammer.Application, []}, extra_applications: [:logger, :runtime_tools]]
  end

  defp deps do
    [
      {:credo, "~> 1.6", only: [:dev, :test]},
      {:ex_doc, "~> 0.28", only: :dev},
      {:dialyxir, "~> 1.1", only: [:dev, :test], runtime: false},
      {:poolboy, "~> 1.5"}
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

  defp package do
    [
      name: :hammer,
      maintainers: ["Emmanuel Pinault", "Shane Kilkelly (shane@kilkelly.me)"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/master/CHANGELOG.md"
      }
    ]
  end
end
