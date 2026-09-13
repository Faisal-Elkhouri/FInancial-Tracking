#!/bin/sh
# Restore a dump produced by pg-backup.sh.
#
#   # list what is available
#   docker compose -f compose.prod.yaml run --rm --entrypoint sh backup -c 'ls -lh /backups'
#
#   # DRILL (recommended): restore into a throwaway database and inspect it
#   docker compose -f compose.prod.yaml run --rm \
#     -e RESTORE_TARGET_DB=restore_drill \
#     --entrypoint /usr/local/bin/pg-restore backup /backups/<file>.dump
#
#   # REAL restore, over the live database (requires CONFIRM=yes)
#   docker compose -f compose.prod.yaml run --rm -e CONFIRM=yes \
#     --entrypoint /usr/local/bin/pg-restore backup /backups/<file>.dump
#
# A backup you have never restored is a hypothesis, not a backup. Run the drill
# form on a schedule; it is the only thing that proves the dumps are usable.
set -eu

ARCHIVE="${1:-}"
if [ -z "$ARCHIVE" ]; then
  echo "usage: pg-restore <path-to-.dump>" >&2
  exit 64
fi
if [ ! -r "$ARCHIVE" ]; then
  echo "ERROR: cannot read $ARCHIVE" >&2
  exit 66
fi

: "${PGHOST:?PGHOST is required}"
: "${PGUSER:?PGUSER is required}"
: "${PGDATABASE:?PGDATABASE is required}"

PASSWORD_FILE="${PGPASSWORD_FILE:-/run/secrets/db_password}"
if [ -r "$PASSWORD_FILE" ]; then
  PGPASSWORD="$(cat "$PASSWORD_FILE")"
  export PGPASSWORD
fi

TARGET_DB="${RESTORE_TARGET_DB:-$PGDATABASE}"

echo "Archive: $ARCHIVE"
echo "Target : $TARGET_DB on $PGHOST"
echo

if ! pg_restore --list "$ARCHIVE" > /dev/null 2>&1; then
  echo "ERROR: $ARCHIVE is not a readable pg_dump archive." >&2
  exit 1
fi

if [ "$TARGET_DB" = "$PGDATABASE" ]; then
  if [ "${CONFIRM:-}" != "yes" ]; then
    cat >&2 <<'WARN'
REFUSING TO PROCEED.

This would restore over the LIVE database and drop existing objects.
If that is genuinely what you want, re-run with CONFIRM=yes.

Safer: set RESTORE_TARGET_DB=restore_drill to restore into a scratch
database instead, which is how you should be testing backups anyway.
WARN
    exit 1
  fi
  echo "CONFIRM=yes given - restoring over the live database."
else
  echo "Drill mode: creating scratch database $TARGET_DB (dropped first if present)."
  dropdb --if-exists "$TARGET_DB"
  createdb "$TARGET_DB"
fi

# --clean --if-exists drops objects before recreating them, so a restore over
# an existing database is idempotent rather than a pile of "already exists".
# --no-owner/--no-privileges keep it portable across differing role names.
pg_restore \
  --dbname="$TARGET_DB" \
  --clean --if-exists \
  --no-owner --no-privileges \
  --exit-on-error \
  "$ARCHIVE"

echo
echo "Restore complete. Sanity check:"
psql --dbname="$TARGET_DB" --tuples-only --command \
  "select 'offices=' || (select count(*) from offices)
       || ' purchases=' || (select count(*) from purchases)
       || ' executive_budget=' || (select count(*) from executive_budget)
       || ' schema_migrations=' || (select count(*) from schema_migrations);"
