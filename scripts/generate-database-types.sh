#!/usr/bin/env bash

set -euo pipefail

types_output="$(mktemp "${TMPDIR:-/tmp}/opensourcingos-database-types.XXXXXX")"
trap 'rm -f "${types_output}"' EXIT

supabase gen types typescript --local --schema public > "${types_output}"
perl -0pi -e 's/\n+\z/\n/' "${types_output}"
mv "${types_output}" lib/database.types.ts
trap - EXIT
