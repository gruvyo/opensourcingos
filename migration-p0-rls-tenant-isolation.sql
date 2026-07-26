-- =====================================================================
-- P0 SECURITY MIGRATION — Tenant isolation via Row-Level Security
-- =====================================================================
-- Replaces the fail-open policies (USING(true)/WITH CHECK(true)) with
-- organization-scoped policies so a user can only see/write rows belonging
-- to their own organization.
--
-- ⚠️  BEFORE APPLYING — READ SECURITY-P0-RUNBOOK.md
--   1. This was authored from a *reconstructed* schema (no DDL is in the
--      repo). Run `supabase db pull` first and diff table/column names
--      against this file. Fix any mismatch before running.
--   2. Apply to a BRANCH / staging Supabase project first, then run the
--      two-account isolation test in the runbook. Only then apply to prod.
--   3. Rotating the leaked anon key (runbook step 1) is what actually
--      neutralizes the exposure — this migration is the second half.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- Helper: the caller's organization_id, resolved once.
-- SECURITY DEFINER so it can read profiles without tripping profiles' own
-- RLS (avoids recursion). STABLE so the planner caches it per statement.
-- ---------------------------------------------------------------------
create or replace function public.current_org_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select organization_id from public.profiles where id = auth.uid()
$$;

revoke all on function public.current_org_id() from public;
grant execute on function public.current_org_id() to authenticated;

-- ---------------------------------------------------------------------
-- 1) Drop every existing policy on the target tables (removes the
--    fail-open ones regardless of their exact names), and ensure RLS is on.
-- ---------------------------------------------------------------------
do $$
declare
  t text;
  p record;
  -- Every table that carries an organization_id column (verified live 2026-07-25):
  org_tables text[] := array[
    'organizations','profiles','categories','business_units','cost_centers',
    'suppliers','sourcing_events','event_scope_lines','baselines','baseline_lines',
    'supplier_offers','supplier_offer_lines','awards','award_lines',
    'savings_calculations','savings_calculation_lines','realization_periods'
  ];
begin
  foreach t in array org_tables loop
    -- drop all existing policies on this table
    for p in
      select policyname from pg_policies
      where schemaname = 'public' and tablename = t
    loop
      execute format('drop policy if exists %I on public.%I', p.policyname, t);
    end loop;
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 2) Org-scoped CRUD policies for every table that has organization_id
--    (except profiles/organizations, handled specially below).
-- ---------------------------------------------------------------------
do $$
declare
  t text;
  scoped_tables text[] := array[
    'categories','business_units','cost_centers','suppliers',
    'sourcing_events','event_scope_lines','baselines','baseline_lines',
    'supplier_offers','supplier_offer_lines','awards','award_lines',
    'savings_calculations','savings_calculation_lines','realization_periods'
  ];
begin
  foreach t in array scoped_tables loop
    execute format($f$
      create policy "org_select" on public.%1$I for select to authenticated
        using (organization_id = public.current_org_id());
      create policy "org_insert" on public.%1$I for insert to authenticated
        with check (organization_id = public.current_org_id());
      create policy "org_update" on public.%1$I for update to authenticated
        using (organization_id = public.current_org_id())
        with check (organization_id = public.current_org_id());
      create policy "org_delete" on public.%1$I for delete to authenticated
        using (organization_id = public.current_org_id());
    $f$, t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 3) organizations — a user may see only their own organization row.
-- ---------------------------------------------------------------------
create policy "own_org_select" on public.organizations for select to authenticated
  using (id = public.current_org_id());

-- ---------------------------------------------------------------------
-- 4) profiles — see org members; update ONLY your own row, and you may not
--    change your organization_id or role from the client (privilege-escalation
--    guard). Column-level change prevention is enforced by trigger below,
--    because a WITH CHECK cannot compare to the OLD row.
-- ---------------------------------------------------------------------
create policy "profiles_select_org" on public.profiles for select to authenticated
  using (organization_id = public.current_org_id());
create policy "profiles_update_self" on public.profiles for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

create or replace function public.prevent_profile_privilege_change()
returns trigger language plpgsql as $$
begin
  if new.organization_id is distinct from old.organization_id then
    raise exception 'organization_id cannot be changed by the user';
  end if;
  -- Uncomment if a `role` column exists and must be admin-only:
  -- if new.role is distinct from old.role then
  --   raise exception 'role cannot be changed by the user';
  -- end if;
  return new;
end $$;

drop trigger if exists trg_prevent_profile_privilege_change on public.profiles;
create trigger trg_prevent_profile_privilege_change
  before update on public.profiles
  for each row execute function public.prevent_profile_privilege_change();

-- ---------------------------------------------------------------------
-- 5) Sanity check — after commit, this should return ZERO fail-open policies.
--    (Run manually; commented so the migration itself stays non-interactive.)
-- ---------------------------------------------------------------------
-- select schemaname, tablename, policyname, qual, with_check
-- from pg_policies
-- where schemaname = 'public'
--   and (qual = 'true' or with_check = 'true');

commit;
