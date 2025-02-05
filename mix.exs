defmodule Sensocto.MixProject do
  use Mix.Project

  def project do
    [
      app: :sensocto,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Sensocto.Application, []},
      # extra_applications: [:logger, :runtime_tools]
      extra_applications: [:logger, :runtime_tools, :os_mon]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:ash_admin, "~> 0.12"},
      {:bcrypt_elixir, "~> 3.0"},
      {:phoenix, "~> 1.7.12"},
      {:phoenix_ecto, "~> 4.4"},
      {:ecto_sql, "~> 3.10"},
      {:postgrex, "~> 0.19 or ~> 1.0"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      # {:phoenix_live_view, "~> 0.20.2"},
      {:phoenix_live_view, "~> 1.0.3"},
      {:floki, ">= 0.30.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      # {:esbuild, "~> 0.8.2"},
      # {:esbuild, github: "evanw/esbuild", branch: "main", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:ex_heroicons, "~> 3.1.0"},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.1.5",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.5"},
      {:hackney, "~> 1.20"},
      {:req, "~> 0.5.0"},
      {:finch, "~> 0.13"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26 and >= 0.26.1"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.1.1"},
      {:horde, "~> 0.8.5"},
      # {:libcluster, "~> 3.3"},
      {:bandit, "~> 1.2"},
      # {:bandit, "~> 1.0", github: "mtrudel/bandit", branch: "gc_on_websocket"}
      {:broadway, "~> 1.0"},
      {:broadway_dashboard, "~> 0.4.0"},
      # {:live_svelte, "~> 0.15.0-rc.6"},
      {:live_svelte, "~> 0.14.1"},
      # {:live_svelte, github: "woutdp/live_svelte", tag: "svelte-5"},
      # {:igniter, "~> 0.5", only: [:dev, :test]},
      # {:rewrite, "~> 1.1.1", only: [:dev], override: true},
      {:ash, "~> 3.0"},
      {:ash_authentication, "~> 4.4.1"},
      {:ash_authentication_phoenix, "~> 2.4.2"},
      {:ash_postgres, "~> 2.0.0"},
      {:picosat_elixir, "~> 0.2"},
      {:flex_logger, "~> 0.2.1"},
      {:dialyxir, "~> 0.4", only: [:dev]},
      {:sourceror, "~> 1.7", only: [:dev, :test]},
      {:nimble_csv, "~> 1.1", only: [:dev]},
      {:brotli, "~> 0.3.2", only: [:dev]},
      {:mishka_chelekom, "~> 0.0.2", only: :dev},
      {:timex, "~> 3.7"},
      {:kino, "~> 0.8.0", only: :dev},
      {:observer_cli, "~> 1.8"},
      {:exprof, "~> 0.2.4"},
      {:guarded_struct, "~> 0.0.4"}
      # {:recode, "~> 0.7", only: :dev, override: true}

      # {
      #   :recode,
      #   compile: true,
      #   app: true,
      #   github: "hrzndhrn/recode",
      #   branch: "rewrite-1-0-0",
      #   sparse: "optimized",
      #   depth: 1
      # }

      # {:sensocto_elixir_simulator, path: "./simulator/sensocto_elixir_simulator", app: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.

  defp aliases do
    [
      setup: [
        "deps.get",
        "ecto.setup",
        "cmd --cd assets npm install",
        "assets.setup",
        "assets.build"
      ],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing"],
      "assets.build": ["tailwind sensocto"],
      "assets.deploy": [
        "cmd --cd assets node build.js --deploy",
        "tailwind sensocto --minify",
        "phx.digest"
      ]
    ]
  end
end
