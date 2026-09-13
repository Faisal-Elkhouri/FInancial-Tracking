#!/bin/sh
# Take a compressed, custom-format dump of the production database.
#
#   docker compose -f compose.prod.yaml run --rm backup
#
# Custom format (-Fc) rather than plain SQL because it is compressed, and
# because pg_restore can then restore selectively and in parallel.
#
# IMPORTANT: libpq (pg_dump, psql, pg_restore) does NOT support the `_FILE`
# environment variable convention. That convention belongs to the postgres
# image's *entrypoint*, which is why the db service can use
# POSTGRES_PASSWORD_FILE but this script cannot use PGPASSWORD_FILE. The secret
# has to be read explicitly.
set -eu

: "${PGHOST:?PGHOST is required}"
: "${PGUSER:?PGUSER is required}"
: "${PGDATABASE:?PGDATABASE is required}"

PASSWORD_FILE="${PGPASSWORD_FILE:-/run/secrets/db_password}"
if [ -r "$PASSWORD_FILE" ]; then
  PGPASSWORD="$(cat "$PASSWORD_FILE")"
  export PGPASSWORD
fi

RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
DEST="${BACKUP_DIR:-/backups}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
TARGET="$DEST/${PGDATABASE}-${STAMP}.dump"

mkdir -p "$DEST"

echo "Dumping $PGDATABASE from $PGHOST -> $TARGET"

# Write to a .partial file first and rename on success, so an interrupted dump
# can never be mistaken for a usable backup by the retention sweep below.
pg_dump --format=custom --compress=9 --file="$TARGET.partial"
mv "$TARGET.partial" "$TARGET"

SIZE="$(wc -c < "$TARGET")"
if [ "$SIZE" -lt 1024 ]; then
  echo "ERROR: dump is only ${SIZE} bytes - refusing to treat this as a backup." >&2
  exit 1
fi
echo "Wrote $TARGET (${SIZE} bytes)"

# Verify the dump is actually readable before trusting it. `pg_restore --list`
# parses the archive's table of contents without touching any database, so it
# is a cheap integrity check that catches truncation and corruption.
if ! pg_restore --list "$TARGET" > /dev/null 2>&1; then
  echo "ERROR: $TARGET is not a readable pg_dump archive." >&2
  exit 1
fi
echo "Verified: archive table of contents is readable."

echo "Pruning dumps older than ${RETENTION_DAYS} days in $DEST"
find "$DEST" -name "${PGDATABASE}-*.dump" -type f -mtime "+${RETENTION_DAYS}" -print -delete || true
find "$DEST" -name "*.partial" -type f -mtime +1 -print -delete || true

echo
echo "Done. REMINDER: this dump is still on the same host as the database."
echo "A backup that shares a disk with its source is not a backup - copy it"
echo "off-host (restic/rclone to object storage) and test a restore."
