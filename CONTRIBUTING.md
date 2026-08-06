# Contributing to OpenSourcingOS

Thanks for helping make procurement value reporting more transparent and
reproducible.

## Before opening a change

- Use a focused branch and keep unrelated changes separate.
- Open an issue first for large product, data-model, or methodology changes.
- Do not include confidential procurement data, credentials, customer names,
  or production database exports.
- Report vulnerabilities privately according to [`SECURITY.md`](SECURITY.md).

## Local setup

```bash
git clone https://github.com/gruvyo/opensourcingos.git
cd opensourcingos
npm ci
cp .env.example .env.local
npm run db:start
npm run db:reset
npm run db:test
npm run db:types
```

Run `supabase status`, then fill `.env.local` with the local API URL and modern
publishable key before running `npm run dev`. Never use a service-role or secret
key in a `NEXT_PUBLIC_` variable. Google sign-in requires separate local OAuth
configuration; see [`supabase/README.md`](supabase/README.md#google-sign-in).

## Framework guidance

This project follows the conventions of its pinned Next.js version. Before
changing routing, rendering, caching, or request APIs, check the matching guides
bundled under `node_modules/next/dist/docs/`; older examples may use APIs that
have changed.

## Required checks

Before submitting a pull request, run:

```bash
npm run verify
npm run lint
npx tsc --noEmit
npm run test:env
npm run test:portfolio-queries
```

All five checks currently pass on `main`. Keep unrelated cleanup in a separate
change so the user-facing behavior and its verification remain easy to review.

## Savings methodology changes

[`lib/savings/index.ts`](lib/savings/index.ts) is the single source of truth for
reported savings. Do not calculate portfolio money independently inside a page
or component.

Any change affecting savings must:

1. Preserve or deliberately update the three-anchor chain.
2. Add or update executable cases in `scripts/verify-savings.mts`.
3. Reconcile Cost Reduction, Cost Avoidance, and Total Savings.
4. Cover missing anchors, negative reductions, differing terms, and year
   boundaries where relevant.
5. Explain any methodology change in the pull request.

## Database changes

- Never edit `supabase/schema.sql` by hand; regenerate it from the hosted schema.
- Create new Supabase migrations with `supabase migration new <name>`.
- Review RLS, grants, function execution privileges, and function search paths.
- Test migrations transactionally before applying them to a hosted project.
- Rebuild from an empty local database with `npm run db:reset`.
- Run the database security suite with `npm run db:test`.
- Run `npm run db:lint` and `npm run db:advisors` after changes.
- Refresh `supabase/schema.sql` after applying a migration.

## Pull requests

Describe:

- the user-facing problem;
- the chosen solution;
- verification performed;
- database or deployment effects;
- screenshots for visible interface changes.

Keep pull requests small enough to review. A passing deployment preview does not
replace the methodology and type checks.
