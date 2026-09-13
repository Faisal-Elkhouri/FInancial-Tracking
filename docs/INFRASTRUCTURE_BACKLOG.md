# Infrastructure Backlog

Work that was deliberately **not** done during the September 2026 container
hardening, with enough context to pick each item up cold. Companion to
[`INFRASTRUCTURE.md`](INFRASTRUCTURE.md), which describes what the setup
actually *is*.

Nothing here is an oversight. Each entry records why it was deferred and what
it would take, so the decision can be revisited deliberately rather than
rediscovered.

---

## 1. Health endpoint and container healthchecks

**Status:** deferred by choice. **Effort:** small. **Unblocks:** verifiable deploys.

Without a healthcheck, Docker treats `web` as healthy the instant the process
starts, so `depends_on` is blind, a wedged-but-alive BEAM is never restarted,
and `docker compose up --wait` reports success for a container that never
served a request.

**Do it like this:**

Add a *shallow* plug in `lib/financial_tracking_web/endpoint.ex`, above
`plug FinancialTrackingWeb.Router`, so it answers even if the router or Repo is
broken:

```elixir
plug :health_check

defp health_check(%{request_path: "/health"} = conn, _opts) do
  conn |> Plug.Conn.send_resp(200, "ok") |> Plug.Conn.halt()
end

defp health_check(conn, _opts), do: conn
```

**Do not query the database in it.** A liveness probe that depends on Postgres
turns a transient database blip into Docker killing a perfectly healthy web
container - a cascading failure. If a database-aware check is wanted, make it a
*separate* `/ready` endpoint used by deploy scripts, not by `healthcheck:`.

For the Compose healthcheck itself: the runner image has **no `curl` and no
`wget`**, and `/bin/sh` is dash, which has no `/dev/tcp` - so a `CMD-SHELL` TCP
trick will not work. Two workable options:

- Add `curl` to the runner stage (~1.5 MB, and it makes production debuggable).
- Use `bash` explicitly in exec form. **Verified 2026-09-12: `bash` *is* present
  at `/usr/bin/bash` in `debian:trixie-slim`**, so this works without adding a
  package:

```yaml
healthcheck:
  test: ["CMD", "bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/4000 && printf 'GET /health HTTP/1.0\r\n\r\n' >&3 && grep -q '200' <&3"]
  interval: 15s
  timeout: 3s
  retries: 3
  start_period: 30s
```

Note Kubernetes **ignores** Docker `HEALTHCHECK` entirely - use `httpGet`
probes there instead.

---

## 2. TLS / reverse proxy

**Status:** deferred by choice. **Blocking for:** any real deployment.

`compose.prod.yaml` serves plain HTTP. That is fine for a local rehearsal and
unacceptable for a financial app on a network: session cookies and balances
would cross the wire in clear text, and `Secure`-flagged cookies would not be set.

**Do it like this:** Caddy in front, for automatic HTTPS with a two-line config.
(Traefik's label-based service discovery earns its complexity at ~15 services,
not one; nginx+certbot means owning renewal and reload yourself.)

```yaml
caddy:
  image: caddy:2
  restart: unless-stopped
  ports: ["80:80", "443:443", "443:443/udp"]
  volumes:
    - ./Caddyfile:/etc/caddy/Caddyfile:ro
    - caddy_data:/data      # certificates live here - back this up or re-issue
    - caddy_config:/config
  networks: [frontend]
```
```
money.example.com {
    encode zstd gzip
    reverse_proxy web:4000
}
```

Then, together:
- stop publishing `4000` from `web` entirely (Caddy reaches it over `frontend`);
- drop `PHX_SCHEME` / `PHX_URL_PORT` from `.env` so they fall back to `https`/`443`;
- add `force_ssl` to **`config/prod.exs`**, not `runtime.exs` - it is read at
  compile time:

```elixir
config :financial_tracking, FinancialTrackingWeb.Endpoint,
  force_ssl: [rewrite_on: [:x_forwarded_proto, :x_forwarded_host, :x_forwarded_port], hsts: true]
```

`rewrite_on` is not optional behind a proxy: without it the app sees `http` on
every request and redirect-loops.

This item also clears sobelow finding `Config.HTTPS` (see §9).

---

## 3. Content-Security-Policy

**Status:** deferred, recorded as an accepted sobelow finding. **Effort:** small, but needs UI testing.

`put_secure_browser_headers` in the `:browser` pipeline sets several headers but
no CSP. Adding one is a one-line change:

