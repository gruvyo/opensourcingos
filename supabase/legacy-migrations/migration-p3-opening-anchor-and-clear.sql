-- =====================================================================
-- P3: THE OPENING ANCHOR + CLEAR THE SAMPLE DATA
-- =====================================================================
-- Two things, in one transaction:
--
--   1. Add opening_proposal_amount to savings_calculations. This is the
--      missing third anchor. Without it the app could only ever compute
--      (Baseline - Final) = Cost Reduction, and reported that as the
--      headline -- silently dropping the entire avoidance leg.
--
--      THE CHAIN:  Opening -> Baseline -> Final
--        Cost Reduction = Baseline - Final    (hard, hits P&L, MAY BE NEGATIVE)
--        Cost Avoidance = Opening  - Baseline (soft)
--        Total          = Opening  - Final    = Reduction + Avoidance, exactly.
--
--      NULLABLE ON PURPOSE. NULL means "no opening captured", which is a
--      distinct state from 0. A 0 would assert the vendor asked for nothing.
--      When opening is NULL the chain collapses: Total = Reduction.
--      When there is no baseline, the whole span books as avoidance and
--      Cost Reduction is NOT APPLICABLE (stored NULL, never 0).
--
--   2. Clear ALL transactional demo data so real deals can be walked
--      through from a clean slate. Because nothing historical survives,
--      there is NO restatement risk from the new math -- which is what
--      makes this migration safe and simple.
--
-- KEPT: organizations, profiles (your login), and the dimension tables
-- (categories, business_units, cost_centers, suppliers) so you are not
-- retyping reference data. Set KEEP_DIMENSIONS to false below to wipe
-- those too.
--
-- A full JSON backup of the ORIGINAL sample data (pre-demo-rebuild) is at
-- ../sample-data-backup-2026-07-26.json. The current demo rows are
-- reproducible any time by re-running migration-p2-demo-dataset.sql.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1) The opening anchor
-- ---------------------------------------------------------------------
alter table public.savings_calculations
  add column if not exists opening_proposal_amount numeric;

comment on column public.savings_calculations.opening_proposal_amount is
  'The vendor''s opening proposal - the third anchor in the chain '
  '(Opening -> Baseline -> Final). NULL means no opening was captured, which '
  'is distinct from 0. Cost Avoidance = Opening - Baseline. '
  'Total procurement performance = Opening - Final = Reduction + Avoidance.';

comment on column public.savings_calculations.gross_savings_amount is
  'THE CHAIN TOTAL (Opening - Final) - the reported headline. Equals '
  'cost_reduction_amount + cost_avoidance_amount exactly. When no opening was '
  'captured this collapses to Cost Reduction (Baseline - Final).';

comment on column public.savings_calculations.cost_reduction_amount is
  'Baseline - Final. Hard, hits the P&L. MAY BE NEGATIVE (a genuine cost '
  'increase) - show in parentheses, never sign-flip, never relabel as savings. '
  'NULL means NOT APPLICABLE (no baseline anchor), distinct from 0.';

comment on column public.savings_calculations.cost_avoidance_amount is
  'Opening - Baseline. Soft. With no baseline anchor the whole span books here.';

-- ---------------------------------------------------------------------
-- 2) Clear the transactional data (children first via CASCADE).
--    organizations + profiles are NOT touched, so your login survives.
-- ---------------------------------------------------------------------
truncate table
  public.realization_periods,
  public.savings_calculation_lines,
  public.savings_calculations,
  public.award_lines,
  public.awards,
  public.supplier_offer_lines,
  public.supplier_offers,
  public.baseline_lines,
  public.baselines,
  public.event_scope_lines,
  public.sourcing_events
  restart identity cascade;

-- Dimensions are KEPT by default so you are not retyping reference data.
-- To wipe them as well, uncomment:
-- truncate table public.cost_centers, public.suppliers,
--   public.business_units, public.categories restart identity cascade;

commit;

-- ---------------------------------------------------------------------
-- VERIFY (run separately; every count should be 0 except the dimensions)
-- ---------------------------------------------------------------------
-- select 'events' t, count(*) n from public.sourcing_events
-- union all select 'calcs', count(*) from public.savings_calculations
-- union all select 'baselines', count(*) from public.baselines
-- union all select 'offers', count(*) from public.supplier_offers
-- union all select 'awards', count(*) from public.awards
-- union all select 'suppliers (kept)', count(*) from public.suppliers
-- union all select 'categories (kept)', count(*) from public.categories
-- union all select 'business_units (kept)', count(*) from public.business_units
-- union all select 'profiles (kept)', count(*) from public.profiles
-- order by 1;
--
-- select column_name from information_schema.columns
--  where table_name='savings_calculations' and column_name='opening_proposal_amount';
