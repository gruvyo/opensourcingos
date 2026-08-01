-- =====================================================================
-- P9: PORTFOLIO SORT INDEXES  (OPTIONAL -- not needed at current scale)
-- =====================================================================
-- READ THIS BEFORE RUNNING IT: you probably do not need to yet.
--
-- Every portfolio-wide page sorts a whole table and relies on RLS to scope
-- it to the organisation. That means each query filters on organization_id
-- and then sorts on a second column:
--
--   /events  and  /reports   sourcing_events      order by created_at desc
--   /savings and  /reports   savings_calculations order by created_at desc
--   /suppliers               suppliers            order by supplier_name
--   /realization             realization_periods  order by period_start_date
--
-- Only organization_id is indexed on those tables today (P1), so the sort is
-- unsupported. At the ~115 projects this system tracks, Postgres will scan
-- and sort that in well under a millisecond and these indexes will change
-- nothing you can measure. They earn their keep in the thousands, not the
-- hundreds.
--
-- Apply this when the project count grows by roughly an order of magnitude,
-- or when a portfolio page starts feeling slow -- not before. Indexes are not
-- free: each one adds write cost on every insert and update.
--
-- The composite shape (organization_id, <sort column>) matches what P7
-- already does for idx_savings_periods_year, and covers both the RLS-implicit
-- tenant filter and the ORDER BY in a single index.
--
-- Safe and idempotent: creates indexes only. No data is read, written, or
-- destroyed, and re-running it does nothing.
-- =====================================================================

begin;

create index if not exists idx_sourcing_events_org_created
  on public.sourcing_events(organization_id, created_at desc);

create index if not exists idx_savings_calculations_org_created
  on public.savings_calculations(organization_id, created_at desc);

create index if not exists idx_suppliers_org_name
  on public.suppliers(organization_id, supplier_name);

-- The Realization tab is hidden from the UI, but /realization is still a
-- reachable route and still sorts on this column.
create index if not exists idx_realization_periods_org_period_start
  on public.realization_periods(organization_id, period_start_date);

commit;

-- ---------------------------------------------------------------------
-- VERIFY (run separately)
-- ---------------------------------------------------------------------
-- select tablename, indexname from pg_indexes
--  where schemaname = 'public'
--    and indexname in ('idx_sourcing_events_org_created',
--                      'idx_savings_calculations_org_created',
--                      'idx_suppliers_org_name',
--                      'idx_realization_periods_org_period_start')
--  order by tablename;
--
-- Whether the planner actually uses one (it will ignore them on a small
-- table, which is correct behaviour, not a failure):
-- explain analyze
--   select id from public.sourcing_events order by created_at desc limit 50;
