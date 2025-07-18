defmodule Hammer.MixProject do
  use Mix.Project

  @source_url "https://github.com/ExHammer/hammer"
  @version "7.1.0"

  def project do
    [
      app: :hammer,
      description: "A rate-limiter with plugable backends.",
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      test_coverage: [summary: [threshold: 90]]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:benchee, "~> 1.2", only: :bench},
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:ex_doc, "~> 0.34", only: :dev},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}

      # Keeping to perform benchmark test as needed at times
      # {:ex_rated, "~> 2.1", only: :bench},
      # {:plug_attack, "~> 0.4.3", only: :bench},
      # {:rate_limiter, "~> 0.4.0", only: :bench}
    ]
  end

  defp docs do
    [
      main: "readme",
      extra_section: "GUIDES",
      extras: ["CHANGELOG.md", "README.md"] ++ Path.wildcard("guides/*.md"),
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"],
      source_url: @source_url,
      source_ref: "v#{@version}",
      homepage_url: @source_url,
      assets: %{"assets" => "assets"}
    ]
  end

  defp package do
    [
      name: :hammer,
      maintainers: ["Emmanuel Pinault", "June Kelly (june@junek.xyz)"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/master/CHANGELOG.md"
      }
    ]
  end
end
