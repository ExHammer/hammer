defmodule Hammer.Mixfile do
  use Mix.Project

  def project do
    [app: :hammer,
     description: "A rate-limiter with plugable backends."
     package: [name: :hammer,
               maintainers: ["Shane Kilkelly (shane@kilkelly.me)"],
               licenses: ["MIT"],
               links: %{"GitHub" => "https://github.com/ExHammer/hammer"}]
     source_url: "https://github.com/ExHammer/hammer",
     homepage_url: "https://github.com/ExHammer/hammer",
     version: "0.1.0",
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps(),
     docs: [main: "frontpage",
            extras: ["doc_src/Frontpage.md",
                     "doc_src/Tutorial.md",
                     "doc_src/CreatingBackends.md"]]]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    []
  end

  # Dependencies can be Hex packages:
  #
  #   {:my_dep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:my_dep, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [{:ex_doc, "~> 0.16", only: :dev},
     {:dialyxir, "~> 0.5", only: [:dev], runtime: false}]
  end
end
