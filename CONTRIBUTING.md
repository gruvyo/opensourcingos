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
npm run dev
```

Fill `.env.local` with a compatible Supabase project URL and a modern
publishable key. Never use a service-role or secret key in a `NEXT_PUBLIC_`
variable.

## Required checks

Before submitting a pull request, run:

```bash
npm run verify
npx tsc --noEmit
```

Also run `npm run lint` and avoid adding new lint errors. The existing lint
baseline is not yet clean, so unrelated cleanup should be kept in a separate
change.

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

- Never edit `schema.sql` by hand; regenerate it from the hosted schema.
- Create new Supabase migrations with `supabase migration new <name>`.
- Review RLS, grants, function execution privileges, and function search paths.
- Test migrations transactionally before applying them to a hosted project.
- Run Supabase security advisors after changes.
- Refresh `schema.sql` after applying a migration.

## Pull requests

Describe:

- the user-facing problem;
- the chosen solution;
- verification performed;
- database or deployment effects;
- screenshots for visible interface changes.

Keep pull requests small enough to review. A passing deployment preview does not
replace the methodology and type checks.
