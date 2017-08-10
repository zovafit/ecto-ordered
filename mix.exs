defmodule EctoOrdered.Mixfile do
  use Mix.Project

  def project do
    [app: :ecto_ordered,
     version: "0.2.0-beta1",
     elixir: "~> 1.0",
     description: "Ecto extension to support ordered list models",
     elixirc_paths: path(Mix.env),
     package: package(),
     deps: deps()]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [applications: [:logger] ++ app_list(Mix.env)]
  end


  defp app_list(:test) do
    [:ecto, :postgrex]
  end

  defp app_list(_) do
    [:ecto]
  end

  defp path(:test) do
    ["lib", "test/support", "test/fixtures"]
  end
  defp path(_), do: ["lib"]


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
     {:ecto, "~> 2.1"},
     {:postgrex, "~> 0.13.0", only: :test},
     {:credo, "~> 0.3", only: [:dev, :test]},
     {:ex_doc, "~> 0.11.4", only: :dev},
     {:earmark, ">= 0.0.0", only: :dev}
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README*"],
      contributors: ["Yurii Rashkovskii", "Andrew Harvey"],
      maintainers: ["Andrew Harvey"],
      licenses: ["Apache 2.0"],
      links: %{"GitHub" => "https://github.com/trustatom-oss/ecto-ordered"}
    ]
  end
end
