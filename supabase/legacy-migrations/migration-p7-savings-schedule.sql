-- =====================================================================
-- P7: THE SAVINGS SCHEDULE
-- =====================================================================
-- Step 3 of the period model.
--
-- P4 gave every anchor a term in months. P5 said which baseline and which
-- offers play the three roles. The chain then produces ONE number for the
-- whole deal -- which is not what anyone is actually asked for. The CFO
-- asks for this fiscal year's savings.
--
-- So the deal gets a SCHEDULE: a start month/year, a period type, and a
-- period count produce one row per period, each carrying the same three
-- anchors (Baseline / Opening / Final) and the same derived split
-- (Cost Reduction / Cost Avoidance / Total). Group those rows by calendar
-- year and the fiscal-year report and year-on-year comparison fall out for
-- free -- that is Step 4, and it reads this table.
--
-- Three period types, and the point of it is that all three book the same
-- money for the same deal:
--
--     Monthly    36 rows x the per-month rate
--     Annual      3 rows x the per-year rate
--     One-Time    1 row  x the whole-term amount
--
-- Rows are GENERATED from the anchors, then saved, then editable. An edited
-- row is flagged so a regenerate cannot quietly discard someone's judgement.
-- Editing is limited to the three anchor amounts; the split is always
-- derived, so no one can type a savings number that does not follow from
-- the chain.
--
-- Source: research/raw/project-savings-tab-ideation-and-calculation.xlsx
-- (sheets savings-monthly, savings-annually, savings-one-time). The math is
-- asserted cell for cell by `npm run verify`.
--
-- NOTE: realization_periods is a DIFFERENT table and is left alone. That one
-- tracks actuals against a plan; this one IS the plan.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1) The schedule header lives on the project's one savings calculation.
--    Nullable throughout: a project that has not been scheduled yet is a
--    normal state, not a broken one.
-- ---------------------------------------------------------------------
alter table public.savings_calculations
  add column if not exists schedule_start_month  integer,
  add column if not exists schedule_start_year   integer,
  add column if not exists schedule_period_type  text,
  add column if not exists schedule_period_count integer;

alter table public.savings_calculations drop constraint if exists chk_schedule_start_month;
alter table public.savings_calculations add constraint chk_schedule_start_month
  check (schedule_start_month is null or schedule_start_month between 1 and 12);

alter table public.savings_calculations drop constraint if exists chk_schedule_start_year;
alter table public.savings_calculations add constraint chk_schedule_start_year
  check (schedule_start_year is null or schedule_start_year between 2000 and 2100);

alter table public.savings_calculations drop constraint if exists chk_schedule_period_type;
alter table public.savings_calculations add constraint chk_schedule_period_type
  check (schedule_period_type is null
         or schedule_period_type in ('monthly', 'annual', 'one_time'));

-- 600 monthly periods is 50 years. The cap is a typo guard, not a policy.
alter table public.savings_calculations drop constraint if exists chk_schedule_period_count;
alter table public.savings_calculations add constraint chk_schedule_period_count
  check (schedule_period_count is null or schedule_period_count between 1 and 600);

comment on column public.savings_calculations.schedule_start_month is
  'Month (1-12) the savings start being booked. With schedule_start_year this '
  'replaces date arithmetic entirely -- see savings_periods.';
comment on column public.savings_calculations.schedule_period_type is
  'monthly | annual | one_time. Determines how many months one schedule row '
  'covers (1, 12, or the whole deal term). All three book the same total.';
comment on column public.savings_calculations.schedule_period_count is
  'How many rows the schedule has. Defaults to whatever covers the deal term '
  'exactly; a term that is not a whole number of periods ends in a short one.';

