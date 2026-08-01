#!/usr/bin/env bash
# =====================================================================
# scripts/db.sh — apply a migration to the hosted Supabase database.
# =====================================================================
#   ./scripts/db.sh supabase/legacy-migrations/migration-p7-savings-schedule.sql
#                                                       apply a migration
#   ./scripts/db.sh --check                             connection + schema
#   ./scripts/db.sh --query "select 1"                  ad-hoc read
#   ./scripts/db.sh --dump                              schema -> supabase/schema.sql
#
# The connection string lives in .env.db.local, which .gitignore already
# excludes via the `.env*.local` rule. It is never printed, never passed on
# the command line (so it cannot leak into `ps` or shell history), and never
# committed. Get it from the Supabase dashboard:
#
#   Project Settings -> Database -> Connection string -> URI
#
# Use the SESSION POOLER URI if the direct one will not connect; direct
# connections are IPv6-only on newer projects.
#
# Guardrails, deliberate:
#   * ON_ERROR_STOP=1 — psql aborts on the first error instead of ploughing
#     on and leaving the schema half-migrated.
#   * Only .sql files inside this repo may be applied, so what runs is always
#     something that is in git and reviewable.
#   * Every migration here already wraps itself in begin/commit.
# =====================================================================
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$REPO/.env.db.local"
PSQL="${PSQL_BIN:-/opt/homebrew/opt/libpq/bin/psql}"
PGDUMP="${PGDUMP_BIN:-/opt/homebrew/opt/libpq/bin/pg_dump}"

case "${1:-}" in
  '' | --help | -h)
    sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

if [[ ! -f "$ENV_FILE" ]]; then
  cat >&2 <<EOF
No $ENV_FILE.

Create it with the connection URI from the Supabase dashboard
(Project Settings -> Database -> Connection string -> URI):

  SUPABASE_DB_URL=postgresql://postgres.<ref>:<password>@<host>:5432/postgres

It is gitignored. Do not paste that URI into a chat -- it contains the
database password.
EOF
  exit 1
fi

# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a
: "${SUPABASE_DB_URL:?SUPABASE_DB_URL is not set in .env.db.local}"

if [[ ! -x "$PSQL" ]]; then
  echo "psql not found at $PSQL. brew install libpq, or set PSQL_BIN." >&2
  exit 1
fi

run() { PGPASSWORD='' "$PSQL" "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 "$@"; }

case "${1:-}" in
  --check)
    echo "Connecting..."
    run -qAt -c "select 'connected to ' || current_database() || ' as ' || current_user;"
    echo
    echo "Applied migrations, inferred from the schema:"
    run -c "
      select
        to_regclass('public.savings_periods')                is not null as p7_savings_periods,
        (select count(*) from information_schema.columns
          where table_name = 'savings_calculations'
            and column_name like 'schedule_%')                           as p7_schedule_cols,
        (select count(*) from public.sourcing_events
          where id in ('00000021-0000-4000-8000-000000000009',
                       '00000021-0000-4000-8000-000000000010'))          as p8_projects;"
    echo "Policies on savings_periods (should be four, none fail-open):"
    run -c "select policyname, cmd, qual is not distinct from 'true' as fail_open
              from pg_policies
             where schemaname = 'public' and tablename = 'savings_periods'
             order by policyname;"
    ;;
  --query)
    [[ $# -ge 2 ]] || { echo "usage: $0 --query \"select ...\"" >&2; exit 1; }
    run -c "$2"
    ;;
  --dump)
    # Pull the LIVE schema into git. Until this existed, every migration was
    # written against a reconstructed guess at the schema -- P0 says so in its
    # own header -- and there was no way to know what a DROP would really take
    # with it. Structure only: no rows, no data, nothing confidential.
    [[ -x "$PGDUMP" ]] || { echo "pg_dump not found at $PGDUMP. brew install libpq, or set PGDUMP_BIN." >&2; exit 1; }
    OUT="${2:-$REPO/supabase/schema.sql}"
    echo "Dumping public schema..."
    {
      echo "-- ====================================================================="
      echo "-- supabase/schema.sql -- GENERATED. Do not edit by hand."
      echo "--"
      echo "--   regenerate:  ./scripts/db.sh --dump"
      echo "--"
      echo "-- The live structure of the public schema, pulled straight from the"
      echo "-- hosted database. Structure only -- no rows. Read this before writing"
      echo "-- a migration, and re-dump after applying one, so the repo and the"
      echo "-- database cannot drift apart unnoticed."
      echo "--"
      echo "-- Supabase-managed schemas (auth, storage, realtime, ...) are excluded"
      echo "-- deliberately: they are not ours to change."
      echo "--"
      echo "-- ONE CONSEQUENCE OF THAT EXCLUSION, so it is not mistaken for dead"
      echo "-- code: public.handle_new_user() appears below with nothing calling it."
      echo "-- It is fired by the trigger on_auth_user_created on auth.users, which"
      echo "-- lives in an excluded schema. It is what creates a profiles row when"
      echo "-- someone signs up. Dropping it would silently break registration."
      echo "-- ====================================================================="
      echo
      # pg_dump 18 stamps a RANDOM token into \restrict / \unrestrict on every
      # run. Left in, two dumps of an identical database differ, and the whole
      # point of committing this file -- noticing real drift in a diff -- is
      # lost in the noise. They are a psql restore-time guard; this file is a
      # reference snapshot, not a restore artifact, so they are stripped to
      # keep the output deterministic.
      "$PGDUMP" "$SUPABASE_DB_URL" \
        --schema-only --schema=public --no-owner --no-tablespaces \
        | grep -vE '^\\(un)?restrict '
    } > "$OUT"
    echo "Wrote $OUT ($(wc -l < "$OUT" | tr -d ' ') lines)"
    ;;
  *)
    FILE="$1"
    [[ -f "$FILE" ]] || { echo "No such file: $FILE" >&2; exit 1; }
    ABS="$(cd "$(dirname "$FILE")" && pwd)/$(basename "$FILE")"
    case "$ABS" in
      "$REPO"/*) ;;
      *) echo "Refusing: $ABS is outside $REPO." >&2; exit 1 ;;
    esac
    [[ "$ABS" == *.sql ]] || { echo "Refusing: not a .sql file." >&2; exit 1; }

    # Clipboard paste into the Supabase editor mangles UTF-8; an em-dash once
    # corrupted a whole seed. Keep the same rule here so both paths agree.
    if LC_ALL=C grep -qP '[^\x00-\x7F]' "$ABS" 2>/dev/null; then
      echo "Refusing: $FILE is not pure ASCII." >&2
      exit 1
    fi

    echo "Applying $(basename "$FILE")..."
    run -f "$ABS"
    echo "Done. Run '$0 --check' to confirm."
    ;;
esac
