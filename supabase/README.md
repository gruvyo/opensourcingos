# Supabase directory

This directory is the reproducible database definition for OpenSourcingOS.

- `config.toml` configures the disposable local Supabase stack.
- `migrations/` rebuilds the application schema in order. The first file is a
  reviewed baseline; the later files preserve the hosted project's forward
  history.
- `seed.sql` contains a small, entirely fictional demo template for local and
  test environments. It contains no production export or confidential data.
- `tests/database/` verifies signup, workspace isolation, Row Level Security,
  grants, privileged-function lockdown, and the reference savings chain.
- `schema.sql` remains the generated, structure-only snapshot of the hosted
  `public` schema. Do not edit it by hand.

## Rebuild a clean local database

Requirements:

- Supabase CLI 2.110.0 (the version pinned in CI)
- Docker Desktop or Podman
- At least 7 GB of memory available to the container runtime

From the repository root:

```bash
npm run db:start
npm run db:reset
npm run db:test
npm run db:lint
npm run db:advisors
npm run db:types
```

`db:types` regenerates `lib/database.types.ts` from the local `public` schema.
The application imports these generated types for its database-backed records
and mutations. CI rebuilds the database and verifies that the file stays current
whenever the schema or database workflow changes.

`db:reset` destroys only the local database, replays every migration, and then
loads the fictional seed. Never add `--linked` when working with production.

Run `supabase status` to obtain the local API URL and publishable key. Put those
values in `.env.local` using the names from `../.env.example`, then run
`npm run dev`.

## Google sign-in

Google is the application's only sign-in method. The local configuration keeps
Google disabled by default so cloning and rebuilding the database never require
secrets.

To exercise Google sign-in locally:

1. Copy the commented `[auth.external.google]` block in `config.toml` into active
   configuration.
2. Put your own Google client ID and secret in `supabase/.env.local` using the
   environment-variable names shown in that block.
3. Configure the Google OAuth client with the callback URL printed for the
   local Supabase Auth service.
4. Keep the application callback exactly
   `http://localhost:3000/auth/callback` (or the 127.0.0.1 equivalent already
   allowlisted in `config.toml`).

Never commit OAuth secrets, service-role keys, database passwords, or signing
keys.

## Set up a brand-new hosted project

1. Create an empty Supabase project.
2. Link the CLI to that new project with `supabase link --project-ref <ref>`.
3. Preview the migration plan with `supabase db push --dry-run`.
4. Apply the schema with `supabase db push`.
5. For a disposable demo or staging project only, load the fictional template
   with `supabase db push --include-seed`. Do not seed a real production system.
6. Enable Google in Supabase Auth and provide your own Google OAuth credentials.
7. Add the deployed application's exact `/auth/callback` URL to Supabase's
   redirect allowlist.
8. Run the database tests against a disposable environment before connecting
   the application.

New projects use explicit Data API grants. The migrations include the grants
the browser application needs; Row Level Security remains a separate and
mandatory protection layer.

## Existing OpenSourcingOS production project

The foundational migration represents schema that already exists in the hosted
project. It must be recorded as applied there once, without executing its SQL:

```bash
supabase migration repair 20260728082800 --status applied --linked
supabase migration list --linked
```

That is a migration-history metadata change and requires explicit production
authorization. Do not run `db push --include-all` against the existing hosted
project before the history is reconciled.

## Database contribution rules

- Create migrations with `supabase migration new <name>`.
- Test them with a clean `npm run db:reset`, not only against an existing
  database.
- Every exposed table needs explicit grants, organization-scoped forced RLS,
  appropriate indexes, and cross-workspace tests.
- Privileged functions need fixed search paths and minimal execute grants.
- Every write path must surface database errors.
- After an approved hosted schema change, refresh the snapshot with:

```bash
supabase db dump --linked --schema public --file supabase/schema.sql
```

Also follow [`../CONTRIBUTING.md`](../CONTRIBUTING.md).
