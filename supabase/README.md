# Supabase directory

This directory contains the public database definition for OpenSourcingOS.

- `schema.sql` is a generated, structure-only snapshot of the hosted `public`
  schema. It contains no production rows or credentials.
- `migrations/` contains reviewed forward changes tracked against the hosted
  database. Applied migrations must not be renamed, reordered, or deleted.

After an approved hosted schema change, refresh the snapshot with:

```bash
supabase db dump --linked --schema public --file supabase/schema.sql
```

The current repository does not yet provide a one-command bootstrap for a new
Supabase project. The schema snapshot excludes Supabase-managed objects such as
the authentication trigger on `auth.users`, so it should be treated as a
reference rather than pasted directly into a database.

For database contribution and verification rules, see
[`../CONTRIBUTING.md`](../CONTRIBUTING.md).