```elixir
plug :put_secure_browser_headers, %{"content-security-policy" => "..."}
```

It was deferred because a wrong CSP silently breaks LiveView (it needs
`connect-src` for the WebSocket, and Phoenix injects inline scripts), and there
is currently no UI to test against. Revisit when the first real LiveView pages
exist, and verify the socket still connects.

---

## 4. Elixir 1.20

**Status:** recommended soon. **Effort:** medium.

Currently pinned to Elixir 1.19.6 / OTP 28.5.0.6. Elixir **1.20** is current
stable, and the 1.19 line is now **security-patches-only** - it receives no bug
fixes. 1.20 also brings the gradual type system, which catches real errors at
compile time; on a financial codebase that is worth something.

Note the compatibility constraint: **Elixir 1.19 supports OTP 26-28; 1.20
supports OTP 27-29.** Moving to OTP 29 therefore *requires* 1.20.

Do it now-ish rather than later: the codebase is small, so this is the cheapest
it will ever be. Bump the `ARG` pins in `Dockerfile` **and** `Dockerfile.dev`
together (they must stay identical), plus `elixir: "~> 1.20"` in `mix.exs`.

---

## 5. Deploy-by-digest, base-image pinning, and supply chain

**Status:** deferred until a deployment target is chosen.

The single highest-value piece here is not "immutability" as an abstraction -
it is that **rollback becomes one command instead of an improvisation at 2am**.

- **Build in CI, push to GHCR, deploy by digest.** `compose.prod.yaml` already
  parameterises the image (`financial-tracking:${IMAGE_TAG:-local}`); swap it
  for `ghcr.io/<owner>/financial-tracking@${IMAGE_DIGEST:?}` and drop `build:`.
- **Pin base images by digest**, keeping the readable tag alongside:
  `ARG RUNNER_IMAGE="docker.io/debian:trixie-20260824-slim@sha256:<digest>"`.
- **Renovate** to bump those weekly (`config:best-practices` +
  `docker:pinDigests`, automerge digest-only updates). Caveat: Renovate's
  handling of `ARG`-indirected `FROM` is not documented either way - run
  `renovate --dry-run` once to confirm detection before relying on it.
- **`--sbom=true`** on the build. Nearly free, and it is what answers "am I
  affected?" in minutes during the next headline CVE. `--provenance=mode=max`
  is optional - nobody is currently consuming the attestation.
- **Trivy** scan of the pushed image, gated on HIGH/CRITICAL with
  `--ignore-unfixed` (otherwise the job gets disabled within a week).

Also re-pin the base images monthly regardless. A pinned-but-stale base is how
images silently rot; the OTP jump this hardening had to make (28.3.1 →
28.5.0.6, crossing several security fixes) is exactly that failure mode.

---

## 6. Compose 5.3+ init containers

**Status:** blocked on a Compose upgrade. **Effort:** trivial once unblocked.

This machine has Compose **5.0.2**; **5.3.0** added native `pre_start` init
containers, and current is 5.5.x. That collapses the one-shot `migrate` service
into three lines on `web`, with correct restart semantics by construction:

```yaml
web:
  pre_start:
    - command: ["/app/bin/migrate"]
```

Until then the separate `migrate` service with `restart: "no"` +
`service_completed_successfully` is the correct pattern - keep it.

Related caveat when scripting deploys: `docker compose up --wait` has open bugs
where it hangs on `service_completed_successfully`. Prefer
`docker compose run --rm migrate && docker compose up -d`, or test `--wait`
against your exact Compose version first.

---

## 7. Dialyzer

**Status:** deferred deliberately. **Cost:** the highest of any gate.

Not added to `mix ci` because it adds 5-10 minutes per run and needs PLT
caching to be tolerable. When added, run it as a **separate job on `master`
only**, not on every push, with `priv/plts` cached and keyed on `mix.lock`:

```elixir
# mix.exs project/0
dialyzer: [plt_local_path: "priv/plts", plt_core_path: "priv/plts"]
```

Community practice is to start with `--ignore-exit-status` and burn down the
existing findings rather than blocking merges on day one.

---

## 8. Zero-downtime deploys

**Status:** explicitly not worth it yet.

`docker compose up -d` stops the old container before starting the new one, so
there is a downtime window equal to BEAM boot time. Compose has no rolling
update for a single host (`deploy.update_config` is parsed and ignored outside
Swarm).

A few seconds of downtime on a deploy you schedule yourself costs nothing.
Revisit when a user *other than you* would notice, and then look at
[`docker rollout`](https://github.com/Wowu/docker-rollout) (a small Compose
plugin) or **Kamal 2** (health-checked blue-green over SSH, well-trodden for
Phoenix) rather than Swarm.

