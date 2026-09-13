# Setup Log

A record of how the Docker + Phoenix + PostgreSQL setup was assembled and
verified. For day-to-day usage instructions see [`README.md`](README.md).

## Goal

Stand up a Phoenix (Elixir) application backed by PostgreSQL that runs both
locally and fully containerized with Docker, using **standard generators and
tooling only** — nothing hand-rolled.

## Environment

| Tool   | Version                          |
| ------ | -------------------------------- |
| Elixir | 1.19.5 (compiled with OTP 28)    |
| Erlang | OTP 28 / erts 16.2               |
| Docker | 29.2.0                           |
| OS     | Windows 11                       |

## Steps performed

1. **Phoenix app generated** with the standard generator (Ecto + PostgreSQL are
   the defaults):

   ```bash
   mix phx.new financial_tracking
   ```

   Produced `lib/`, `config/`, `assets/`, `priv/`, `mix.exs`, and the Ecto `Repo`
   wired for PostgreSQL.

2. **Production release + Dockerfile generated** with the official task:

   ```bash
   mix phx.gen.release --docker
   ```

   Produced the multi-stage `Dockerfile`, `.dockerignore`, and the
   `rel/overlays/bin/{migrate,server}` release scripts.

3. **Docker Compose stacks added** so Postgres and the app run together:
   - `compose.yaml` — dev: Postgres 17 + app via `Dockerfile.dev`, with
     code reloading and named volumes for `deps`/`_build`.
   - `compose.prod.yaml` — prod: Postgres 17 + the release image, running
     `bin/migrate` then `bin/server` on boot.
   - `Dockerfile.dev` — dev image keeping the full Elixir toolchain plus
     `inotify-tools` for live reload.

4. **Config made environment-driven** so the same code runs locally and in
   containers: `config/dev.exs` and `config/runtime.exs` read the `DATABASE_*`
   and prod secret variables, with `.env.example` as the tracked template
   (`.env` is git-ignored).

5. **Documentation written** — replaced the default Phoenix `README.md` with
   project-specific setup, run, and configuration instructions.

## Verification

- **Compile:** `mix compile` succeeds. The only output is a Windows-only
  symlink warning for LiveView colocated JS (non-fatal).
- **Full dev stack:** `docker compose up --build -d` was run end to end:
  - Web image built; Postgres 17 pulled and reported **healthy**.
  - App fetched deps, **created the database, ran migrations** ("Migrations
    already up" on the second boot).
  - **Phoenix served** via Bandit at `0.0.0.0:4000`; esbuild + Tailwind
    watchers running.
  - **`HTTP 200`** returned from the host at <http://localhost:4000>.
- **Teardown:** `docker compose down` removed both containers and the network
  cleanly. Data volumes (`pgdata_dev`, `deps`, `build`) were intentionally
  retained for fast subsequent boots; use `docker compose down -v` to drop them.

### Known non-error log noise

- `watchman: not found` — Phoenix falls back to the installed `inotify-tools`.
- LiveView colocated-JS symlink `:eperm` warning — Windows-only, harmless.
