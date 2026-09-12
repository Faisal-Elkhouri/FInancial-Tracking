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
  # base64 then strip the URL-hostile characters. The app reads these from a
  # file rather than a URL, so encoding is not strictly required - but keeping
  # them URL-safe means they can also be pasted into a DATABASE_URL without
  # tripping over percent-encoding.
  openssl rand -base64 "$bytes" | tr -d '\n=+/' > "secrets/$name"
  chmod 600 "secrets/$name"
  echo "  wrote secrets/$name"
}

echo "Generating secrets in ./secrets (gitignored):"
gen db_password 32
gen secret_key_base 80

echo
echo "Done. These are mounted read-only into the containers as files, so the"
echo "values do not appear in 'docker inspect' or 'docker compose config'."
