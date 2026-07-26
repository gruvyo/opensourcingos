-- =====================================================================
-- P1 SCHEMA HARDENING — indexes, uniqueness invariants, value constraints
-- =====================================================================
-- Adds the database-level guarantees the app currently only enforces in the
-- UI (see ASSESSMENT.md §4, "Data model & schema governance").
--
-- ⚠️  BEFORE APPLYING:
--   1. Authored from a *reconstructed* schema. Diff table/column names against
--      `supabase db pull` (or the live DB) first; fix any mismatch.
--   2. Apply to a BRANCH/staging project first if you can.
--   3. Everything here is idempotent (IF NOT EXISTS / drop-then-add) and
--      NON-destructive to data. CHECK constraints are added NOT VALID, so they
--      apply to NEW rows only and will not reject existing rows.
--   4. The partial UNIQUE indexes (§2) CAN fail if existing data already
--      violates "one official baseline per event". Run the pre-flight query at
--      the very bottom first; clean up any duplicates, then apply.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1) Indexes on foreign-key / filter columns.
--    None existed; every page filters on these (event_id, organization_id,
--    and the parent FKs), so they currently sequential-scan.
-- ---------------------------------------------------------------------

-- organization_id (tenant filter, on every table)
create index if not exists idx_categories_org           on public.categories(organization_id);
create index if not exists idx_business_units_org        on public.business_units(organization_id);
create index if not exists idx_cost_centers_org          on public.cost_centers(organization_id);
create index if not exists idx_suppliers_org             on public.suppliers(organization_id);
create index if not exists idx_sourcing_events_org       on public.sourcing_events(organization_id);
create index if not exists idx_event_scope_lines_org     on public.event_scope_lines(organization_id);
create index if not exists idx_baselines_org             on public.baselines(organization_id);
create index if not exists idx_baseline_lines_org        on public.baseline_lines(organization_id);
create index if not exists idx_supplier_offers_org       on public.supplier_offers(organization_id);
create index if not exists idx_supplier_offer_lines_org  on public.supplier_offer_lines(organization_id);
create index if not exists idx_awards_org                on public.awards(organization_id);
create index if not exists idx_award_lines_org           on public.award_lines(organization_id);
create index if not exists idx_savings_calculations_org  on public.savings_calculations(organization_id);
create index if not exists idx_realization_periods_org   on public.realization_periods(organization_id);

-- event_id (the primary drill-down key)
create index if not exists idx_event_scope_lines_event   on public.event_scope_lines(event_id);
create index if not exists idx_baselines_event           on public.baselines(event_id);
create index if not exists idx_baseline_lines_event      on public.baseline_lines(event_id);
create index if not exists idx_supplier_offers_event     on public.supplier_offers(event_id);
create index if not exists idx_supplier_offer_lines_event on public.supplier_offer_lines(event_id);
create index if not exists idx_awards_event              on public.awards(event_id);
create index if not exists idx_award_lines_event         on public.award_lines(event_id);
create index if not exists idx_savings_calculations_event on public.savings_calculations(event_id);
create index if not exists idx_realization_periods_event on public.realization_periods(event_id);

-- parent-row FKs
create index if not exists idx_baseline_lines_baseline   on public.baseline_lines(baseline_id);
create index if not exists idx_supplier_offer_lines_offer on public.supplier_offer_lines(offer_id);
create index if not exists idx_awards_offer              on public.awards(offer_id);
create index if not exists idx_award_lines_award         on public.award_lines(award_id);
create index if not exists idx_savings_calculations_baseline on public.savings_calculations(baseline_id);
create index if not exists idx_savings_calculations_award   on public.savings_calculations(award_id);
create index if not exists idx_savings_calculation_lines_calc on public.savings_calculation_lines(savings_calculation_id);
create index if not exists idx_realization_periods_calc  on public.realization_periods(savings_calculation_id);

-- classification / supplier FKs on sourcing_events
create index if not exists idx_sourcing_events_category  on public.sourcing_events(category_id);
create index if not exists idx_sourcing_events_bu        on public.sourcing_events(business_unit_id);
create index if not exists idx_sourcing_events_incumbent on public.sourcing_events(incumbent_supplier_id);
create index if not exists idx_sourcing_events_awarded   on public.sourcing_events(awarded_supplier_id);