-- ---------------------------------------------------------------------
-- 2) The schedule itself: one row per period.
-- ---------------------------------------------------------------------
create table if not exists public.savings_periods (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null,
  event_id uuid not null
    references public.sourcing_events(id) on delete cascade,
  savings_calculation_id uuid not null
    references public.savings_calculations(id) on delete cascade,

  -- Where this row sits in the schedule.
  period_number integer not null,
  period_month  integer not null,
  period_year   integer not null,
  -- Months of the DEAL TERM this row books. Normally the period length, but
  -- the last row of a term that is not a whole number of periods is short,
  -- and a row scheduled past the end of the term books zero rather than
  -- inventing savings the contract cannot produce.
  period_months numeric not null default 0,

  -- The three anchors, at this row's scale. NULL means the anchor was never
  -- captured -- deliberately distinct from zero.
  baseline_amount numeric,
  opening_amount  numeric,
  final_amount    numeric not null default 0,

  -- The derived split. Always Baseline - Final, Opening - Baseline, and their
  -- sum. cost_reduction_amount is NULL when there is no baseline anchor: not
  -- applicable, which is not the same as zero. It MAY BE NEGATIVE.
  cost_reduction_amount numeric,
  cost_avoidance_amount numeric not null default 0,
  total_savings_amount  numeric not null default 0,

  -- True once a human has overridden the generated figures, so a regenerate
  -- can warn instead of silently discarding their judgement.
  is_edited boolean not null default false,
  notes text,

  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,

  constraint chk_savings_periods_month  check (period_month between 1 and 12),
  constraint chk_savings_periods_year   check (period_year between 2000 and 2100),
  constraint chk_savings_periods_number check (period_number >= 1),
  constraint chk_savings_periods_months check (period_months >= 0)
);

comment on table public.savings_periods is
  'The savings schedule: one row per period, each carrying the three anchors '
  'and the derived chain. Generated from the anchors, then editable. Grouping '
  'these rows by calendar year is what produces fiscal-year and YoY reporting.';
comment on column public.savings_periods.period_months is
  'Months of the deal term this row books. Zero past the end of the term.';
comment on column public.savings_periods.cost_reduction_amount is
  'Baseline - Final for this period. NULL means NOT APPLICABLE (no baseline '
  'anchor), which is distinct from zero. May legitimately be negative.';
comment on column public.savings_periods.is_edited is
  'True when the amounts were overridden by hand rather than generated.';

-- One row per period number per schedule. Makes a double-generate impossible.
create unique index if not exists uq_savings_periods_calc_number
  on public.savings_periods(savings_calculation_id, period_number);

create index if not exists idx_savings_periods_org
  on public.savings_periods(organization_id);
create index if not exists idx_savings_periods_event
  on public.savings_periods(event_id);
create index if not exists idx_savings_periods_calc
  on public.savings_periods(savings_calculation_id);
-- The fiscal-year report groups on this; Step 4 will lean on it hard.
create index if not exists idx_savings_periods_year
  on public.savings_periods(organization_id, period_year);

-- ---------------------------------------------------------------------
-- 3) RLS -- exactly the org-scoped pattern from P0. A new table defaults to
--    NO policies, which is deny-all, but never rely on that: state it.
-- ---------------------------------------------------------------------
alter table public.savings_periods enable row level security;
alter table public.savings_periods force row level security;

drop policy if exists "org_select" on public.savings_periods;
drop policy if exists "org_insert" on public.savings_periods;
drop policy if exists "org_update" on public.savings_periods;
drop policy if exists "org_delete" on public.savings_periods;

create policy "org_select" on public.savings_periods for select to authenticated
  using (organization_id = public.current_org_id());
create policy "org_insert" on public.savings_periods for insert to authenticated
  with check (organization_id = public.current_org_id());
create policy "org_update" on public.savings_periods for update to authenticated
  using (organization_id = public.current_org_id())
  with check (organization_id = public.current_org_id());
create policy "org_delete" on public.savings_periods for delete to authenticated
  using (organization_id = public.current_org_id());

grant select, insert, update, delete on public.savings_periods to authenticated;

commit;

-- ---------------------------------------------------------------------
-- VERIFY (run separately)
-- ---------------------------------------------------------------------
-- The four policies, none of them fail-open:
-- select policyname, cmd, qual, with_check from pg_policies
--  where schemaname = 'public' and tablename = 'savings_periods';
--
-- Once a schedule has been generated, its rows must add back to the deal:
-- select e.event_name,
--        c.schedule_period_type,
--        count(p.id)                        as periods,
--        sum(p.period_months)               as months_booked,
--        round(sum(p.total_savings_amount)) as schedule_total,
--        round(c.gross_savings_amount)      as calculation_total
--   from public.savings_calculations c
--   join public.sourcing_events e on e.id = c.event_id
--   left join public.savings_periods p on p.savings_calculation_id = c.id
--  group by e.event_name, c.schedule_period_type, c.gross_savings_amount
--  order by e.event_name;
--
-- The fiscal-year report, which is what Step 4 renders:
-- select period_year,
--        round(sum(cost_reduction_amount)) as cost_reduction,
--        round(sum(cost_avoidance_amount)) as cost_avoidance,
--        round(sum(total_savings_amount))  as total
--   from public.savings_periods
--  group by period_year order by period_year;
