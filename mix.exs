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
      deps: deps(),
      listeners: [Phoenix.CodeReloader]
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
      {:claude, "~> 0.5", only: [:dev], runtime: false},
      {:ash_admin, "~> 0.12"},
      {:bcrypt_elixir, "~> 3.0"},
      {:phoenix, "~> 1.7"},
      {:phoenix_ecto, "~> 4.4"},
      {:ecto_sql, "~> 3.10"},
      {:postgrex, "~> 0.19 or ~> 1.0"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      # {:phoenix_live_view, "~> 0.20.2"},
      {:phoenix_live_view, "~> 1.0", override: true},
      {:floki, ">= 0.30.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      # LVN_ACTIVATION {:live_view_native, "~> 0.4.0-rc.1"},
      # LVN_ACTIVATION {:live_view_native_stylesheet, "~> 0.4.0-rc.1"},
      # LVN_ACTIVATION {:live_view_native_swiftui, "~> 0.4.0-rc.1"},
      # LVN_ACTIVATION {:live_view_native_live_form, "~> 0.4.0-rc.1"},
      # Video/Voice calling with Membrane RTC Engine (using ex_webrtc - pure Elixir)
      {:membrane_rtc_engine, "~> 0.25.0"},
      {:membrane_rtc_engine_ex_webrtc, "~> 0.2.0"},
      {:flame, "~> 0.5"},
      # {:esbuild, "~> 0.8.2"},
      # {:esbuild, github: "evanw/esbuild", branch: "main", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2 or ~> 0.3 or ~> 0.4", runtime: Mix.env() == :dev},
      {:ex_heroicons, "~> 3.1.0"},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.1.5",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:iconify_ex, "~> 0.6.1"},
      {:swoosh, "~> 1.5"},
      {:hackney, "~> 1.20"},
      {:req, "~> 0.5.0"},
      {:finch, "~> 0.13"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26 or ~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.1 or ~> 0.2"},
      {:horde, "~> 0.9 or ~> 0.10"},
      # {:libcluster, "~> 3.3"},
      {:bandit, "~> 1.2"},
      # {:bandit, "~> 1.0", github: "mtrudel/bandit", branch: "gc_on_websocket"}
      # {:broadway, "~> 1.0"},
      # {:broadway_dashboard, "~> 0.4.0"},
      # {:live_svelte, "~> 0.15.0-rc.6"},
      # ~> 0.14.1"},
      {:live_svelte, "~> 0.14 or ~> 0.15 or ~> 0.16"},

      # {:live_svelte, github: "woutdp/live_svelte"},
      # {:live_svelte, github: "woutdp/live_svelte", tag: "svelte-5"},
      # {:igniter, "~> 0.5", only: [:dev, :test]},
      # {:rewrite, "~> 1.1.1", only: [:dev], override: true},
      {:ash, "~> 3.0"},
      {:ash_authentication, "~> 4.5"},
      {:ash_authentication_phoenix, "~> 2.4"},
      {:ash_postgres, "~> 2.5"},
      # {:cozodb, git: "https://github.com/leapsight/cozodb.git", branch: "master"},
      # {:cozodb, git: "https://github.com/Leapsight/cozodb.git", tag: "0.2.9"},
      {:ash_ops, "~> 0.2.3"},
      {:picosat_elixir, "~> 0.2"},
      # {:flex_logger, "~> 0.2.1"},
      {:flex_logger, git: "https://github.com/adiibanez/elixir-flex-logger"},
      {:dialyxir, "~> 1.4", only: [:dev]},
      # only: [:dev, :test]
      {:sourceror, "~> 1.7 or ~> 1.8 or ~> 1.9 or ~> 1.10", override: true},
      {:nimble_csv, "~> 1.1"},
      {:yaml_elixir, "~> 2.11"},
      # {:brotli, "~> 0.3.2", only: [:dev]},
      {:mishka_chelekom, "~> 0.0.2", only: :dev},
      {:daisy_ui_components, "~> 0.7"},
      {:timex, "~> 3.7"},
      # {:kino, "~> 0.8.0", only: :dev},
      # {:kino, github: "adiibanez/kino", only: :dev},
      # {:kino,
      # local: "/Users/adrianibanez/Documents/projects/2024_sensor-platform/checkouts/kino"},
      # {:mix_install_watcher, "~> 0.1.0"},
      {:observer_cli, "~> 1.8", only: :dev},
      # {:exprof, "~> 0.2.4"},
      # {:guarded_struct, "~> 0.0.4"},
      # {:live_debugger,
#        git: "https://github.com/software-mansion-labs/live-debugger.git",
#        tag: "v0.5.0",
# only: :dev},
      # {:qr_code, "~> 3.1.0"},
      {:nx, "~> 0.9 or ~> 0.10", override: true},
      # {:matplotex, "~> 0.4.6"},
      # {:stream_data, "~> 1.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:machete, "~> 0.3.10", only: [:dev, :test], runtime: false},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:wallaby, "~> 0.30", only: :test, runtime: false},
      {:exacto_knife, "~> 0.1.5", only: [:dev, :test], runtime: false},
      # {:bridge,
      #  path:
      #    "/Users/adrianibanez/Documents/projects/2024_sensor-platform/checkouts/elixir-desktop-bridge"}

      {:iroh_ex, "~> 0.0.15"},
      # {:iroh_ex,
      # path: "/Users/adrianibanez/Documents/projects/2024_sensor-platform/checkouts/iroh_ex"},
      {:rustler_precompiled, "~> 0.8"},
      # {:rustler_btleplug, "~> 0.0.3-alpha"},
      # {:rustler_btleplug,
      # path: "/Users/adrianibanez/Documents/projects/2024_sensor-platform/checkouts/rustler_btleplug",
      # },

      {:rustler, "~> 0.36 or ~> 0.37", optional: true},
      {:usage_rules, "~> 0.1", only: :dev},
      # Tidewave - can be enabled in production with ENABLE_TIDEWAVE=true
      # Protected by Basic Auth via AuthenticatedTidewave plug
      {:tidewave, "~> 0.5"},

      # QR code generation for room sharing
      {:eqrcode, "~> 0.1.10"},

      # OpenAPI specification generation
      {:open_api_spex, "~> 3.21"},

      # Hot code upgrades for Fly.io deployments
      {:fly_deploy, "~> 0.1.15"},

      # AI/LLM Integration
      {:ollama, "~> 0.9"}
      # {:remove_unused, github: "KristerV/remove_unused_ex"}

      # https://github.com/georgeguimaraes/soothsayer
      # https://github.com/gridpoint-com/plox

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
      reset_live_svelte: [
        "cmd --cd assets rm -rf node_modules/*",
        "deps.clean live_svelte",
        "deps.get",
        # "live_svelte.setup",
        "cmd npm install --prefix ./assets --save-dev esbuild esbuild-svelte svelte svelte-preprocess esbuild-plugin-import-glob",
        "cmd npm install --prefix ./assets --save ./deps/phoenix ./deps/phoenix_html ./deps/phoenix_live_view ./deps/live_svelte",
        "assets.deploy"
      ],
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
