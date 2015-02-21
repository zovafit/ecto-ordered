defmodule EctoOrdered.Mixfile do
  use Mix.Project

  def project do
    [app: :ecto_ordered,
     version: "0.0.2",
     elixir: "~> 1.0",
     description: "Ecto extension to support ordered list models",
     package: package,
     deps: deps]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [applications: [:logger, :ecto]]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type `mix help deps` for more examples and options
  defp deps do
    [
     {:ecto, "~> 0.8.1"},
     {:postgrex, "~> 0.7.0", only: :test},
    ]
  end

  defp package do
    [
      files: ["lib", "priv", "mix.exs", "README*", "readme*", "LICENSE*", "license*"],
      contributors: ["Yurii Rashkovskii"],
      licenses: ["Apache 2.0"],
      links: %{"GitHub" => "https://github.com/trustatom-oss/ecto-ordered"}
    ]
  end
end
