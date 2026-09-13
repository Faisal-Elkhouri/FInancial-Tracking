#!/bin/sh
# Entrypoint for the one-shot `test` service.
#
# Why this exists: `deps` is a named volume shared with `web`, and it is only
# populated from the image the first time it is created. When mix.lock changes
# afterwards, the volume still holds the old packages and every mix command
# fails with "lock mismatch: the dependency is out of date".
#
# Syncing here rather than in the service's `command:` means any command works
# unchanged - `mix test`, `mix ci`, `mix precommit`, `mix deps.tree` - instead
# of each caller having to remember the prefix.
#
# `exec` on the last line so the mix process replaces this shell and receives
# signals directly.
set -eu

mix deps.get

exec "$@"
