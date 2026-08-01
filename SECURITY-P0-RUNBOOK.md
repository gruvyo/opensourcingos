# P0 Security Status — public repository

Last audited: **2026-07-31**

This file records the security incident that was found during the original
open-source review, what was done about it, and the small number of checks that
still require access to the hosted services.

The GitHub repository is public. Treat every committed value and every reachable
historical object as publicly accessible.

## Current status

| Control | Status | Evidence |
| --- | --- | --- |
| Tenant isolation | Done | `migration-p0-rls-tenant-isolation.sql` was applied and verified live on 2026-07-25: 0 fail-open policies, 63 organization-scoped policies across 17 tables, and a two-organization isolation test passed. |
| Profile ownership | Done | The same migration prevents users from editing another user's profile or changing their organization. |
| Exposed legacy anon key | Neutralized | The Supabase management API confirmed on 2026-07-31 that the legacy `anon` JWT is disabled and the modern `sb_publishable_...` key is active. Production/preview were moved to the modern key before commit `c92a467`. |
| Git-history cleanup | Done | A full reachable-history audit on 2026-07-31 found only placeholders and `***REMOVED***` markers in historical `NEXT_PUBLIC_SUPABASE_ANON_KEY` assignments. It found no JWT-shaped, `sb_publishable_...`, `sb_secret_...`, or service-role value. |
| Privileged database functions | Done | P13 removed browser access to `clone_org_data()` and `handle_new_user()`, pinned application-function search paths, and was verified live on 2026-07-31. |
| Reproducible schema | Done | The hosted schema is captured in `schema.sql`, including RLS and policy definitions. Database changes P0–P13 are retained as migrations. |
| Local environment files | Done | `.env.local` and `.env*.local` are ignored and no environment file is tracked. `setup.sh` contains placeholders only. |
| Vercel environment | Done | Production and Preview use the same sensitive Supabase variables. The local/deployed configuration uses the modern publishable key, no public secret-shaped variable was found, and the production Google OAuth redirect was verified on 2026-07-31. |
| GitHub secret scanning | Done | Secret scanning and push protection were enabled on 2026-07-31. GitHub reported 0 alerts immediately after enablement. |

## Why the original issue was serious

The repository once contained a legacy Supabase `anon` JWT for project
`qjtactdcfeuseuqaxfaa`. An anon or publishable key is expected to be present in
browser code, but it is safe only when Row Level Security is correct. At the
time, fail-open policies gave the anon role broad data access. The combination
of corrected RLS, disabled legacy keys, and scrubbed history closes that path.

## Remaining hosted-service confirmations

These checks cannot be proven from the repository alone:

- In Supabase's Google auth provider, confirm redirect URLs are limited to the
  intended production, preview, and local callback origins.
- Confirm the production app still passes a two-user/two-organization isolation
  smoke test after the most recent deployment.

## Accepted Supabase advisor warnings

After P13, Supabase's security advisor reports two warnings:

- `public.current_org_id()` is intentionally `SECURITY DEFINER` and executable
  by `authenticated`. Organization RLS policies call it, and it needs definer
  rights to read `profiles` without recursively invoking the profiles policy.
  It returns only the caller's organization ID. `anon` cannot execute it.
- Leaked-password protection is disabled. The application is Google-only and
  has no password sign-in or signup interface, so the control does not apply to
  its supported authentication path.

The same audit found zero public tables without RLS and zero fail-open policies.

## Repeatable local audit

The 2026-07-31 audit inspected every commit reachable from every local branch
and tag, not just the current working tree. Re-run an equivalent history-aware
secret scanner immediately before publication. At minimum, search for:

- JWT-like values beginning with `eyJ`
- Supabase `sb_publishable_` and `sb_secret_` values
- assigned `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` values
- tracked `.env`, private-key, credential, or secret files

Do not print matching credential values into terminal logs. Report only the
commit and file, then rotate the credential before cleaning history.

## If another active credential is found

1. Revoke or rotate it at the provider first.
2. Update the private deployment environment and verify the app.
3. Back up the repository.
4. Rewrite history with `git filter-repo --replace-text`.
5. Re-run the full-history audit.
6. Coordinate the force-push and have every collaborator re-clone.

History rewriting is destructive and is not required for the already-scrubbed
legacy Supabase key described above.

## Release gate

The security gate is complete when the two remaining hosted-service checks above
have been recorded. Repository history, GitHub scanning, Vercel configuration,
and the live database audit are currently clean.