The cheap 80% is already available: add the healthcheck from §1, then deploy
with `docker compose up -d --wait`, which at least *fails loudly* when the new
container never becomes healthy.

---

## 9. Accepted sobelow findings

`.sobelow-skips` records findings we have consciously accepted, so that **new**
findings still fail CI. Currently:

| Finding | Why accepted | Cleared by |
|---|---|---|
| `Config.HTTPS` - HTTPS Not Enabled | No TLS terminator yet; deployment target undecided | §2 |
| `Config.CSP` - Missing Content-Security-Policy | No UI to validate a policy against yet | §3 |

**Re-run `mix sobelow --mark-skip-all` only deliberately.** It accepts
everything currently outstanding, which is exactly how a real finding gets
silently buried. Prefer fixing, or adding a single targeted skip.

**Regenerate skips inside the container, never on the Windows host.** The skip
entries are `Finding,path:line,FINGERPRINT`, and the fingerprint incorporates
the file path. Generating them on Windows produced `c:/config/prod.exs`, whose
fingerprint does not match the `config/prod.exs` that Linux sees — so the skips
were silently ignored in CI and the build failed on findings that were supposed
to be accepted. Always:

```sh
docker compose run --rm --entrypoint sh test -c "mix sobelow --mark-skip-all"
```

---

## 10. Smaller items

- **`COPY --link`** on the final `COPY` in the Dockerfile. Avoids re-uploading
  the ~40 MB release layer when only the runner stage changes. Requires the
  numeric `--chown` we already have (`--link` copies onto a scratch filesystem
  with no `/etc/passwd`, so a *named* owner fails). Left out deliberately: it
  is a build-cache optimisation with a reported parent-directory ownership
  quirk, and it was not worth stacking onto a release path that had never
  produced a working image. Now that a green baseline exists, it is a one-line
  change - verify `/app` ownership afterwards.
- **Off-host backup shipping.** `scripts/pg-backup.sh` writes to `./backups` on
  the same host as the database, which is not yet a backup. Add restic/rclone
  to object storage. Note the `backup` service is on the `internal: true`
  `backend` network and would need `frontend` too in order to reach the internet.
- **Scheduled restore drills.** `scripts/pg-restore.sh` has a
  `RESTORE_TARGET_DB=restore_drill` mode precisely so this can be automated. A
  backup that has never been restored is a hypothesis.
- **Managed Postgres** (Neon / RDS / Fly Postgres). Would retire the backup
  work, the major-version upgrade hazard, and half the resource-limit tuning -
  by *removing* code rather than adding it. If taken, TLS to the database
  becomes mandatory, and note Erlang's `:ssl` defaults to `verify: :verify_none`
  (encryption without authentication) - set `verify: :verify_peer` with
  `cacerts: :public_key.cacerts_get()` and a charlist `server_name_indication`.
- **Native PostgreSQL on the dev host.** A local PostgreSQL currently owns
  `0.0.0.0:5432`, which is why the dev stack publishes `15432` by default
  (`DB_HOST_PORT`). Worth knowing: any `mix` command run *on the host* talks to
  that native server, not the container. Stopping it and setting
  `DB_HOST_PORT=5432` would remove the surprise.
- **Stale container from the pre-`name:` era.** `financialtracking-db-1`
  (exited, 6 weeks old) predates the explicit Compose project name. Safe to
  remove once you have confirmed its volume holds nothing you want.

---

## Explicitly rejected (for now)

Recorded so they are not re-litigated:

- **Kubernetes, Swarm, service meshes.** One app, one database. Compose on one
  host is the correct architecture. (The image is nonetheless k8s-*ready*:
  numeric non-root UID, read-only rootfs, no baked-in distribution cookie.)
- **Vault / AWS Secrets Manager / SOPS.** File-backed Compose secrets are the
  right rung on that ladder here. The gap from "plain env var" to "file secret"
  is large; the gap from "file secret" to Vault is mostly ceremony at this scale.
- **pgBackRest / WAL-G with PITR.** Nightly verified dumps cover most of the
  realistic disaster space at a fraction of the operational cost. Escalate when
  "up to 24 hours of lost transactions" stops being acceptable - at which point
  managed Postgres is likely the better answer than either.
- **Coverage thresholds, mutation testing, load testing in CI.**
- **Running three vulnerability scanners.** One you act on beats three you ignore.
