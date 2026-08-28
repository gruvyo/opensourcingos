#!/usr/bin/env bash

set -euo pipefail

schema_body="$(mktemp "${TMPDIR:-/tmp}/opensourcingos-database-schema-body.XXXXXX")"
schema_output="$(mktemp "${TMPDIR:-/tmp}/opensourcingos-database-schema.XXXXXX")"
trap 'rm -f "${schema_body}" "${schema_output}"' EXIT

supabase db dump --local --schema public --file "${schema_body}"

{
  printf '%s\n' \
    '-- =====================================================================' \
    '-- supabase/schema.sql -- GENERATED. Do not edit by hand.' \
    '--' \
    '--   regenerate:  npm run db:reset && npm run db:schema' \
    '--' \
    '-- This structure-only public-schema snapshot is generated from a clean' \
    '-- local rebuild of every committed migration. CI repeats that rebuild' \
    '-- and rejects drift between the migrations and this file.' \
    '--' \
    '-- Supabase-managed schemas (auth, storage, realtime, ...) are excluded.' \
    '-- public.handle_new_user() is called by a trigger on auth.users, which is' \
    '-- deliberately outside this snapshot.' \
    '-- =====================================================================' \
    ''
  sed -E '/^-- Dumped from database version /d; /^-- Dumped by pg_dump version /d' "${schema_body}"
} > "${schema_output}"

perl -0pi -e 's/\n+\z/\n/' "${schema_output}"
mv "${schema_output}" supabase/schema.sql
trap - EXIT
