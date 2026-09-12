# Infrastructure Guide

How this application is built, configured, and run — and the reasoning behind
each piece. Everything runs in Docker; the host machine (Windows or otherwise)
only needs Docker Desktop and a text editor. Elixir, Erlang, Postgres, and
Node-ish asset tooling never touch the host.

This document covers:

1. [The big picture](#1-the-big-picture)
2. [Dev vs prod: two stacks, two images](#2-dev-vs-prod-two-stacks-two-images)
3. [The environment variable system](#3-the-environment-variable-system)
4. [Elixir's config layering (how env vars actually reach the app)](#4-elixirs-config-layering)
5. [The database lifecycle](#5-the-database-lifecycle)
6. [Testing](#6-testing)
7. [Livebook](#7-livebook)
8. [Day-to-day operations](#8-day-to-day-operations)
9. [Production maintenance practices](#9-production-maintenance-practices)
10. [Application architecture conventions](#10-application-architecture-conventions)

---

## 1. The big picture

There are two independent Compose stacks in this repo:

| | Dev | Prod |
|---|---|---|
| Compose file | `docker-compose.yml` (the default) | `docker-compose.prod.yml` |
| App image | `Dockerfile.dev` — full Elixir toolchain | `Dockerfile` — multi-stage OTP release |
| How code runs | Source bind-mounted, recompiled live | Compiled release baked into the image |
| Code reloading | Yes (`inotify-tools` + Phoenix live reload) | No — rebuild + redeploy to change code |
| Services | `db`, `web`, `livebook`, `test` (profile) | `db`, `web` |
| Database | `financial_tracking_dev` | `financial_tracking_prod` |
| Start command | `docker compose up` | `docker compose -f docker-compose.prod.yml up --build -d` |
| Secrets required | None (safe defaults) | `DATABASE_PASSWORD`, `SECRET_KEY_BASE` — refuses to start without them |

The guiding principle: **dev optimizes for iteration speed, prod optimizes for
immutability and small attack surface.** They intentionally share as little as
possible beyond the Postgres image and the env variable names.

---

## 2. Dev vs prod: two stacks, two images

### 2.1 The dev image (`Dockerfile.dev`)

A single-stage image that keeps the entire Elixir toolchain (compiler, Hex,
Rebar, `build-essential`, git, `inotify-tools`). It:

1. Installs system packages and Hex/Rebar.
2. Copies only `mix.exs` + `mix.lock` and runs `mix deps.get` — so the
   (slow) dependency fetch is a cached Docker layer that only invalidates when
   dependencies actually change.
3. Does **not** copy the application source. At runtime the whole repo is
   bind-mounted over `/app` (see below), so the container always sees your
   current working tree.

### 2.2 The dev stack (`docker-compose.yml`)

**`db`** — `postgres:17` with credentials from env vars (safe defaults for
dev). Port 5432 is published to the host purely as a convenience so you can
inspect the database with psql or a GUI. Data persists in the `pgdata_dev`
named volume. A `pg_isready` healthcheck gates the app's startup so the web
container never races a half-started database.

**`web`** — built from `Dockerfile.dev`. Its startup command chains:

```
mix deps.get && mix ecto.create && mix ecto.migrate && elixir --name financial_tracking@web.local --cookie $LIVEBOOK_COOKIE -S mix phx.server
```

- `deps.get` re-syncs dependencies in case `mix.lock` changed since the image
  was built (the image layer is a cache, not the source of truth).
- `ecto.create` / `ecto.migrate` make the container self-provisioning: a fresh
  clone plus `docker compose up` yields a created, migrated database with no
  manual steps.
- The server starts as a **named distributed node**
  (`financial_tracking@web.local`) sharing an Erlang cookie, which is what
  lets Livebook attach to the running app. Erlang long-name distribution
  requires a fully qualified hostname (one containing a dot), so the
  container gets `hostname: web.local` plus a matching Docker network alias
  that other containers resolve via Docker DNS.

Its volume layout is the key trick of the dev setup:

```yaml
- .:/app          # live source: edits on the host are seen instantly
- deps:/app/deps  # named volume: Linux-compiled deps stay in Docker
- build:/app/_build
```

The bind mount gives live code reloading. The two named volumes *shadow*
`deps/` and `_build/` inside that mount so compiled artifacts are
Linux-native and never collide with anything on the (possibly Windows) host.
Without this, host and container would fight over incompatible build
artifacts.

**`livebook`** — the official Livebook image, configured for long-name
distribution with the same cookie so it can attach to `financial_tracking@web.local`
(see [§7](#7-livebook)). Notebooks persist to `./notebooks` on the host.

**`test`** — a one-shot test runner behind a Compose *profile*
(`profiles: ["test"]`), meaning `docker compose up` never starts it; it only
runs when explicitly invoked with `docker compose run` (see
[§6](#6-testing)).

### 2.3 The prod image (`Dockerfile`)

The standard Phoenix release Dockerfile (from `mix phx.gen.release --docker`),
a **multi-stage build**:

**Stage 1 — `builder`** (full Elixir image):
1. Fetches prod-only deps (`mix deps.get --only prod`).
2. Copies compile-time config (`config.exs`, `prod.exs`) *before* compiling
   deps, so a config change correctly triggers dependency recompilation.
3. Compiles the app, builds and digests assets (`mix assets.deploy` →
   minified CSS/JS + `cache_manifest.json`).
4. Copies `runtime.exs` *after* compilation — runtime config changes don't
   force a recompile.
5. Runs `mix release`, producing a self-contained OTP release: the app, all
   deps, and the Erlang VM itself, in one directory.

**Stage 2 — `final`** (plain Debian slim): copies *only* the release out of
the builder. The result contains no compiler, no Hex, no source code, no
build tools — a materially smaller image and attack surface. The app runs as
the unprivileged `nobody` user.

The layer ordering in both Dockerfiles is deliberate: things that change
rarely (system packages, deps) come before things that change often (source),
maximizing Docker layer-cache hits and keeping rebuilds fast.

### 2.4 The prod stack (`docker-compose.prod.yml`)

- `db` has **no published port** — the database is reachable only on the
  internal Compose network. Its password is *required* (`:?` guard, §3).
- `web` starts with `sh -c "/app/bin/migrate && /app/bin/server"`: migrations
  run via the release's built-in migration script
  (`FinancialTracking.Release.migrate/0` in `lib/financial_tracking/release.ex` —
  releases don't ship Mix, so `mix ecto.migrate` doesn't exist in prod), then
  the server starts.
- The app receives one composite `DATABASE_URL`
  (`ecto://user:pass@db/dbname`) rather than individual vars — this is the
  contract `config/runtime.exs` expects in prod, and it matches what most
  hosting platforms provide.
- Both services have `restart: unless-stopped` so they survive daemon
  restarts and crashes.
- Data persists in `pgdata_prod`, a completely separate volume from dev's.

---

## 3. The environment variable system

### 3.1 The two files

- **`.env`** — your real values. Read automatically by Docker Compose to fill
  every `${VARIABLE}` reference in the compose files. **Git-ignored**;
  secrets never enter version control.
- **`.env.example`** — the committed template: variable names, safe defaults,
  and a comment per variable. Setup on any machine is
  `cp .env.example .env`, then fill in real values.

**Maintenance rule: when you add a variable to `.env`, add it to
`.env.example` in the same commit** (with a placeholder, never the real
value). The template is the documented contract of what the stack needs; an
out-of-sync template is how "works on my machine" happens.

### 3.2 Interpolation syntax and the fail-fast pattern

The compose files use two forms deliberately:

```yaml
POSTGRES_USER: ${DATABASE_USER:-postgres}     # default: optional in dev
SECRET_KEY_BASE: ${SECRET_KEY_BASE:?generate one with `mix phx.gen.secret`}  # required
```

- `:-` supplies a default — used in dev, where convenience wins and the
  values aren't sensitive.
- `:?` makes the variable **required**: Compose refuses to even start the
  stack and prints the message after the `?`. Prod uses this for
  `DATABASE_PASSWORD` and `SECRET_KEY_BASE`, so a misconfigured production
  deploy fails loudly at startup instead of running with a default password.

This "fail fast on missing secrets" pattern repeats at the app layer:
`config/runtime.exs` `raise`s if `DATABASE_URL` or `SECRET_KEY_BASE` is
missing. Two layers of guard means there is no path to a silently
misconfigured production instance.

### 3.3 The variables

| Variable | Used by | Notes |
|---|---|---|
| `DATABASE_USER` / `DATABASE_PASSWORD` | dev + prod | Password is defaulted in dev, **required** in prod |
| `DATABASE_NAME` | dev + prod | Defaults differ per stack (`_dev` / `_prod`) |
| `TEST_DATABASE_NAME` | test | Separate variable on purpose — see §6.2 |
| `LIVEBOOK_COOKIE` | dev | Erlang cookie shared by the app node and Livebook |
| `PHX_HOST` | prod | Public hostname the app generates URLs with |
| `SECRET_KEY_BASE` | prod | Signs/encrypts cookies and tokens. Generate with `mix phx.gen.secret`. **Never reuse across environments; rotating it invalidates all sessions** |
| `PORT`, `POOL_SIZE`, `ECTO_IPV6`, `DNS_CLUSTER_QUERY` | prod | Optional tuning knobs read by `runtime.exs` |

---

## 4. Elixir's config layering

Env vars are only half the story — Phoenix has its own config pipeline, and
knowing *when* each file runs tells you where a setting belongs.

```
config/config.exs      compile time, all environments (shared base)
  └─ imports config/{dev,test,prod}.exs   compile time, per environment
config/runtime.exs     boot time, all environments — including inside a release
```

**Compile-time** files are evaluated when the code is compiled. For prod that
means *inside the Docker build*, on the build machine — `System.get_env` in
`prod.exs` would read the *builder's* environment and freeze the value into
the artifact. That's why:

- `config/prod.exs` contains only genuinely static settings (cache manifest,
  logger level, Swoosh client).
- **All** secrets and deployment-specific values live in
  `config/runtime.exs`, which executes at boot on the actual production
  machine. This is what makes the release image *portable*: one image can be
  pointed at any database/host/secret purely via environment variables —
  build once, configure at deploy time.

**Per-environment conventions in this repo:**

- `config/dev.exs` and `config/test.exs` read `DATABASE_*` env vars with
  Docker-first defaults (host defaults to `db`, the Compose service name).
  This works because in dev/test we run `mix` directly, so "compile time"
  and "runtime" are the same moment on the same machine — reading env vars
  there is safe. In prod it wouldn't be, hence `runtime.exs`.
- `config/test.exs` additionally forces `server: false` (no HTTP server
  during tests), the SQL Sandbox pool (§6.1), and the Swoosh test adapter
  (emails are captured, not sent).

**Rule of thumb:** static and environment-shaped → `dev/test/prod.exs`;
secret or deployment-shaped → `runtime.exs` + env var; shared by all
environments → `config.exs`.

---

## 5. The database lifecycle

Three fully isolated databases on the two Postgres services:

| Database | Where | Created by |
|---|---|---|
| `financial_tracking_dev` | dev `db` container | `web` startup (`mix ecto.create`) |
| `financial_tracking_test` | dev `db` container | the `mix test` alias (`ecto.create --quiet`) |
| `financial_tracking_prod` | prod `db` container | Postgres itself via `POSTGRES_DB` |

**Migrations** live in `priv/repo/migrations/` and run automatically in both
stacks — via `mix ecto.migrate` at dev startup and via the release's
`/app/bin/migrate` at prod startup. Consequences for how you work:

- A teammate pulling new migrations just restarts the stack.
- Migrations must therefore be **safe to run against live data**: additive
  where possible, no destructive column drops in the same deploy that stops
  writing to them, and never *edit* a migration that has already run anywhere
  (Postgres tracks applied migrations in `schema_migrations` by timestamp;
  edits to applied files are silently ignored). Fix mistakes with a new
  migration.

**Data persistence** is in named volumes (`pgdata_dev`, `pgdata_prod`).
`docker compose down` keeps them; `docker compose down -v` **destroys them**
— never run `-v` against the prod stack unless you mean to delete the
production database. To reset dev cleanly, prefer
`docker compose exec web mix ecto.reset` (drop, recreate, migrate, seed via
`priv/repo/seeds.exs`).

---

## 6. Testing

### 6.1 Running tests

```sh
docker compose run --rm test                              # whole suite
docker compose run --rm test mix test test/foo_test.exs   # one file
docker compose run --rm test mix test --failed            # only previous failures
```

`run --rm` starts a fresh one-shot container (auto-removed on exit) and
implicitly activates the `test` profile. The service shares the `deps` and
`_build` volumes with `web` — safe because `MIX_ENV=test` compiles into
`_build/test`, a separate directory from web's `_build/dev`, and it means the
test run reuses all cached compilation instead of starting cold.

Tests use the **Ecto SQL Sandbox** (configured in `config/test.exs` +
`test/support/data_case.ex`): every test runs inside a transaction that is
rolled back at the end, so tests are isolated from each other and can run
concurrently (`async: true`).

### 6.2 Why `TEST_DATABASE_NAME` is a separate variable

The `web` container exports `DATABASE_NAME=financial_tracking_dev`. If
`config/test.exs` read `DATABASE_NAME` like the other configs do, then
running tests inside the web container (`docker compose exec web ...`) would
aim the test suite — including `ecto.create`/`ecto.migrate` and every
sandboxed write — at the **development database**. So the test config
deliberately ignores `DATABASE_NAME` and reads its own `TEST_DATABASE_NAME`
(default `financial_tracking_test`). There is no environment in which the
test suite can reach dev or prod data.

`MIX_TEST_PARTITION` is appended to the test database name; it exists so a CI
system can run partitions of the suite in parallel against separate
databases. Unused locally.

### 6.3 The pre-commit gate

```sh
docker compose run --rm test mix precommit
```

runs `compile --warnings-as-errors`, checks for unused deps, formats, and
runs the tests (`precommit` alias in `mix.exs`, pinned to the test env). Make
passing this the bar for every commit; it is also exactly what a CI job
should run.

---

## 7. Livebook

Livebook runs as its own dev-stack container (UI at
<http://localhost:8080>) and connects to the running Phoenix app through
Erlang **distribution**: the web container starts as node
`financial_tracking@web.local`, both containers share `LIVEBOOK_COOKIE`, and
Docker DNS (via the `web.local` network alias) lets Livebook find it.

To attach a notebook to the live app: *Runtime settings → Attached node* →
name `financial_tracking@web.local`, cookie = your `LIVEBOOK_COOKIE`. Cells then
execute **inside the running application** — full access to `Repo`, contexts,
and application state.

Two things to remain conscious of:

- The attached node is the **dev** environment: notebook code hits the real
  dev database with no sandbox. Wrap experimental writes in
  `Repo.transaction` + deliberate rollback, or treat the dev DB as
  disposable (`mix ecto.reset` exists).
- The cookie is an authentication credential — any process that knows it and
  can reach the node has full code execution on it. Fine on a local Compose
  network; never expose EPMD/distribution ports publicly. Note the prod
  stack deliberately has **no Livebook** and no distribution flags.

Notebooks are bind-mounted from `./notebooks` and should be committed like
code.

---

## 8. Day-to-day operations

```sh
# Dev
docker compose up                         # start everything (app :4000, Livebook :8080)
docker compose up --build                 # after changing mix.exs/Dockerfile.dev
docker compose logs -f web               # follow app logs
docker compose exec web sh -c 'iex --name console@web.local --cookie "$LIVEBOOK_COOKIE" --remsh financial_tracking@web.local'  # IEx into the running app
docker compose exec web mix ecto.reset   # rebuild dev DB from scratch
docker compose down                       # stop (data survives)

# Tests
docker compose run --rm test
docker compose run --rm test mix precommit

# Prod
docker compose -f docker-compose.prod.yml up --build -d   # build + deploy
docker compose -f docker-compose.prod.yml logs -f web
docker compose -f docker-compose.prod.yml down             # stop (data survives)
```

When dependencies change (`mix.exs` / `mix.lock`): the dev `web` command runs
`deps.get` on every start, so usually a restart suffices; rebuild with
`--build` if the Docker layer cache is stale. The prod image must always be
rebuilt.

---

## 9. Production maintenance practices

The habits that keep this production-grade as the project grows:

1. **One artifact, many configs.** Never bake environment-specific values
   into the prod image. If you need a new knob, thread it through an env var
   read in `runtime.exs`, add it to both compose files as needed, and
   document it in `.env.example`.
2. **Fail fast on misconfiguration.** New required prod settings get the
   `:?` guard in compose *and* a `raise` in `runtime.exs`. Loud startup
   failures beat quiet wrong behavior.
3. **Secrets hygiene.** Real values only in `.env` (ignored) or the host's
   secret store. If a secret ever lands in git history, rotate it —
   deleting the commit is not enough. Rotate `SECRET_KEY_BASE` knowingly
   (it logs out all users).
4. **Migrations are forward-only and deploy-safe.** New migration for every
   change, never edit applied ones, keep them non-destructive relative to
   the currently running code (the old code briefly runs against the new
   schema during deploys).
5. **Back up prod data.** The `pgdata_prod` volume is the only copy.
   Schedule `pg_dump` (e.g.
   `docker compose -f docker-compose.prod.yml exec db pg_dump -U postgres financial_tracking_prod > backup.sql`)
   and store dumps off the machine. Test a restore before you need one.
6. **Pin and upgrade deliberately.** Elixir/OTP/Debian versions are pinned
   as `ARG`s at the top of both Dockerfiles — keep dev and prod pins
   identical, and bump them together in a dedicated commit that passes the
   full test suite. Same for the `postgres:17` tag (major version bumps
   require a data migration, not just a tag change).
7. **Gate every change on `mix precommit`.** Warnings-as-errors, format,
   tests. When CI exists, it runs the same command — no separate CI logic to
   drift.
8. **Prod is minimal on purpose.** No Livebook, no exposed DB port, no
   compiler, `nobody` user, required secrets. When adding a service or a
   port mapping to prod, the question is "does the running system need
   this?", not "would this be convenient?" — conveniences belong in the dev
   stack.

---

## 10. Application architecture conventions

Established July 2026 when the codebase was restructured (context module
introduced, schemas renamed to singular, FK deletion rules tightened).
These are the rules for all future domain code — follow them so the
codebase stays consistent with what Phoenix generators and documentation
assume.

### 10.1 All domain logic goes through the context

`FinancialTracking.Tracker` (`lib/financial_tracking/tracker.ex`) is the
**only** public API for offices, purchases, and executive budget line
items. The layering is:

```
web layer (controllers / LiveViews)  →  context (Tracker)  →  schemas + Repo
```

- Controllers, LiveViews, Livebook notebooks, and scripts call
  `Tracker.create_purchase(attrs)` etc. They **never** call `Repo.*` or
  build changesets themselves. (Coming from Python: schemas are like
  SQLAlchemy models — data shape and validation only; the context is the
  service layer.)
- Adding a new operation? Put it in the context, name it after the domain
  action (`approve_purchase`, not `update_purchase_status_field`), have it
  return `{:ok, struct}` / `{:error, changeset}`, and test it in
  `test/financial_tracking/tracker_test.exs`.
- A new domain area (e.g. accounts, reporting) gets its **own** context
  module — don't let `Tracker` become a junk drawer. Rule of thumb: if two
  groups of functions never share schemas, they're two contexts.
- Test fixtures (`test/support/fixtures/tracker_fixtures.ex`) also go
  through the context, so tests exercise the same code paths as the app.

### 10.2 Schema modules are singular

A schema struct represents **one row**, so the module is singular:
`Office`, `Purchase`, `ExecutiveBudget` — while the database tables stay
plural (`offices`, `purchases`). Plural module names are reserved for
contexts. Every Phoenix generator and tutorial assumes this; deviating
means fighting the ecosystem.

When creating new schemas, prefer generating them so all conventions come
along for free:

```sh
docker compose exec web mix phx.gen.context Tracker Vendor vendors name:string ...
```

### 10.3 Foreign keys: financial data is never silently orphaned

Policy (implemented in migration `20260703120000_restrict_financial_fks`):

| Reference | `on_delete` | Why |
|---|---|---|
| `purchases.origin_office_id` → offices | `:restrict` | A purchase must not silently lose its origin; deleting an office with purchases must fail loudly |
| `executive_budget.office_id` → offices | `:restrict` | Changeset requires the field, so nilifying would create rows the app considers invalid |
| `offices.parent_id` → offices | `:restrict` | Delete/reparent children before deleting a parent office |
| `executive_budget.parent_line_item_id` → itself | `:nilify_all` | Deliberate: deleting a parent line item *promotes* its children to top level |

Rules for new foreign keys:

- **Default to `:restrict`** for anything financial or audit-relevant.
  Use `:nilify_all`/`:delete_all` only when disappearance or promotion is
  the *designed* behavior — and say so in a migration comment.
- **Keep the DB rule and the changeset consistent.** If the changeset
  `validate_required`s the FK, the DB must not be able to null it. The DB
  is the last line of defense; the changeset is just the friendly error.
- When a context delete can hit a `:restrict` FK, convert the raise into a
  user-facing error with `foreign_key_constraint/3` — see
  `Tracker.delete_office/1` for the pattern (it names each dependent kind:
  sub-offices, purchases, budget line items).

### 10.4 History of the July 2026 restructuring

For anyone doing archaeology: before this change, schemas were plural
(`Offices`, `Purchases`), there was no context module (a misspelled
`FinancialTracking.Utilites` grab-bag held `get_office_with_children`),
`ExecutiveBudget.changeset` cast the association name
`:parent_line_item` (which raises) instead of `:parent_line_item_id`, and
office FKs were `:nilify_all`. If you find old branches, notes, or
notebooks referring to `Tracker.Offices`, `Tracker.Purchases`, or
`Utilities`/`Utilites` — that's the pre-restructuring world; the
functionality now lives in `FinancialTracking.Tracker`.
