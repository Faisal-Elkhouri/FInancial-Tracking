# syntax=docker/dockerfile:1

# Find eligible builder and runner images on Docker Hub. We suggest Debian/Ubuntu
# instead of Alpine to avoid production compatibility issues (such as DNS
# resolution failures, and dynamically linked NIFs/precompiled binaries).
#
# Valid tag combinations can be found at https://bob.hex.pm/docker
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the build image
#   - https://hub.docker.com/_/debian/tags - for the release image
#   - https://pkgs.org/ - resource for finding needed packages
#
# Keep these pins identical to Dockerfile.dev (see docs/INFRASTRUCTURE.md §9.6)
# and re-pin monthly - a pinned-but-stale base is how images silently rot.
ARG ELIXIR_VERSION=1.19.6
ARG OTP_VERSION=28.5.0.6
ARG DEBIAN_VERSION=trixie-20260824-slim

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# install build dependencies
# Cache mounts keep the apt lists/archives out of the layer while still making
# repeat builds fast. `sharing=locked` serialises concurrent builds.
RUN rm -f /etc/apt/apt.conf.d/docker-clean \
  && echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
  && apt-get install -y --no-install-recommends build-essential git

# prepare build dir
WORKDIR /app

# install hex + rebar
# NOTE: do not cache-mount /root/.mix - the Hex archive is installed there by
# this RUN, and mounting it in a later RUN would shadow the archive away.
RUN mix local.hex --force \
  && mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
# Only the *package* caches are mounted. deps/ and _build/ deliberately are NOT:
# "Mounted files are not persisted in the final image", so a cache-mounted
# _build would make `mix release` write into the mount and the final
# `COPY --from=builder .../rel/...` copy nothing at all.
COPY mix.exs mix.lock ./
RUN --mount=type=cache,target=/root/.hex,sharing=locked \
    --mount=type=cache,target=/root/.cache/rebar3,sharing=locked \
    mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

RUN mix assets.setup

COPY priv priv

COPY lib lib

# Compile the release BEFORE assets: LiveView 1.1 colocated hooks are extracted
# to _build/$MIX_ENV/phoenix-colocated during compilation, and esbuild needs them.
RUN mix compile

COPY assets assets

# compile assets
RUN mix assets.deploy

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

# --chmod is belt-and-braces with the git index mode (100755): it guarantees the
# release scripts are executable regardless of how the build context was
# produced. Windows/NTFS carries no exec bit, and `mix release` copies overlays
# with File.cp_r!/2, which preserves the source mode verbatim - so a 0644 script
# in the context becomes a 0644 /app/bin/server and the container dies with
# "permission denied".
COPY --chmod=0755 rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE} AS final

# libstdc++6 / openssl / libncurses6 / ca-certificates is the minimal set a BEAM
# release needs on Debian. The `locales` package and locale-gen are deliberately
# NOT installed: C.UTF-8 ships in libc-bin (Essential on every Debian system)
# and is sufficient for the only two things the BEAM uses the locale for -
# filename encoding (+fna) and standard_io encoding. Saves ~10MB and a layer.
RUN apt-get update \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Must remain a UTF-8 locale - do not simply drop these.
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

WORKDIR "/app"

# set runner ENV
ENV MIX_ENV="prod"

# Do not start EPMD or a distribution listener. `mix release` otherwise defaults
# RELEASE_DISTRIBUTION to "sname" and RELEASE_COOKIE to the value baked into
# releases/COOKIE at build time - i.e. a remote-code-execution surface guarded
# by a static secret that anyone with pull access can extract from the image.
# Nothing here clusters (DNS_CLUSTER_QUERY is unset). If clustering is ever
# needed: set this to "name" and supply RELEASE_COOKIE from a runtime secret.
ENV RELEASE_DISTRIBUTION=none

# Keep every runtime write inside /tmp so the image can run with a read-only
# root filesystem. RELEASE_TMP is NOT optional: because config/runtime.exs
# exists, the release first boots in interactive mode to compute a config file
# and writes it to this directory - it defaults to $RELEASE_ROOT/tmp (= /app/tmp),
# so a read-only /app without this line means the release does not boot at all.
ENV RELEASE_TMP=/tmp
ENV ERL_CRASH_DUMP=/tmp/erl_crash.dump
ENV ERL_CRASH_DUMP_SECONDS=10

# Only copy the final release from the build stage.
#
# The UID is numeric on purpose. Kubernetes' `runAsNonRoot: true` cannot read
# /etc/passwd at admission time, so an image whose USER is a *name* fails with
# "container has runAsNonRoot and image has non-numeric user (nobody), cannot
# verify user is non-root". 65534 is Debian's `nobody`.
# Group 0 with group-read is the OpenShift arbitrary-UID convention.
#
# /app itself stays root-owned (the generator's `chown nobody /app` is gone):
# the app has no reason to be able to rewrite its own code.
COPY --from=builder --chown=65534:0 /app/_build/${MIX_ENV}/rel/financial_tracking ./

USER 65534:65534

# Documentation only; publishing is the orchestrator's job.
EXPOSE 4000

# Provenance. NOTE: LABEL writes the image *config*, not OCI manifest
# *annotations* - pass `docker buildx build --annotation ...` as well if a tool
# you use reads annotations.
# DEBIAN_VERSION is a pre-FROM global ARG, so it must be re-declared inside this
# stage to be usable here (otherwise it silently expands to an empty string).
ARG DEBIAN_VERSION
ARG VCS_REF
ARG BUILD_DATE
ARG VERSION
LABEL org.opencontainers.image.title="financial_tracking" \
      org.opencontainers.image.description="Financial tracking (Phoenix/LiveView)" \
      org.opencontainers.image.source="https://github.com/Faisal-Elkhouri/FInancial-Tracking" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.base.name="docker.io/debian:${DEBIAN_VERSION}"

# The release's own scripts already `exec` at every hop (bin/server -> release
# CLI -> bin/elixir -> erl -> erlexec -> beam.smp), so exec-form CMD puts
# beam.smp at PID 1 and SIGTERM drains cleanly. Do NOT override this with
# `command: sh -c "..."` in Compose - dash never execs from `sh -c`, and the
# kernel silently DISCARDS SIGTERM sent to a PID-1 process with the default
# disposition, so the container ignores docker stop and is SIGKILLed instead.
CMD ["/app/bin/server"]
