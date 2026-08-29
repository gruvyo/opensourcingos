begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select plan(9);

-- Replays the V8 portability repair from
-- 20260829005844_qa_r2_remaining_core.sql against a reconstructed legacy
-- population. The repair matched zero rows in production and matches zero on a
-- fresh rebuild, so without this replay its UPDATE would never execute against
-- a matched row. The legacy shells predate the per-leg derivation trigger, so
-- they are planted with that trigger disabled, then the repair runs with it
-- re-enabled — the exact condition under which the migration executed.

update public.organization_settings
set savings_realization_enabled = true
where organization_id = '00000000-0000-4000-8000-000000000001';

alter table public.realization_periods
  disable trigger realization_periods_derive_per_leg_fields;

-- Six rows sharing the derived-consistent 'Leaked' zero-realization shape.
-- Row ...b1 is the unambiguous empty-evidence shell the repair must return to
-- Pending; each other row differs on exactly one repair predicate and must
-- survive untouched. savings_period_id stays null so the derivation trigger
-- cannot rewrite the planted comparators during the replay.
insert into public.realization_periods (
  id, organization_id, event_id, savings_calculation_id, savings_period_id,
  period_name, period_start_date, period_end_date,
  baseline_amount, projected_reduction_amount, projected_avoidance_amount,
  projected_savings, actual_amount, realized_reduction_amount,
  realized_avoidance_amount, realized_savings, leakage_amount,
  realization_status, finance_validated, finance_validated_by,
  finance_validation_date, evidence_document_id, notes, leakage_reason
) values
  ('a8000000-0000-4000-8000-0000000000b1',
   '00000000-0000-4000-8000-000000000001',
   '00000000-0000-4000-8000-000000000021',
   '00000000-0000-4000-8000-000000000051',
   null,
   'V8 shell', '2026-01-01', '2026-12-31',
   100000, 100000, null, 100000, 0, 0, null, 0, 100000,
   'Leaked', false, null, null, null, null, null),
  ('a8000000-0000-4000-8000-0000000000b2',
   '00000000-0000-4000-8000-000000000001',
   '00000000-0000-4000-8000-000000000021',
   '00000000-0000-4000-8000-000000000051',
   null,
   'V8 near-miss: notes', '2026-01-01', '2026-12-31',
   100000, 100000, null, 100000, 0, 0, null, 0, 100000,
   'Leaked', false, null, null, null, 'Reviewed with finance', null),
  ('a8000000-0000-4000-8000-0000000000b3',
   '00000000-0000-4000-8000-000000000001',
   '00000000-0000-4000-8000-000000000021',
   '00000000-0000-4000-8000-000000000051',
   null,
   'V8 near-miss: avoidance entered', '2026-01-01', '2026-12-31',
   100000, 100000, null, 100000, 0, 0, 0, 0, 100000,
   'Leaked', false, null, null, null, null, null),
  ('a8000000-0000-4000-8000-0000000000b4',
   '00000000-0000-4000-8000-000000000001',
   '00000000-0000-4000-8000-000000000021',
   '00000000-0000-4000-8000-000000000051',
   null,
   'V8 near-miss: finance validated', '2026-01-01', '2026-12-31',
   100000, 100000, null, 100000, 0, 0, null, 0, 100000,
   'Leaked', true, '00000000-0000-4000-8000-000000000002',
   '2026-08-01T00:00:00Z', null, null, null),
  ('a8000000-0000-4000-8000-0000000000b5',
   '00000000-0000-4000-8000-000000000001',
   '00000000-0000-4000-8000-000000000021',
   '00000000-0000-4000-8000-000000000051',
   null,
   'V8 near-miss: actual spend', '2026-01-01', '2026-12-31',
   100000, 100000, null, 100000, 250000, 0, null, 0, 100000,
   'Leaked', false, null, null, null, null, null),
  ('a8000000-0000-4000-8000-0000000000b6',
   '00000000-0000-4000-8000-000000000001',
   '00000000-0000-4000-8000-000000000021',
   '00000000-0000-4000-8000-000000000051',
   null,
   'V8 near-miss: leakage reason', '2026-01-01', '2026-12-31',
   100000, 100000, null, 100000, 0, 0, null, 0, 100000,
   'Leaked', false, null, null, null, null, 'Supplier price increase');

alter table public.realization_periods
  enable trigger realization_periods_derive_per_leg_fields;

select is(
  (select tgenabled::text from pg_trigger
   where tgrelid = 'public.realization_periods'::regclass
     and tgname = 'realization_periods_derive_per_leg_fields'),
  'O',
  'the repair replays with the per-leg derivation trigger active, as at migration time'
);

-- The repair UPDATE, verbatim from 20260829005844_qa_r2_remaining_core.sql.
update public.realization_periods
set actual_amount = null,
    realized_reduction_amount = null,
    realized_savings = null,
    leakage_amount = null,
    realization_status = 'Pending'
where actual_amount = 0
  and realized_reduction_amount = 0
  and realized_avoidance_amount is null
  and realized_savings = 0
  and realization_status = 'Leaked'
  and not finance_validated
  and evidence_document_id is null
  and notes is null
  and leakage_reason is null;

select ok(
  (select actual_amount is null
      and realized_reduction_amount is null
      and realized_avoidance_amount is null
      and realized_savings is null
      and leakage_amount is null
      and realization_status = 'Pending'
   from public.realization_periods
   where id = 'a8000000-0000-4000-8000-0000000000b1'),
  'the empty-evidence shell returns to Pending with every realized field cleared'
);

select ok(
  (select projected_reduction_amount = 100000
      and projected_avoidance_amount is null
      and projected_savings = 100000
   from public.realization_periods
   where id = 'a8000000-0000-4000-8000-0000000000b1'),
  'the repaired shell keeps its projected comparators'
);

select ok(
  (select realization_status = 'Leaked' and realized_savings = 0
      and notes = 'Reviewed with finance'
   from public.realization_periods
   where id = 'a8000000-0000-4000-8000-0000000000b2'),
  'a zero-realization row carrying notes is evidence and stays Leaked'
);

select ok(
  (select realization_status = 'Leaked' and realized_savings = 0
      and realized_avoidance_amount = 0
   from public.realization_periods
   where id = 'a8000000-0000-4000-8000-0000000000b3'),
  'an entered zero avoidance leg is evidence and stays Leaked'
);

select ok(
  (select realization_status = 'Leaked' and realized_savings = 0
      and finance_validated
   from public.realization_periods
   where id = 'a8000000-0000-4000-8000-0000000000b4'),
  'a finance-validated row stays Leaked'
);

select ok(
  (select realization_status = 'Leaked' and realized_savings = 0
      and actual_amount = 250000
   from public.realization_periods
   where id = 'a8000000-0000-4000-8000-0000000000b5'),
  'a row with recorded actual spend stays Leaked'
);

select ok(
  (select realization_status = 'Leaked' and realized_savings = 0
      and leakage_reason = 'Supplier price increase'
   from public.realization_periods
   where id = 'a8000000-0000-4000-8000-0000000000b6'),
  'a row with a leakage reason stays Leaked'
);

select is(
  (select count(*) from public.realization_periods
   where id::text like 'a8000000-0000-4000-8000-0000000000b_'
     and realization_status = 'Pending'),
  1::bigint,
  'the repair touches exactly one of the six planted rows'
);

select * from finish();
rollback;
