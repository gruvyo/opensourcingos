-- =====================================================================
-- P11: HARD-REDUCTION OVERRIDE ON A BASELINE
-- =====================================================================
-- Implements the governing principle ruled 2026-07-18: a HARD cost
-- reduction requires a baseline grounded in your own spend, not in a
-- vendor's ask or a market figure.
--
-- The classification itself lives in code, in lib/savings, alongside every
-- other rule about what a number means -- not in this table. Baseline types
-- are free text with no CHECK constraint, the mapping is a business rule
-- that will be revised, and lib/savings is the single source of truth by
-- design. What lives HERE is only the deliberate, per-baseline exception.
--
-- Ruled 2026-07-28: Approved Budget counts as SOFT, not as its own third
-- category. A department's budget is an internal reference figure, close to
-- a market index -- it is not money that was actually paid. Two states, not
-- three.
--
-- THE OVERRIDE. A buyer can declare a soft baseline good enough to book as
-- hard, provided they write down why. Real cases exist: the invoices for
-- last year are unavailable, but the incumbent's renewal quote is known to
-- match what was actually paid.
--
-- The risk with any override is that it becomes the default path, so this
-- one is recorded rather than merely allowed: who, when, and the reason,
-- surfaced on the Baselines tab, in the Calculations tab, in reports and in
-- the CSV export. An override nobody can find later is not defensible; one
-- that shows up in every report is.
--
-- IMPORTANT: an override never changes the TOTAL. It only moves money
-- between the Cost Reduction and Cost Avoidance lines. The headline figure
-- is identical either way -- see chainWithBaselineQuality() in lib/savings.
--
-- SAFE: additive columns with defaults. No existing row changes meaning,
-- and every baseline type currently in use already qualifies as hard, so
-- applying this migration changes no number anywhere.
-- =====================================================================

begin;

alter table public.baselines
  add column if not exists hard_reduction_override boolean not null default false,
  add column if not exists hard_reduction_override_reason text,
  add column if not exists hard_reduction_override_by uuid,
  add column if not exists hard_reduction_override_at timestamptz;

-- An override without a reason is exactly the shrug this is meant to stop.
alter table public.baselines drop constraint if exists chk_hard_reduction_override_reason;
alter table public.baselines add constraint chk_hard_reduction_override_reason
  check (
    hard_reduction_override = false
    or (hard_reduction_override_reason is not null
        and length(btrim(hard_reduction_override_reason)) >= 10)
  );

comment on column public.baselines.hard_reduction_override is
  'True when a buyer has declared this baseline good enough to book a HARD '
  'cost reduction despite its type being classified as soft. Never changes '
  'the Total -- only moves money between the Reduction and Avoidance lines.';
comment on column public.baselines.hard_reduction_override_reason is
  'Why this baseline is defensible as own-spend despite its type. Required '
  'when the override is on, minimum 10 characters, enforced by CHECK.';

commit;

-- ---------------------------------------------------------------------
-- VERIFY (run separately)
-- ---------------------------------------------------------------------
-- select column_name, data_type, is_nullable, column_default
--   from information_schema.columns
--  where table_schema = 'public' and table_name = 'baselines'
--    and column_name like 'hard_reduction%'
--  order by column_name;
--
-- The CHECK must reject an override with no reason:
--   update public.baselines set hard_reduction_override = true
--    where id = (select id from public.baselines limit 1);
--   -> ERROR: violates check constraint "chk_hard_reduction_override_reason"
--
-- Every override on file, which is what an auditor would ask for:
-- select e.event_name, b.baseline_type, b.hard_reduction_override_reason,
--        b.hard_reduction_override_at
--   from public.baselines b
--   join public.sourcing_events e on e.id = b.event_id
--  where b.hard_reduction_override
--  order by b.hard_reduction_override_at desc;
