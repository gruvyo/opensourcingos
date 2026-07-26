# P0 Security Runbook — do this before sharing the repo

> **STATUS — updated 2026-07-25**
> - ✅ **Tenant isolation (RLS) — DONE & verified live.** `migration-p0-rls-tenant-isolation.sql`
>   was applied to production. Verified: 0 fail-open policies, 63 org-scoped policies across
>   17 tables; the real user sees their 14 events, a stranger from another org sees 0.
> - ✅ **Profile edits locked** to the owner; org-hopping blocked (same migration).
> - ⏳ **Retire the leaked key (Step 1 below)** — REMAINING, now **low-risk**: with RLS fixed,
>   the anon role has no access to data tables, so the leaked key can't reach data. Do it
>   before publishing the repo.
> - ⏳ **Capture schema to git (Step 2)** and **purge key from history (Step 4)** — REMAINING,
>   pre-publish. **Step 3 (apply RLS) is already DONE** — skip it.

The steps below are ordered by what makes you safe. Steps that only you can do
(Supabase console / DB access) are marked. Retiring the key (Step 3) is **only
meaningful once done** — removing it from history does nothing while it still works.

> The exposed key: legacy `anon` key for project `qjtactdcfeuseuqaxfaa`. Before the RLS fix it
> was a full read/write grant over all data. **After the RLS fix it can no longer reach your
> data** (anon has no policies) — but retire it anyway before publishing, as good hygiene.

---

## Step 1 — Rotate the leaked key (this is the real fix)

This invalidates the committed key so it can't be used even though it's in git history.

1. Supabase Dashboard → your project → **Project Settings → API**.
2. Roll the key:
   - **Legacy JWT keys** (your project — the committed key is a JWT `anon` token):
     open **JWT Settings → "Generate a new secret"**. This re-signs and invalidates
     the old `anon` and `service_role` keys. ⚠️ It also **signs out every current
     user session** — expected, do it when that's acceptable.
   - **New API keys** (if your project uses publishable/secret keys): revoke the
     exposed publishable key and create a new one.
3. Copy the **new** anon/publishable key into `opensourcingos/.env.local`
   (which is gitignored — keep it that way). `setup.sh` has already been scrubbed
   to placeholders.
4. Restart the app and confirm it still connects with the new key.

Do **not** proceed to publishing the repo until this is done.

---

## Step 2 — Capture the real schema into version control

The ~16 base tables, RLS enablement, and the signup→`profiles`→`organization_id`
trigger exist **only in Supabase Studio** — a clone can't reproduce the app, and
I couldn't verify the RLS migration against real column names. Fix both at once:

```bash
brew install supabase/tap/supabase
```

```bash
cd opensourcingos && supabase link --project-ref qjtactdcfeuseuqaxfaa
```

```bash
supabase db pull
```

This writes the true schema to `supabase/migrations/`. Commit it. Now you have a
real baseline to diff my migration against.

---

## Step 3 — Apply the tenant-isolation RLS migration

File: `migration-p0-rls-tenant-isolation.sql` (in this repo). It replaces all 39
fail-open policies with `organization_id = current_org_id()` policies and locks
`profiles` updates to the owner.

**3a. Verify names** against the `supabase db pull` output from step 2 — confirm
every table in the migration's two `text[]` arrays exists with an
`organization_id` column, and that `savings_calculation_lines` really has none
(it's scoped through its parent). Fix any mismatch before running.

**3b. Apply to a staging/branch project first** (Supabase → Branches, or a second
project), never straight to prod. Paste the file into the SQL editor, or:

```bash
supabase db execute --file migration-p0-rls-tenant-isolation.sql
```

**3c. Run the isolation test** (this is the acceptance gate):
1. Create two users in two different organizations (User A / Org 1, User B / Org 2).
2. As A, create an event. As B, confirm you **cannot** see or edit it.
3. As B, try `supabase.from('sourcing_events').select('*')` — should return only
   Org 2 rows.
4. As B, try to insert a row with `organization_id` = Org 1's id — should be
   **rejected** by the `WITH CHECK`.
5. As B, try to update A's `profiles` row — should be **rejected**.
6. Confirm the app's own screens still work end-to-end for a normal same-org user.

**3d.** Verify no fail-open policy remains (run the commented query at the bottom
of the migration — it should return zero rows). Then apply to prod.

---

## Step 4 — Purge the key from git history (after step 1)

Only cleanup — the rotation in step 1 is what neutralized the key. This rewrites
history, so coordinate if the repo is pushed anywhere or cloned by anyone.

```bash
pip install git-filter-repo
```

Create a replacements file **outside** the repo (so the secret is never
re-committed) — one line, the old key on the left:

```bash
printf '%s==>***REMOVED***\n' "$OLD_ANON_KEY" > /tmp/secret-replacements.txt
```

(Set `OLD_ANON_KEY` in your shell first from your own copy of the leaked value —
do not paste it into any tracked file.) Then rewrite history:

```bash
cd opensourcingos && git filter-repo --replace-text /tmp/secret-replacements.txt && rm /tmp/secret-replacements.txt
```

Then force-push if there's a remote. (If you'd rather not rewrite history and the
repo has never been pushed, you can instead squash to a fresh initial commit.)

⚠️ `git filter-repo` is destructive and irreversible. Back up the repo first:
`cp -r opensourcingos opensourcingos.bak`.

---

## Optional P0 hardening (recommended before a public launch)

- **Gate signup** — `app/login/page.tsx` allows open `signUp` with a 6-char
  password and no invite/domain restriction. Add an invite code or email-domain
  allow-list so strangers can't self-provision into your app.
- **`middleware.ts` → `proxy.ts`** — Next 16 deprecated the `middleware` filename
  (still works, warning only): `npx @next/codemod@canary middleware-to-proxy .`

---

### Done when
- New key in `.env.local`, old key rotated and confirmed dead.
- Real schema committed under `supabase/migrations/`.
- RLS migration applied; two-account isolation test passes; zero fail-open policies.
- Key purged from history (or repo re-initialized) before any push/publish.
