begin;

select plan(11);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.savings_periods'::regclass
      and conname = 'chk_savings_periods_estimated_chain'
      and convalidated
  ),
  'the estimated schedule chain constraint is validated'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.savings_periods'::regclass
      and conname = 'chk_savings_periods_executed_chain'
      and convalidated
  ),
  'the executed schedule chain constraint is validated'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.savings_calculations'::regclass
      and conname = 'chk_savings_calculations_chain'
      and convalidated
  ),
  'the calculation headline chain constraint is validated'
);

select lives_ok(
  $$
    update public.savings_periods
    set opening_amount = 900,
        cost_avoidance_amount = -100,
        total_savings_amount = 0,
        executed_opening_amount = 900,
        executed_cost_avoidance_amount = -100,
        executed_total_savings_amount = 0
    where id = '00000000-0000-4000-8000-000000000061'
  $$,
  'Opening below Baseline remains a signed negative avoidance leg'
);

select ok(
  (select cost_avoidance_amount = -100 and total_savings_amount = 0
   from public.savings_periods
   where id = '00000000-0000-4000-8000-000000000061')
  and
  (select executed_cost_avoidance_amount = -100
      and executed_total_savings_amount = 0
   from public.savings_periods
   where id = '00000000-0000-4000-8000-000000000061'),
  'estimated and executed snapshots preserve the same negative avoidance result'
);

select throws_ok(
  $$
    update public.savings_periods
    set total_savings_amount = 1
    where id = '00000000-0000-4000-8000-000000000061'
  $$,
  '23514', null,
  'the database rejects a schedule headline that disagrees with its legs'
);

select lives_ok(
  $$
    update public.savings_calculations
    set opening_proposal_amount = 2700000,
        cost_avoidance_amount = -300000,
        gross_savings_amount = 0,
        net_savings_amount = 0
    where id = '00000000-0000-4000-8000-000000000051'
  $$,
  'the calculation headline accepts the same signed negative avoidance leg'
);

select throws_ok(
  $$
    update public.savings_calculations
    set gross_savings_amount = 1
    where id = '00000000-0000-4000-8000-000000000051'
  $$,
  '23514', null,
  'the database rejects a calculation headline that disagrees with its legs'
);

select throws_ok(
  $$ delete from public.sourcing_events
     where id = '00000000-0000-4000-8000-000000000021' $$,
  'P0001', 'reverse executed savings before deleting the project',
  'an executed calculation blocks project cascade deletion without realization rows'
);

select throws_ok(
  $$ delete from public.baselines
     where id = '00000000-0000-4000-8000-000000000031' $$,
  'P0001', 'reverse executed savings before deleting the baseline',
  'an executed calculation blocks baseline SET NULL without realization rows'
);

insert into public.awards (
  id, organization_id, event_id, award_name, award_total_amount
) values (
  '00000000-0000-4000-8000-000000000071',
  '00000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000021',
  'Executed calculation retention fixture',
  2700000
);

update public.savings_calculations
set award_id = '00000000-0000-4000-8000-000000000071'
where id = '00000000-0000-4000-8000-000000000051';

select throws_ok(
  $$ delete from public.awards
     where id = '00000000-0000-4000-8000-000000000071' $$,
  'P0001', 'reverse executed savings before deleting the award',
  'an executed calculation blocks award SET NULL without realization rows'
);

select * from finish();
rollback;