-- ---------------------------------------------------------------------
-- 2) Uniqueness invariants the app enforces with non-atomic client loops.
--    A partial unique index makes "at most one official/selected per event"
--    a real DB guarantee (and fixes the race that could break .maybeSingle()).
--    ⚠️ May fail if existing data already has duplicates — see pre-flight query.
-- ---------------------------------------------------------------------
create unique index if not exists uq_baselines_official_hard_savings
  on public.baselines(event_id) where official_for_hard_savings;
create unique index if not exists uq_baselines_official_cost_avoidance
  on public.baselines(event_id) where official_for_cost_avoidance;
create unique index if not exists uq_baselines_official_demand_reduction
  on public.baselines(event_id) where official_for_demand_reduction;
create unique index if not exists uq_supplier_offers_selected_award
  on public.supplier_offers(event_id) where selected_for_award_flag;

-- ---------------------------------------------------------------------
-- 3) CHECK constraints for status/enum columns that today are plain text
--    (validity enforced only by frontend dropdowns). Added NOT VALID so
--    existing rows are untouched; new writes must conform.
--
--    NOTE: the value lists below come from the app's frontend enums. Before
--    trusting them, confirm against your data, e.g.:
--        select distinct realization_status from public.realization_periods;
--    and adjust the IN(...) lists to match. Columns where I was NOT certain of
--    the full set are left as commented templates.
-- ---------------------------------------------------------------------

alter table public.realization_periods drop constraint if exists chk_realization_status;
alter table public.realization_periods add constraint chk_realization_status
  check (realization_status in
    ('Pending','In Progress','Realized','Partially Realized','Not Realized','Leaked')) not valid;

alter table public.supplier_offers drop constraint if exists chk_offer_type;
alter table public.supplier_offers add constraint chk_offer_type
  check (offer_type in ('Initial','Revised','Best and Final (BAFO)','Counter','Final')) not valid;

alter table public.baselines drop constraint if exists chk_baseline_lock_status;
alter table public.baselines add constraint chk_baseline_lock_status
  check (baseline_lock_status in ('Draft','Locked','Submitted','Approved','Rejected')) not valid;

-- compliance_status lives on supplier_offer_lines (line-level compliance).
-- Verify the column/table, then uncomment:
-- alter table public.supplier_offer_lines drop constraint if exists chk_compliance_status;
-- alter table public.supplier_offer_lines add constraint chk_compliance_status
--   check (compliance_status in ('Compliant','Non-Compliant','Conditional','Pending Review')) not valid;

-- award_status — confirm the full set first (select distinct award_status from awards;)
-- alter table public.awards drop constraint if exists chk_award_status;
-- alter table public.awards add constraint chk_award_status
--   check (award_status in ('Recommended','Approved','Rejected','Contracted')) not valid;

-- calculation_status — confirm the full set first
-- (select distinct calculation_status from savings_calculations;)
-- alter table public.savings_calculations drop constraint if exists chk_calculation_status;
-- alter table public.savings_calculations add constraint chk_calculation_status
--   check (calculation_status in ('identified','negotiated','contracted','realized')) not valid;

commit;

-- ---------------------------------------------------------------------
-- PRE-FLIGHT (run BEFORE the migration): find any existing duplicates that
-- would make the §2 unique indexes fail. Each query should return 0 rows.
-- ---------------------------------------------------------------------
-- select event_id, count(*) from public.baselines where official_for_hard_savings
--   group by event_id having count(*) > 1;
-- select event_id, count(*) from public.baselines where official_for_cost_avoidance
--   group by event_id having count(*) > 1;
-- select event_id, count(*) from public.baselines where official_for_demand_reduction
--   group by event_id having count(*) > 1;
-- select event_id, count(*) from public.supplier_offers where selected_for_award_flag
--   group by event_id having count(*) > 1;

-- ---------------------------------------------------------------------
-- AFTER applying + confirming data is clean, you can promote the CHECKs from
-- NOT VALID to fully enforced with:
--   alter table public.realization_periods validate constraint chk_realization_status;
--   alter table public.supplier_offers    validate constraint chk_offer_type;
--   alter table public.baselines          validate constraint chk_baseline_lock_status;
-- ---------------------------------------------------------------------
