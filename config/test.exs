import Config
config :sensocto, token_signing_secret: "sLPXCrglbg3s1MmPqSVvxYZkqgom9bmh"

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :sensocto, Sensocto.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "sensocto_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Configure the replica repo for test (same as primary in test)
config :sensocto, Sensocto.Repo.Replica,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "sensocto_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :sensocto, SensoctoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "i/v92TEKlmVLlVKHZmMBmLqqiwUJKveGMVted/Nu77Ln0UDDKD6MLuaVxbnhpXVx",
  server: false

# In test we don't send emails.
config :sensocto, Sensocto.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  # Enable helpful, but potentially expensive runtime checks
  enable_expensive_runtime_checks: true

# Mark test environment for rate limiter to skip by default
config :sensocto, env: :test

# Disable rate limiting in tests by default (can be enabled per-test)
config :sensocto, enable_rate_limiting_in_test: false

# Wallaby browser testing configuration
config :wallaby,
  driver: Wallaby.Chrome,
  screenshot_on_failure: true,
  screenshot_dir: "tmp/wallaby_screenshots",
  # Use headless Chrome for CI
  chromedriver: [
    headless: System.get_env("CI") == "true"
  ],
  # Longer timeout for complex E2E tests
  max_wait_time: 10_000
