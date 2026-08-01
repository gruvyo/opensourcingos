# OpenSourcingOS

Procurement savings, tracked properly.

![OpenSourcingOS shown across desktop, tablet, and mobile](public/readme-cover-concept-b.png)

_Product direction concept; the screens illustrate the experience this public
beta is working toward._

OpenSourcingOS is a public-beta procurement value tracker for sourcing projects,
baselines, supplier offers, savings schedules, fiscal-year reporting, and
portfolio analysis. It is designed around one question: can every reported
savings figure be traced back to the commercial anchors that produced it?

[Try the hosted demo](https://opensourcingos-lac.vercel.app/login) ·
[Report a security issue](SECURITY.md) ·
[Contribute](CONTRIBUTING.md)

## What it does

- Tracks sourcing and non-commercial support projects in one portfolio.
- Records scope lines, baselines, supplier offers, and final awards.
- Separates Cost Reduction from Cost Avoidance without losing the total deal
  movement.
- Normalizes offers with different terms onto a comparable monthly basis.
- Books monthly, annual, or one-time savings schedules without changing the
  total economics.
- Attributes savings to the correct calendar year, including periods spanning
  year boundaries.
- Separates forecast savings from contracted and realized results.
- Produces dashboard, supplier, project, savings, and fiscal-year reporting.
- Gives every demo user a private workspace with isolated sample data.

## The savings methodology

The application uses three commercial anchors:

```text
Opening proposal → Baseline → Final offer
```

```text
Cost Reduction = Baseline − Final
Cost Avoidance = Opening − Baseline
Total Savings  = Opening − Final
               = Cost Reduction + Cost Avoidance
```

The total cannot be changed by choosing a more flattering baseline. A missing
baseline makes Cost Reduction not applicable rather than zero. A real cost
increase remains negative and is never relabeled as savings. Hard Cost
Reduction requires a baseline grounded in the organization's own spend unless
an explicit override is recorded.

All screens use [`lib/savings/index.ts`](lib/savings/index.ts) as the single
source of truth. The executable methodology suite currently covers 340 checks.

## Try the demo

Visit [opensourcingos-lac.vercel.app](https://opensourcingos-lac.vercel.app/login)
and continue with Google. A first sign-in creates a private workspace and copies
in example projects. Changes made in one workspace are not visible to another
user.

The demo is for exploration and feedback. It is not yet presented as a hosted
production service or a system of record for confidential procurement data.

## Technology

- Next.js 16 and React 19
- TypeScript
- Supabase Auth and PostgreSQL
- PostgreSQL Row Level Security for workspace isolation
- Tailwind CSS
- Recharts
- Vercel deployment

## Run the application locally

### Requirements

- Node.js 20.9 or newer
- npm
- Access to a compatible Supabase project

### Setup

```bash
git clone https://github.com/gruvyo/opensourcingos.git
cd opensourcingos
npm ci
cp .env.example .env.local
```

Fill in `.env.local` with the URL and modern publishable key from your Supabase
project, then start the development server:

```bash
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

`NEXT_PUBLIC_SUPABASE_ANON_KEY` retains its historical name because the
Supabase client reads it throughout the application. Its value should be a
modern `sb_publishable_...` key. Never place a secret or service-role key in a
`NEXT_PUBLIC_` variable.

## Database status

[`schema.sql`](schema.sql) is a structure-only snapshot of the live `public`
schema. It includes tables, functions, Row Level Security, policies, and grants.
The numbered SQL files record the evolution of the hosted database, and the
P13 migration is under [`supabase/migrations`](supabase/migrations).

A safe, one-command bootstrap for a completely new Supabase project is not yet
packaged. The generated schema intentionally excludes Supabase-managed schemas,
including the signup trigger on `auth.users`, and should not be pasted blindly
into an existing project. Until bootstrap packaging lands, the hosted demo is
the supported evaluation path and fresh self-hosting is an advanced task.

## Verification

Run the money-methodology suite:

```bash
npm run verify
```

Run TypeScript checking:

```bash
npx tsc --noEmit
```

Run linting:

```bash
npm run lint
```

The methodology and TypeScript checks pass on `main`. The repository still has
known lint debt, mostly loose database-row types and several React effect
patterns; see the public-beta status below.

## Security model

- Every business table in the exposed `public` schema has Row Level Security.
- Policies scope business rows to the signed-in user's organization.
- New demo users receive separate organizations and separately cloned data.
- Browser users cannot invoke the privileged workspace-cloning function.
- Legacy Supabase JWT keys are disabled; the frontend uses a modern publishable
  key.
- GitHub secret scanning and push protection are enabled.

The detailed audit record is in
[`SECURITY-P0-RUNBOOK.md`](SECURITY-P0-RUNBOOK.md). Please report suspected
vulnerabilities privately as described in [`SECURITY.md`](SECURITY.md).

## Project status

OpenSourcingOS is an MVP and public beta. The core savings methodology,
workspace isolation, Google sign-in, schedules, and fiscal-year reporting are
working. Current priorities are:

1. Package reproducible fresh-database setup.
2. Remove the production build's dependency on downloading Google Fonts.
3. Reduce TypeScript and React lint debt.
4. Complete accessibility and end-to-end browser testing.

## Contributing

Contributions are welcome. Start with [`CONTRIBUTING.md`](CONTRIBUTING.md), run
the methodology suite before submitting savings-related changes, and keep
security reports out of public issues.

## License

OpenSourcingOS is licensed under the [Apache License 2.0](LICENSE).
