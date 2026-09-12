import Config

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
#     PHX_SERVER=true bin/financial_tracking start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :financial_tracking, FinancialTrackingWeb.Endpoint, server: true
end

if config_env() == :prod do
  # Read a secret from `<NAME>_FILE` (a Docker/Compose secret mounted under
  # /run/secrets) and fall back to the plain `<NAME>` environment variable.
  #
  # The file form is preferred: a plain `environment:` value is visible in
  # `docker inspect`, in /proc/<pid>/environ for every process in the
  # container, and in `docker compose config` output.
  read_secret = fn name ->
    case System.get_env(name <> "_FILE") do
      nil -> System.get_env(name)
      path -> path |> File.read!() |> String.trim()
    end
  end

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  # Two supported shapes, so one image is portable:
  #
  #   * DATABASE_URL      - what most PaaS providers hand you.
  #   * discrete options  - preferred for self-hosted/Compose, because it
  #     avoids the URL parser entirely. Ecto runs URI.decode/1 on the password
  #     extracted from a URL, so a literal `%` is read as a percent-escape, and
  #     a literal `@`, `/` or `#` breaks URI.parse's authority split before
  #     Ecto ever sees it. A password passed discretely needs no encoding.
  repo_connection_opts =
    case System.get_env("DATABASE_URL") do
      url when is_binary(url) and url != "" ->
        [url: url]

      _ ->
        password =
          read_secret.("DATABASE_PASSWORD") ||
            raise """
            no database connection configured.
            Set DATABASE_URL, or set DATABASE_PASSWORD / DATABASE_PASSWORD_FILE
            together with DATABASE_HOST, DATABASE_USER and DATABASE_NAME.
            """

        [
          hostname: System.get_env("DATABASE_HOST") || "db",
          port: String.to_integer(System.get_env("DATABASE_PORT") || "5432"),
          username: System.get_env("DATABASE_USER") || "postgres",
          password: password,
          database: System.get_env("DATABASE_NAME") || "financial_tracking_prod"
        ]
    end

  config :financial_tracking,
         FinancialTracking.Repo,
         [
           # ssl: true is deliberately NOT set: app and database share a private
           # Docker network here. Turn it on (with verify: :verify_peer and a
           # cacertfile - the Erlang default is :verify_none, i.e. encryption
           # without authentication) if the database ever moves off-host.
           pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
           # For machines with several cores, consider starting multiple pools of `pool_size`
           # pool_count: 4,
           socket_options: maybe_ipv6,
           # Ecto's default is :table_lock, which wraps the whole migration in a
           # transaction holding a write lock on schema_migrations. The advisory
           # lock serialises migrations across nodes just as safely while
           # allowing operations that cannot run inside a transaction, such as
           # CREATE INDEX CONCURRENTLY.
           migration_lock: :pg_advisory_lock
         ] ++ repo_connection_opts

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    read_secret.("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE (or SECRET_KEY_BASE_FILE) is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  # PHX_HOST is required, with no fallback, on purpose.
  #
  # Phoenix's default `check_origin: true` validates WebSocket origins against
  # this host ONLY (not the scheme, not the port). A stale default such as
  # "localhost" or "example.com" therefore does not fail loudly - it silently
  # rejects every LiveView socket once a real domain points at the app, leaving
  # dead views and an infinite reconnect loop. Fail at boot instead.
  host =
    System.get_env("PHX_HOST") ||
      raise """
      environment variable PHX_HOST is missing.
      Set it to the hostname browsers use to reach this app, e.g. money.example.com.
      """

  port = String.to_integer(System.get_env("PORT") || "4000")

  # The scheme/port the *outside world* uses, which is not necessarily how this
  # process is reached. Behind a TLS-terminating proxy the defaults are right.
  # For a plain-HTTP local rehearsal, set PHX_SCHEME=http and PHX_URL_PORT=4000
  # so generated URLs and the origin check match what the browser actually sends.
  url_scheme = System.get_env("PHX_SCHEME") || "https"
  url_port = String.to_integer(System.get_env("PHX_URL_PORT") || if(url_scheme == "https", do: "443", else: "80"))

  config :financial_tracking, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :financial_tracking, FinancialTrackingWeb.Endpoint,
    url: [host: host, port: url_port, scheme: url_scheme],
    # An explicit origin list compares scheme, host AND port. `check_origin:
    # true` compares host only, so a same-host page on another scheme or port
    # would pass - worth closing for an app that handles money. Derived from the
    # values above so the two can never drift apart.
    check_origin: ["#{url_scheme}://#{host}:#{url_port}"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :financial_tracking, FinancialTrackingWeb.Endpoint,
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
  #     config :financial_tracking, FinancialTrackingWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :financial_tracking, FinancialTracking.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
