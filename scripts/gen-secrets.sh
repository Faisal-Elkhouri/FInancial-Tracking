#!/bin/sh
# Generate the file-backed secrets that compose.prod.yaml mounts at
# /run/secrets/<name>. Safe to re-run: existing files are never overwritten.
#
#   ./scripts/gen-secrets.sh
#
# The ./secrets directory is gitignored. These values are for the LOCAL
# production rehearsal only - a real deployment must generate its own, on that
# host, and never reuse these.
#
# Rotating secret_key_base invalidates every session and signed token.
set -eu

cd -P -- "$(dirname -- "$0")/.."
mkdir -p secrets

# gen <name> <raw-bytes-of-entropy>
#
# The resulting string is roughly 4/3 the byte count, minus the characters
# stripped below. Phoenix requires secret_key_base to be AT LEAST 64 bytes and
# raises at boot otherwise, so keep that argument comfortably above 48.
gen() {
  name="$1"
  bytes="$2"
  if [ -f "secrets/$name" ]; then
    echo "  secrets/$name already exists, leaving it alone"
    return
  fi

  # The character class here is load-bearing in two ways.
  #
  # 1. CR (\r) must be stripped, not just LF. On Windows, openssl emits CRLF,
  #    and deleting only \n leaves a trailing carriage return inside the
  #    secret. That byte is invisible in every tool that displays it, and the
  #    two sides of the system disagree about it: Elixir's String.trim/1 strips
  #    it, while shell command substitution does not. The result is "password
  #    authentication failed" between an app and a database that were handed
  #    what looks like an identical secret.
  #
  # 2. =+/ are stripped so the value stays URL-safe. The app reads these from a
  #    file rather than a URL, so it is not strictly required - but it means a
  #    value can also be pasted into a DATABASE_URL without percent-encoding.
  openssl rand -base64 "$bytes" | tr -d '\r\n=+/' > "secrets/$name"
  chmod 600 "secrets/$name"

  # Fail loudly rather than shipping a secret with a stray control character.
  if LC_ALL=C grep -q '[^A-Za-z0-9]' "secrets/$name"; then
    echo "  ERROR: secrets/$name contains unexpected characters" >&2
    exit 1
  fi
  echo "  wrote secrets/$name ($(wc -c < "secrets/$name" | tr -d ' ') bytes)"
}

echo "Generating secrets in ./secrets (gitignored):"
gen db_password 32
gen secret_key_base 80

echo
echo "Done. These are mounted read-only into the containers as files, so the"
echo "values do not appear in 'docker inspect' or 'docker compose config'."
