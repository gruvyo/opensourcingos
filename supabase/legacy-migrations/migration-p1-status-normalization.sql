-- =====================================================================
-- P1 STATUS NORMALIZATION — calculation_status + award_status
-- =====================================================================
-- Resolves the two items migration-p1-schema-hardening.sql intentionally
-- left unconstrained (see its §3 notes):
--
--   • calculation_status held INCONSISTENT values — a mix of two vocabularies
--     and mixed case ('Approved | contracted | Draft | realized | Submitted').
--     This normalizes them to the single canonical set the app's UI uses
--     (components/calculations-tab.tsx: the Workflow <Select> and
--     CALC_STATUS_COLORS), then adds chk_calculation_status.
--
--   • award_status was left unconstrained because the full value set was
--     unknown. This adds chk_award_status, guarded so it aborts with the
--     offending values if reality differs from the assumed set.
--
-- CANONICAL SETS (source of truth = the app, not this file):
--   calculation_status ∈ {identified, negotiated, contracted, realized}  (lowercase)
--   award_status       ∈ {Recommended, Approved, Rejected, Contracted}
--
-- LEGACY → CANONICAL MAPPING for calculation_status (confirm before applying):
--   Draft      → identified   (initial / not yet worked)
--   Submitted  → negotiated   (terms agreed, submitted for approval)
--   Approved   → contracted   (approved / committed)
--   contracted → contracted   (already canonical)
--   realized   → realized     (already canonical)
--   identified/negotiated → unchanged
--   (case-insensitive; any already-canonical value is left as-is)
--
-- SAFETY: two independent transactions so award_status cannot roll back the
-- calc normalization. Each block RAISES (aborting only itself) if it meets a
-- value it does not know how to handle — so a wrong assumption surfaces the
-- real data instead of corrupting it or mis-constraining. CHECK passes NULLs
-- (SQL three-valued logic), which is fine: the app defaults new rows to a
-- concrete value.
--
-- DISCOVERY (run first, expect only the documented values):
--   select calculation_status, count(*) from public.savings_calculations
--     group by calculation_status order by 2 desc;
--   select award_status, count(*) from public.awards
--     group by award_status order by 2 desc;
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) calculation_status: normalize, then constrain.
-- ---------------------------------------------------------------------
begin;

update public.savings_calculations
set calculation_status = case lower(calculation_status)
    when 'draft'      then 'identified'
    when 'submitted'  then 'negotiated'
    when 'approved'   then 'contracted'
    when 'identified' then 'identified'
    when 'negotiated' then 'negotiated'
    when 'contracted' then 'contracted'
    when 'realized'   then 'realized'
    else calculation_status  -- unknown: left as-is, caught by the guard below
  end
where calculation_status is not null
  and calculation_status not in ('identified','negotiated','contracted','realized');

-- Guard: abort (rolling back the UPDATE) if any unmapped value survives, and
-- report exactly which ones so the mapping above can be extended.
do $$
declare offenders text;
begin
  select string_agg(distinct calculation_status, ', ')
    into offenders
  from public.savings_calculations
  where calculation_status is not null
    and calculation_status not in ('identified','negotiated','contracted','realized');
  if offenders is not null then
    raise exception
      'chk_calculation_status not applied: unmapped calculation_status value(s): %. Extend the CASE mapping and re-run.', offenders;
  end if;
end $$;

alter table public.savings_calculations drop constraint if exists chk_calculation_status;
alter table public.savings_calculations add constraint chk_calculation_status
  check (calculation_status in ('identified','negotiated','contracted','realized'));

commit;

-- ---------------------------------------------------------------------
-- 2) award_status: constrain (no normalization expected — the app only ever
--    writes 'Recommended'; the rest of the set covers the award lifecycle).
--    Guarded: if a live value falls outside the set, this aborts and names it
--    rather than adding a constraint that would reject real data.
-- ---------------------------------------------------------------------
begin;

do $$
declare offenders text;
begin
  select string_agg(distinct award_status, ', ')
    into offenders
  from public.awards
  where award_status is not null
    and award_status not in ('Recommended','Approved','Rejected','Contracted');
  if offenders is not null then
    raise exception
      'chk_award_status not applied: award_status value(s) outside the assumed set: %. Confirm the full set and adjust the IN(...) list.', offenders;
  end if;
end $$;

alter table public.awards drop constraint if exists chk_award_status;
alter table public.awards add constraint chk_award_status
  check (award_status in ('Recommended','Approved','Rejected','Contracted'));

commit;

-- ---------------------------------------------------------------------
-- POST-APPLY verification (each should confirm the constraint exists):
--   select conname, pg_get_constraintdef(oid) from pg_constraint
--     where conname in ('chk_calculation_status','chk_award_status');
--   select calculation_status, count(*) from public.savings_calculations
--     group by calculation_status order by 1;   -- only canonical values
-- ---------------------------------------------------------------------
