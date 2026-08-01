-- =====================================================================
-- P4: TERM IN MONTHS ON EVERY ANCHOR
-- =====================================================================
-- Step 1 of the period model.
--
-- Every anchor (baseline, offer) carries an amount AND a term in months.
-- From those two the app derives:
--     per_month = amount / months
--     per_year  = per_month * 12
-- and runs the savings chain on the RATES rather than the raw totals.
--
-- Why months and not start/end dates: it removes date arithmetic entirely
-- (no day-counting, no timezone edge cases, no proration guesswork) and it
-- makes unlike terms directly comparable. Today a 12-month baseline is
-- silently subtracted from a 36-month offer; normalising to a monthly rate
-- fixes that.
--
-- Escalators are baked into the offer price by the buyer, so a single
-- amount + term stays exact.
--
-- The existing period-start/period-end columns are LEFT IN PLACE (they are
-- documentation of what the baseline covers). Nothing reads them.
-- =====================================================================

begin;

alter table public.baselines
  add column if not exists baseline_term_months numeric;

alter table public.supplier_offers
  add column if not exists offer_term_months numeric;

comment on column public.baselines.baseline_term_months is
  'Term the baseline_total_amount covers, in months. Used to derive a monthly '
  'rate (amount / months) so baselines and offers of different lengths can be '
  'compared like with like. NULL means the term was not captured.';

comment on column public.supplier_offers.offer_term_months is
  'Term the offer_total_amount covers, in months. Used to derive a monthly rate. '
  'Any annual escalator should be priced into offer_total_amount. '
  'NULL means the term was not captured.';

-- Backfill: anything already entered was implicitly a 12-month figure.
update public.baselines
   set baseline_term_months = 12
 where baseline_term_months is null;

update public.supplier_offers
   set offer_term_months = 12
 where offer_term_months is null;

commit;

-- ---------------------------------------------------------------------
-- VERIFY (run separately)
-- ---------------------------------------------------------------------
-- select column_name, data_type from information_schema.columns
--  where (table_name, column_name) in
--        (('baselines','baseline_term_months'), ('supplier_offers','offer_term_months'));
--
-- select baseline_name, baseline_total_amount, baseline_term_months,
--        round(baseline_total_amount / nullif(baseline_term_months,0), 2) as per_month,
--        round(baseline_total_amount / nullif(baseline_term_months,0) * 12, 2) as per_year
--   from public.baselines;
