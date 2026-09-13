# FinancialTracking

A [Phoenix](https://www.phoenixframework.org/) (Elixir) web application backed by
PostgreSQL, packaged to run either directly on your machine or fully containerized
with Docker. This README documents how the project was set up and how to run it.

## Stack

| Layer      | Choice                                                        |
| ---------- | ------------------------------------------------------------ |
| Language   | Elixir 1.19 / Erlang OTP 28                                  |
| Framework  | Phoenix 1.8 (Bandit adapter, LiveView)                       |
| Database   | PostgreSQL 17 (via Ecto + Postgrex)                          |
| Assets     | esbuild + Tailwind (managed by Mix, no Node toolchain needed) |
| Containers | Docker + Docker Compose (separate dev and prod stacks)       |

## Prerequisites

You only need **one** of the following:

- **Docker path:** [Docker Desktop](https://www.docker.com/products/docker-desktop/)
  (Docker Engine + Compose v2). Nothing else required.
- **Local path:** Elixir 1.19 / OTP 28, plus a PostgreSQL 17 server you can reach.

---

## Quick start with Docker (recommended)

The development stack runs Postgres and the Phoenix app (with live code reloading)
together. The defaults work out of the box.

```bash
cp .env.example .env        # optional for dev; defaults are fine
docker compose up           # builds the image, starts Postgres + the app
```

Then open <http://localhost:4000>.

On first boot the `web` service fetches deps, creates the database, runs
migrations, and starts the server. Source is bind-mounted, so edits on the host
trigger live reload inside the container.

To stop: `Ctrl-C`, then `docker compose down` (add `-v` to also drop the
database volume).

## Quick start without Docker

```bash
mix setup                   # deps.get + ecto.setup + assets setup/build
mix phx.server              # or: iex -S mix phx.server
```

> **Not the supported path.** `config/dev.exs` and `config/test.exs` default
> `DATABASE_HOST` to `db`, the Compose service name, because this project is
> Docker-first (see [`docs/INFRASTRUCTURE.md`](docs/INFRASTRUCTURE.md)). To run
> on the host you must set `DATABASE_HOST=localhost` explicitly, along with the
> other `DATABASE_*` variables.
>
> Be careful here: if you have a **native PostgreSQL** installed, it probably
> already owns `localhost:5432`, and host-run `mix` commands will silently talk
> to *that* server rather than the container's — two databases that look
> identical and diverge. That is also why the dev stack publishes the container
> on `15432` by default (`DB_HOST_PORT`).

Then open <http://localhost:4000>.

---

## Production with Docker

`compose.prod.yaml` builds a slim, self-contained OTP **release** (via the
multi-stage `Dockerfile`), runs database migrations on boot, then starts the
server. Unlike dev, it requires real secrets.

```bash
cp .env.example .env
# In .env, set:
#   SECRET_KEY_BASE   -> generate with: mix phx.gen.secret
#   DATABASE_PASSWORD -> a real password (not the dev default)
#   PHX_HOST          -> the hostname users will reach the app at

docker compose -f compose.prod.yaml up --build -d
```

Then open <http://localhost:4000> (or your `PHX_HOST`).

The compose file refuses to start if `SECRET_KEY_BASE` or `DATABASE_PASSWORD`
are missing, so misconfiguration fails fast rather than silently.

---

## Configuration

Configuration is driven by environment variables, which Docker Compose loads
automatically from `.env`. The same variables work for a local (non-Docker) run.

| Variable            | Used in    | Default                    | Notes                                          |
| ------------------- | ---------- | -------------------------- | ---------------------------------------------- |
| `DATABASE_HOST`     | dev        | `localhost` (`db` in compose) | Postgres host                               |
| `DATABASE_USER`     | dev / prod | `postgres`                 |                                                |
| `DATABASE_PASSWORD` | dev / prod | `postgres`                 | **Required** in prod                           |
| `DATABASE_NAME`     | dev / prod | `financial_tracking_dev` / `_prod` |                                        |
| `DATABASE_URL`      | prod       | built from the vars above  | Full `ecto://…` URL the release reads          |
| `SECRET_KEY_BASE`   | prod       | —                          | **Required**; `mix phx.gen.secret`             |
| `PHX_HOST`          | prod       | `localhost`                | Public hostname for generated URLs             |
| `PORT`              | both       | `4000`                     | HTTP port                                      |

- `config/dev.exs` reads the `DATABASE_*` vars (falling back to local defaults),
  which is how the dev container points the app at the `db` service.
- `config/runtime.exs` reads `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`, and
  `PORT` at release start — the standard Phoenix releases pattern.
- `.env` is git-ignored; `.env.example` is the tracked template.

---

## How this project was set up

These are the steps that produced the repository, following the standard Phoenix
and Docker tooling (nothing hand-rolled):

1. **Generated the Phoenix app** with the project generator (Ecto + Postgres are
   the defaults):

   ```bash
   mix phx.new financial_tracking
   ```

   This produced `lib/`, `config/`, `assets/`, `priv/`, `mix.exs`, and the Ecto
   `Repo` wired for PostgreSQL.

2. **Generated the production release + Dockerfile** with the official task:

   ```bash
   mix phx.gen.release --docker
   ```

   This created the multi-stage `Dockerfile`, the `.dockerignore`, and the
   `rel/overlays/bin/{migrate,server}` release scripts used in production.

3. **Added the Docker Compose stacks** so Postgres and the app run together:
   - `compose.yaml` — development: Postgres 17 + the app via `Dockerfile.dev`
     with code reloading and named volumes for `deps`/`_build`.
   - `compose.prod.yaml` — production: Postgres 17 + the release image,
     running `bin/migrate` then `bin/server` on boot.
   - `Dockerfile.dev` — a dev image that keeps the full Elixir toolchain (plus
     `inotify-tools` for live reload).

4. **Made config environment-driven** so the same code runs locally and in
   containers: `config/dev.exs` and `config/runtime.exs` read the `DATABASE_*`
   and prod secret variables shown above, with `.env.example` as the template.

5. **Verified** the app compiles (`mix compile`) and the database lifecycle is
   handled (`mix ecto.setup` locally; migrations on boot in the prod stack).

## Project layout

```
lib/financial_tracking/        # business/domain code + Repo + Application
lib/financial_tracking_web/    # web layer (router, controllers, components)
config/                        # config.exs, dev/test/prod.exs, runtime.exs
priv/repo/migrations/          # Ecto migrations
assets/                        # JS/CSS (built by esbuild + Tailwind)
rel/overlays/bin/              # release migrate/server scripts
Dockerfile                     # production OTP release (multi-stage)
Dockerfile.dev                 # development image
compose.yaml             # dev stack (default)
compose.prod.yaml        # production stack
.env.example                   # environment variable template
```

## Common commands

```bash
# Local
mix setup                      # install deps + set up DB + build assets
mix phx.server                 # run the server
mix test                       # run the test suite (creates a test DB)
mix ecto.reset                 # drop + recreate + migrate + seed
mix precommit                  # compile (warnings as errors) + format + test

# Docker (dev)
docker compose up              # start Postgres + app
docker compose down            # stop (add -v to drop the DB volume)
docker compose logs -f web     # tail app logs

# Docker (prod)
docker compose -f compose.prod.yaml up --build -d
docker compose -f compose.prod.yaml down
```

## Learn more

- Phoenix: <https://hexdocs.pm/phoenix/overview.html>
- Phoenix deployment with releases: <https://hexdocs.pm/phoenix/releases.html>
- Ecto: <https://hexdocs.pm/ecto>
