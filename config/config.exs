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
  ecto_repos: [Sensocto.Repo, Sensocto.Repo.Replica],
  generators: [timestamp_type: :utc_datetime],
  ash_domains: [Sensocto.Accounts, Sensocto.Sensors]

# Internationalization (i18n) configuration
config :sensocto, SensoctoWeb.Gettext,
  default_locale: "en",
  locales: ~w(en de gsw fr es pt_BR zh ja)

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
# Multiple STUN servers for redundancy and better NAT traversal
config :membrane_rtc_engine_ex_webrtc,
  ice_servers: [
    # Google public STUN servers
    %{urls: "stun:stun.l.google.com:19302"},
    %{urls: "stun:stun1.l.google.com:19302"},
    %{urls: "stun:stun2.l.google.com:19302"},
    %{urls: "stun:stun3.l.google.com:19302"},
    %{urls: "stun:stun4.l.google.com:19302"},
    # Twilio public STUN
    %{urls: "stun:global.stun.twilio.com:3478"},
    # Cloudflare public STUN
    %{urls: "stun:stun.cloudflare.com:3478"}
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
  pool_size: 16

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :sensocto, Sensocto.Mailer, adapter: Swoosh.Adapters.Local
config :sensocto, :mailer_from, {"Sensocto", "hello@adrianibanez.info"}
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

# Rate limiting configuration for authentication endpoints
# Protects against brute-force attacks and credential stuffing
config :sensocto, SensoctoWeb.Plugs.RateLimiter,
  # Authentication endpoints (login, password reset, magic link)
  # 10 requests per minute per IP
  auth_limit: 10,
  auth_window_ms: 60_000,
  # Registration endpoints - stricter to prevent bot signups
  # 5 requests per minute per IP
  registration_limit: 5,
  registration_window_ms: 60_000,
  # API authentication endpoints (mobile token verification)
  # 20 requests per minute per IP
  api_auth_limit: 20,
  api_auth_window_ms: 60_000,
  # Guest authentication - moderate limits
  # 10 requests per minute per IP
  guest_auth_limit: 10,
  guest_auth_window_ms: 60_000

# Multi-backend room hydration configuration
# Coordinates room state persistence across PostgreSQL, Iroh P2P, and client-side localStorage
config :sensocto, Sensocto.Storage.HydrationManager,
  # Backends are tried in priority order (lower = higher priority)
  backends: [
    {Sensocto.Storage.Backends.PostgresBackend, enabled: true},
    {Sensocto.Storage.Backends.IrohBackend, enabled: true},
    {Sensocto.Storage.Backends.LocalStorageBackend, enabled: false}
  ],
  # Hydration strategy:
  # - :priority_fallback - Try backends in order, return first success
  # - :latest - Query all backends, return highest version
  # - :quorum - Require majority agreement (not implemented)
  hydration_strategy: :priority_fallback,
  # Interval for periodic snapshot batching (milliseconds)
  snapshot_interval_ms: 5_000

# Pythonx - Python integration via uv for realistic biosignal simulation
config :pythonx, :uv_init,
  pyproject_toml: """
  [project]
  name = "sensocto-simulator"
  version = "0.0.0"
  requires-python = "==3.13.*"
  dependencies = [
    "neurokit2>=0.2.0",
    "numpy>=1.24.0"
  ]
  """

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
