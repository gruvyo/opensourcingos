# Historical database migrations

This directory preserves the SQL used to evolve the original hosted database
through P12, along with earlier seed and repair scripts. It exists for audit
history and is not a fresh-database bootstrap sequence.

New database changes belong in `supabase/migrations/` and should be created with
the Supabase CLI. The current structure-only reference snapshot is
`supabase/schema.sql`.
