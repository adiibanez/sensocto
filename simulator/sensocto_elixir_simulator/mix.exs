defmodule SensoctoElixirSimulator.MixProject do
  use Mix.Project

  def project do
    [
      app: :sensocto_elixir_simulator,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Sensocto.Simulator.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:phoenix_client, "~> 0.11.1"},
      {:phoenix_pubsub, "~> 2.1"},
      {:jason, "~> 1.4"},
      {:nimble_csv, "~> 1.1"},
      {:kino, "~> 0.12.0"},
      {:uuid, "~> 1.1"},
      # , only: :dev
      {:mock, "~> 0.3.9"},
      {:flex_logger, "~> 0.2.1"},
      {:sourceror, "~> 1.7", only: [:dev, :test]}

      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
