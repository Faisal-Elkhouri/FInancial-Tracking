defmodule FinancialTracking.MixProject do
  use Mix.Project

  def project do
    [
      app: :financial_tracking,
      version: "0.1.0",
      # Matches what we actually build and test against (see the ARG pins in
      # Dockerfile / Dockerfile.dev). The previous "~> 1.15" claimed support for
      # five minor versions that were never exercised.
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {FinancialTracking.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test, ci: :test]
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
      {:phoenix, "~> 1.8.1"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},

      # Quality and security gates. All dev/test only and runtime: false, so
      # none of these reach the production release.
      #
      # mix_audit  - known CVEs in the dependency tree
      # sobelow    - Phoenix-specific static analysis (XSS via raw/1, missing
      #              CSRF, config leaks). Table stakes for an app handling money.
      # credo      - style/consistency; run non-strict to start.
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
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
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind financial_tracking", "esbuild financial_tracking"],
      "assets.deploy": [
        "tailwind financial_tracking --minify",
        "esbuild financial_tracking --minify",
        "phx.digest"
      ],
      # Local gate: fixes what it can, then runs the suite. Run before committing.
      #
      # NOTE the flag spelling. It was previously "--warning-as-errors"
      # (singular), and `mix compile` ignores unknown switches silently - a
      # bogus flag also exits 0 - so this gate had never actually run.
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "test"
      ],

      # CI gate: identical intent, but ASSERTS instead of mutating.
      # `format` rewrites files and `deps.unlock --unused` edits mix.lock, so
      # running `precommit` in CI would let a badly formatted or lock-rotted
      # branch go green while leaving the checkout dirty.
      ci: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "deps.unlock --check-unused",
        # `cmd mix hex.audit`, not plain `hex.audit`, on purpose.
        #
        # Once anything in the same Mix invocation has compiled the project,
        # the Hex archive is no longer on the code path and `hex.audit` fails
        # with "The task hex.audit could not be found" - which reads like a
        # missing dependency rather than a load-path problem. Running it as a
        # subprocess gives it a fresh VM where the archive is loaded.
        # Verified in the container; it works standalone and fails in-chain.
        #
        # hex.audit and deps.audit are NOT redundant: hex.audit queries Hex's
        # own advisory database (plus retired releases), deps.audit checks the
        # Elixir Security Advisories repo. Each has caught real findings the
        # other missed - retired plug from one, postgrex SQL-injection
        # advisories from the other.
        "cmd mix hex.audit",
        "deps.audit",
        # --skip honours .sobelow-skips, which records findings we have
        # explicitly accepted (see docs/INFRASTRUCTURE_BACKLOG.md). Any NEW
        # finding still fails the build, which is the point.
        "sobelow --skip --exit Low",
        "test"
      ]
    ]
  end
end
