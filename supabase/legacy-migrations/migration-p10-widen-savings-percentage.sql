-- =====================================================================
-- P10: WIDEN savings_percentage
-- =====================================================================
-- Found on 2026-07-28 by pulling the real schema into git for the first
-- time. Every migration before this one was written against a
-- RECONSTRUCTED guess at the schema -- P0 says so in its own header --
-- and this column was never in that guess.
--
-- savings_percentage is numeric(5,2) on both tables. Five digits with two
-- after the point means the largest storable value is 999.99. A savings
-- percentage of 1000% or more does not round or clamp; the INSERT fails
-- outright:
--
--   ERROR:  numeric field overflow
--   DETAIL: A field with precision 5, scale 2 must round to an absolute
--           value less than 10^3.
--
-- That is reachable without anyone doing anything wrong. The percentage's
-- denominator is BASELINE spend, so a small baseline against a large
-- vendor ask produces a large percentage honestly: a 10,000 baseline
-- against a 500,000 opening proposal is 4,800%, and the save fails. The
-- deal is real and the arithmetic is right; only the column is too narrow.
--
-- numeric(9,2) allows up to 9,999,999.99. Nothing legitimate reaches that,
-- so a value near it still reads as a data-entry error rather than being
-- silently accepted -- but no honest deal is blocked from saving.
--
-- SAFE: widening a numeric column cannot lose data and cannot truncate.
-- Existing values are unchanged. Idempotent -- re-running it does nothing.
-- =====================================================================

begin;

alter table public.savings_calculations
  alter column savings_percentage type numeric(9,2);

-- Line-level calculations are not currently written by the UI, but the
-- column has the same ceiling and would fail the same way.
alter table public.savings_calculation_lines
  alter column savings_percentage type numeric(9,2);

comment on column public.savings_calculations.savings_percentage is
  'Total savings as a percentage of BASELINE spend (never of the opening ask '
  'or the awarded amount). NULL means not applicable -- no baseline anchor. '
  'Written only by reportableSavingsPct() in lib/savings.';

commit;

-- ---------------------------------------------------------------------
-- VERIFY (run separately)
-- ---------------------------------------------------------------------
-- select table_name, column_name, numeric_precision, numeric_scale
--   from information_schema.columns
--  where table_schema = 'public' and column_name = 'savings_percentage';
--   -> both rows should read precision 9, scale 2
--
-- And the value that used to fail should now be storable:
-- select 4800.00::numeric(9,2);
