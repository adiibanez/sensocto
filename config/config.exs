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
  ash_domains: [Sensocto.Accounts, Sensocto.Sensors, Sensocto.Graph]

# Neo4j/Boltx configuration (override in environment configs)
config :boltx, Bolt,
  uri: "bolt://localhost:7687",
  auth: [username: "neo4j", password: "sensocto123"],
  pool_size: 10

# AttributeStore tiered storage limits (all in-memory)
# Hot tier: fastest access, in Agent process memory
# Warm tier: fast concurrent reads via ETS
# Total capacity per attribute = hot_limit + warm_limit
config :sensocto,
  attribute_store_hot_limit: 500,
  attribute_store_warm_limit: 10_000

# System pulse (load monitoring) weights configuration
# These weights determine how much each factor contributes to overall system load.
# Higher values mean that factor has more influence on the system pulse.
# The weights are normalized, so they don't need to sum to 1.0
config :sensocto, :system_pulse,
  # CPU (scheduler utilization) - primary indicator of compute load
  cpu_weight: 0.45,
  # PubSub pressure - indicates message broadcasting backlog (IO bound)
  pubsub_weight: 0.30,
  # Message queue pressure - indicates process mailbox backlog
  queue_weight: 0.15,
  # Memory pressure has lowest weight - high memory is often fine in development
  memory_weight: 0.10

# Simulator configuration (disabled by default)
config :sensocto, :simulator,
  enabled: false,
  config_path: "config/simulators.yaml"

# Video/Voice calls configuration
config :sensocto, :calls,
  max_participants: 20,
  default_quality_profile: :auto

# Membrane RTC Engine ExWebRTC ICE configuration
config :membrane_rtc_engine_ex_webrtc,
  ice_servers: [
    %{urls: "stun:stun.l.google.com:19302"},
    %{urls: "stun:stun1.l.google.com:19302"}
  ]

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

# PubSub clustering configuration
# For single-node development, PG2 still works but adds no overhead
# For multi-node production, this enables distributed PubSub across cluster
config :sensocto, Sensocto.PubSub,
  adapter: Phoenix.PubSub.PG2,
  pool_size: 10

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

config :daisy_ui_components, translate_function: &SensoctoWeb.CoreComponents.translate_error/1

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

# LVN_ACTIVATION config :phoenix_template, :format_encoders, swiftui: Phoenix.HTML.Engine

# LVN_ACTIVATION config :live_view_native,
# LVN_ACTIVATION   plugins: [
# LVN_ACTIVATION     LiveViewNative.SwiftUI
# LVN_ACTIVATION   ]

# LVN_ACTIVATION config :phoenix, :template_engines, neex: LiveViewNative.Engine

# LVN_ACTIVATION config :live_view_native_stylesheet,
# LVN_ACTIVATION   content: [
# LVN_ACTIVATION     swiftui: [
# LVN_ACTIVATION       "lib/**/swiftui/*",
# LVN_ACTIVATION       "lib/**/*swiftui*"
# LVN_ACTIVATION     ]
# LVN_ACTIVATION   ],
# LVN_ACTIVATION   output: "priv/static/assets"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
