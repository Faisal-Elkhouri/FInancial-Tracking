import Config

# Configure your database
#
# Docker-first: defaults point at the compose "db" service, since the app only
# runs in containers (see the `test` service in docker-compose.yml). Note we
# deliberately do NOT read DATABASE_NAME here — the web container sets that to
# the dev database, and tests must never point at it. Tests get their own
# TEST_DATABASE_NAME variable instead.
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :financial_tracking, FinancialTracking.Repo,
  username: System.get_env("DATABASE_USER", "postgres"),
  password: System.get_env("DATABASE_PASSWORD", "postgres"),
  hostname: System.get_env("DATABASE_HOST", "db"),
  database:
    System.get_env("TEST_DATABASE_NAME", "financial_tracking_test") <>
      System.get_env("MIX_TEST_PARTITION", ""),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :financial_tracking, FinancialTrackingWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "zYUe/bwWUWAgYvpNkoVYjibq54FOn5/LoXms4qJfwosOa5oyI6mWmTBzlilN6nOq",
  server: false

# In test we don't send emails
config :financial_tracking, FinancialTracking.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
