# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :ash,
  allow_forbidden_field_for_relationships_by_default?: true,
  include_embedded_source_by_default?: false,
  show_keysets_for_all_actions?: false,
  default_page_type: :keyset,
  policies: [no_filter_static_forbidden_reads?: false]

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :admin,
        :authentication,
        :tokens,
        :resource,
        :code_interface,
        :actions,
        :policies,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :multitenancy,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities
      ]
    ],
    "Ash.Domain": [
      section_order: [:admin, :resources, :policies, :authorization, :domain, :execution]
    ]
  ]

config :sensocto,
  ecto_repos: [Sensocto.Repo],
  generators: [timestamp_type: :utc_datetime],
  ash_domains: [Sensocto.Accounts, Sensocto.Sensors]

config :ex_heroicons, type: "outline"

# Configures the endpoint
config :sensocto, SensoctoWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  http: [
    websocket_options: [
      compress: false
    ]
  ],
  render_errors: [
    formats: [html: SensoctoWeb.ErrorHTML, json: SensoctoWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Sensocto.PubSub,
  live_view: [signing_salt: "LfxsxGaX"]

# config :sensocto, Sensocto.PubSub,
#  adapter: Phoenix.PubSub.PG2

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :sensocto, Sensocto.Mailer, adapter: Swoosh.Adapters.Local
config :sensocto, :dns_cluster_query, "sensocto.internal"

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.0",
  sensocto: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --minify
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :mime, :types, %{
  "application/wasm" => ["wasm"],
  "audio/flac" => ["flac"],
  "text/styles" => ["styles"],
  "text/swiftui" => ["swiftui"]
}

config :sensocto,
  google_client_secret: System.get_env("GOOGLE_CLIENT_SECRET"),
  # ||raise("Missing environment variable `GOOGLE_SIGNING_SECRET`!"),
  google_redirect_uri: System.get_env("GOOGLE_REDIRECT_URI"),
  google_client_id: System.get_env("GOOGLE_CLIENT_ID")

config :phoenix_template, :format_encoders, swiftui: Phoenix.HTML.Engine

config :live_view_native,
  plugins: [
    LiveViewNative.SwiftUI
  ]

config :phoenix, :template_engines, neex: LiveViewNative.Engine

config :live_view_native_stylesheet,
  content: [
    swiftui: [
      "lib/**/swiftui/*",
      "lib/**/*swiftui*"
    ]
  ],
  output: "priv/static/assets"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
