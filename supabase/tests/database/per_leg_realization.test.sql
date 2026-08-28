begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select plan(9);

select has_column('public', 'realization_periods', 'projected_reduction_amount', 'realization stores its executed reduction comparator');
select has_column('public', 'realization_periods', 'projected_avoidance_amount', 'realization stores its executed avoidance comparator');
select has_column('public', 'realization_periods', 'realized_reduction_amount', 'realization stores achieved reduction separately');
select has_column('public', 'realization_periods', 'realized_avoidance_amount', 'realization stores achieved avoidance separately');

update public.organization_settings
set savings_realization_enabled = true
where organization_id = '00000000-0000-4000-8000-000000000001';

insert into public.realization_periods (
  id, organization_id, event_id, savings_calculation_id, savings_period_id,
  period_name, period_start_date, period_end_date,
  baseline_amount, projected_savings, realized_savings, leakage_amount,
  realization_status
) values (
  'a6000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000021',
  '00000000-0000-4000-8000-000000000051',
  '00000000-0000-4000-8000-000000000061',
  'Per-leg test', '2026-08-01', '2027-07-31',
  0, 0, null, null, 'Pending'
);

select ok(
  (select projected_reduction_amount = 100000
      and projected_avoidance_amount = 200000
      and projected_savings = 300000
      and realized_savings is null
      and leakage_amount is null
      and realization_status = 'Pending'
   from public.realization_periods
   where id = 'a6000000-0000-4000-8000-000000000001'),
  'the linked executed schedule seeds both comparators and a pending total'
);

update public.realization_periods
set realized_reduction_amount = 80000,
    realized_avoidance_amount = 200000
where id = 'a6000000-0000-4000-8000-000000000001';

select ok(
  (select realized_savings = 280000
      and leakage_amount = 20000
      and realization_status = 'Partially Realized'
   from public.realization_periods
   where id = 'a6000000-0000-4000-8000-000000000001'),
  'reduction leakage compares reduction to reduction while total realized stays additive'
);

update public.realization_periods
set realized_reduction_amount = 100000,
    realized_avoidance_amount = 0,
    realized_savings = 999999,
    leakage_amount = 999999,
    realization_status = 'Leaked'
where id = 'a6000000-0000-4000-8000-000000000001';

select ok(
  (select realized_savings = 100000
      and leakage_amount = 0
      and realization_status = 'Partially Realized'
   from public.realization_periods
   where id = 'a6000000-0000-4000-8000-000000000001'),
  'derived fields ignore tampering and avoidance shortfall is never leakage'
);

update public.realization_periods
set actual_amount = 950000
where id = 'a6000000-0000-4000-8000-000000000001';

select ok(
  (select realized_reduction_amount = 50000
      and realized_avoidance_amount = 0
      and realized_savings = 50000
      and leakage_amount = 50000
      and realization_status = 'Partially Realized'
   from public.realization_periods
   where id = 'a6000000-0000-4000-8000-000000000001'),
  'the database derives the reduction leg from actual spend for every writer'
);

select ok(
  has_column_privilege('authenticated', 'public.realization_periods', 'realized_reduction_amount', 'UPDATE')
  and has_column_privilege('authenticated', 'public.realization_periods', 'realized_avoidance_amount', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.realization_periods', 'realized_savings', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.realization_periods', 'leakage_amount', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.realization_periods', 'realization_status', 'UPDATE'),
  'signed-in commercial editors write only per-leg inputs, never derived outputs'
);

select * from finish();
rollback;
