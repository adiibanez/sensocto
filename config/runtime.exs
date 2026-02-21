import Config

# Safe integer parsing for environment variables — returns default on invalid input
safe_int = fn env_var, default ->
  case Integer.parse(System.get_env(env_var) || "") do
    {n, ""} -> n
    _ -> default
  end
end

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/sensocto start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :sensocto, SensoctoWeb.Endpoint, server: true
end

# Delta encoding for high-frequency data — enable via env var
if System.get_env("DELTA_ENCODING_ENABLED") in ~w(true 1) do
  config :sensocto, :delta_encoding, enabled: true
end

# Tidewave AI debugging - can be enabled in production via environment variable
# Requires TIDEWAVE_USER and TIDEWAVE_PASS for authentication
# Access at https://your-app.fly.dev/tidewave
config :sensocto, :enable_tidewave, System.get_env("ENABLE_TIDEWAVE") in ~w(true 1)

# Tidewave needs project_name and root configured explicitly in releases
# (in dev, it auto-detects via Mix.Project)
if System.get_env("ENABLE_TIDEWAVE") in ~w(true 1) do
  config :tidewave,
    project_name: "sensocto",
    root: System.get_env("RELEASE_ROOT") || File.cwd!()
end

# Chat feature - disabled by default in production, enable via environment variable
# Set ENABLE_CHAT=true to enable the chat sidebar (desktop) and chat tab (mobile)
# In dev, this is set in config/dev.exs
if env = System.get_env("ENABLE_CHAT") do
  config :sensocto, :enable_chat, env in ~w(true 1)
end

# Simulator configuration - can be enabled via environment variable
if System.get_env("SIMULATOR_ENABLED") in ~w(true 1) do
  config :sensocto, :simulator,
    enabled: true,
    autostart: System.get_env("SIMULATOR_AUTOSTART") in ~w(true 1),
    config_path: System.get_env("SIMULATOR_CONFIG_PATH") || "config/simulators.yaml"
end

# FlyDeploy hot code upgrade configuration
if bucket = System.get_env("FLY_DEPLOY_BUCKET") do
  config :fly_deploy, bucket: bucket
end

# Tigris S3-compatible storage for room markdown backup
# On Fly.io, Tigris credentials are auto-injected when you run `fly storage create`
if System.get_env("TIGRIS_BUCKET") || System.get_env("BUCKET_NAME") do
  config :sensocto, :tigris,
    bucket: System.get_env("TIGRIS_BUCKET") || System.get_env("BUCKET_NAME"),
    region: System.get_env("TIGRIS_REGION") || System.get_env("AWS_REGION") || "auto",
    access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
    secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
    endpoint:
      System.get_env("TIGRIS_ENDPOINT") || System.get_env("AWS_ENDPOINT_URL_S3") ||
        "https://fly.storage.tigris.dev"

  # Enable backup worker when Tigris is configured
  config :sensocto, :backup_worker,
    enabled: true,
    interval_ms: safe_int.("BACKUP_INTERVAL_MS", 300_000),
    batch_size: safe_int.("BACKUP_BATCH_SIZE", 10)
end

# Optional static TURN server for video/voice calls (Membrane RTC Engine ExWebRTC)
# TURN is only needed when clients are behind symmetric NATs
if turn_url = System.get_env("TURN_SERVER_URL") do
  turn_username = System.get_env("TURN_USERNAME")
  turn_password = System.get_env("TURN_PASSWORD")

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
      %{urls: "stun:stun.cloudflare.com:3478"},
      # TURN relay (static)
      %{
        urls: turn_url,
        username: turn_username,
        credential: turn_password
      }
    ]
end

# Cloudflare TURN (dynamic short-lived credentials via API)
# Preferred over static TURN — generates ephemeral credentials per session.
# Set CLOUDFLARE_TURN_KEY_ID and CLOUDFLARE_TURN_API_TOKEN from Cloudflare dashboard.
if cf_turn_key_id = System.get_env("CLOUDFLARE_TURN_KEY_ID") do
  config :sensocto,
    cloudflare_turn_key_id: cf_turn_key_id,
    cloudflare_turn_api_token: System.get_env("CLOUDFLARE_TURN_API_TOKEN")
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: postgresql://USER:PASS@HOST/DATABASE?sslmode=require
      For Neon.tech: postgresql://user:pass@ep-xxx-pooler.region.aws.neon.tech/neondb?sslmode=require
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  # Primary database (Neon.tech) - handles all writes and can handle reads
  config :sensocto, Sensocto.Repo,
    url: database_url,
    ssl: [cacerts: :public_key.cacerts_get()],
    # Conservative default - Neon pooler has limits, don't exceed them
    # Each connection uses ~5-10MB RAM on Postgres side
    pool_size: safe_int.("POOL_SIZE", 10),
    # Queue settings help during connection pressure
    queue_target: 5000,
    queue_interval: 1000,
    # Neon auto-suspends after inactivity, needs time to wake up
    # Increased timeout to handle cold starts (default is 15000ms)
    timeout: 60_000,
    connect_timeout: 60_000,
    socket_options: maybe_ipv6

  # Read replica configuration (optional)
  # Set DATABASE_REPLICA_URL to enable read replica
  # For Neon, you can create a read replica and use its pooler endpoint
  if replica_url = System.get_env("DATABASE_REPLICA_URL") do
    config :sensocto, Sensocto.Repo.Replica,
      url: replica_url,
      ssl: [cacerts: :public_key.cacerts_get()],
      pool_size: safe_int.("REPLICA_POOL_SIZE", 5),
      timeout: 60_000,
      connect_timeout: 60_000,
      socket_options: maybe_ipv6
  else
    # If no replica URL, configure replica to use primary (for simpler deployments)
    config :sensocto, Sensocto.Repo.Replica,
      url: database_url,
      ssl: [cacerts: :public_key.cacerts_get()],
      pool_size: safe_int.("REPLICA_POOL_SIZE", 5),
      timeout: 60_000,
      connect_timeout: 60_000,
      socket_options: maybe_ipv6
  end

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = safe_int.("PORT", 4000)

  config :sensocto, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :logger, level: :info

  config :sensocto, SensoctoWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base,
    # Set check_origin at runtime so PHX_HOST is available
    check_origin: [
      "https://sensocto.ddns.net",
      "https://#{host}",
      "https://sensocto.fly.dev"
    ]

  config :sensocto,
    token_signing_secret:
      System.get_env("TOKEN_SIGNING_SECRET") ||
        raise("Missing environment variable `TOKEN_SIGNING_SECRET`!")

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :sensocto, SensoctoWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :sensocto, SensoctoWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Also, you may need to configure the Swoosh API client of your choice if you
  # are not using SMTP. Here is an example of the configuration:
  #

  config :swoosh, api_client: Swoosh.ApiClient.Hackney

  config :sensocto, Sensocto.Mailer,
    adapter: Swoosh.Adapters.SMTP2GO,
    api_key: System.get_env("SMTP2GO_APIKEY")

  mailer_from_name = System.get_env("MAILER_FROM_NAME", "Sensocto")
  mailer_from_email = System.get_env("MAILER_FROM_EMAIL", "hello@adrianibanez.info")
  config :sensocto, :mailer_from, {mailer_from_name, mailer_from_email}

  config :sensocto,
    google_client_secret: System.get_env("GOOGLE_CLIENT_SECRET"),
    # ||raise("Missing environment variable `GOOGLE_SIGNING_SECRET`!"),
    google_redirect_uri: System.get_env("GOOGLE_REDIRECT_URI"),
    google_client_id: System.get_env("GOOGLE_CLIENT_ID")

  #
  # For this example you need include a HTTP client required by Swoosh API client.
  # Swoosh supports Hackney and Finch out of the box:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Hackney
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
