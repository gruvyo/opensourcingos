begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select plan(40);

insert into auth.users (id, email, raw_user_meta_data)
values
  ('b1000000-0000-4000-8000-000000000001', 'lifecycle-admin@example.test', '{"full_name":"Lifecycle Admin"}'),
  ('b1000000-0000-4000-8000-000000000002', 'lifecycle-procurement@example.test', '{"full_name":"Lifecycle Procurement"}'),
  ('b1000000-0000-4000-8000-000000000003', 'lifecycle-viewer@example.test', '{"full_name":"Lifecycle Viewer"}');

update public.profiles set role = 'procurement_user'
where id = 'b1000000-0000-4000-8000-000000000002';
update public.profiles set role = 'viewer'
where id = 'b1000000-0000-4000-8000-000000000003';

select is(
  (
    select count(*)::integer
    from public.savings_calculations calculation
    join public.profiles profile on profile.organization_id = calculation.organization_id
    where profile.id in (
      'b1000000-0000-4000-8000-000000000001',
      'b1000000-0000-4000-8000-000000000002',
      'b1000000-0000-4000-8000-000000000003'
    )
      and calculation.calculation_status = 'executed'
      and calculation.executed_by = profile.id
  ),
  3,
  'demo cloning attributes each copied execution to the new workspace owner'
);

select is(
  (
    select count(*)::integer
    from public.sourcing_events event
    join public.profiles profile on profile.organization_id = event.organization_id
    where profile.id in (
      'b1000000-0000-4000-8000-000000000001',
      'b1000000-0000-4000-8000-000000000002',
      'b1000000-0000-4000-8000-000000000003'
    )
      and event.savings_disposition = 'executed'
      and event.savings_disposition_by = profile.id
  ),
  3,
  'demo cloning attributes each copied disposition to the new workspace owner'
);

insert into public.organization_settings (organization_id, savings_realization_enabled)
values (
  (select organization_id from public.profiles where id = 'b1000000-0000-4000-8000-000000000001'),
  true
)
on conflict (organization_id) do update set savings_realization_enabled = excluded.savings_realization_enabled;

insert into public.sourcing_events (
  id, organization_id, event_name, event_type, event_status, project_type
)
values
  (
    'b2000000-0000-4000-8000-000000000001',
    (select organization_id from public.profiles where id = 'b1000000-0000-4000-8000-000000000001'),
    'Correction project', 'Contract Renewal', 'Pipeline', 'Sourcing'
  ),
  (
    'b2000000-0000-4000-8000-000000000002',
    (select organization_id from public.profiles where id = 'b1000000-0000-4000-8000-000000000001'),
    'Open reversal project', 'Contract Renewal', 'Pipeline', 'Sourcing'
  ),
  (
    'b2000000-0000-4000-8000-000000000003',
    (select organization_id from public.profiles where id = 'b1000000-0000-4000-8000-000000000001'),
    'Complete reversal project', 'Contract Renewal', 'Pipeline', 'Sourcing'
  ),
  (
    'b2000000-0000-4000-8000-000000000004',
    (select organization_id from public.profiles where id = 'b1000000-0000-4000-8000-000000000002'),
    'Procurement correction project', 'Contract Renewal', 'Pipeline', 'Sourcing'
  );

insert into public.savings_calculations (
  id, organization_id, event_id, calculation_name, savings_type,
  calculation_status, schedule_start_month, schedule_start_year,
  schedule_period_type, schedule_period_count
)
values
  (
    'b3000000-0000-4000-8000-000000000001',
    (select organization_id from public.profiles where id = 'b1000000-0000-4000-8000-000000000001'),
    'b2000000-0000-4000-8000-000000000001', 'Correction schedule',
    'Cost Avoidance', 'estimated', 8, 2026, 'monthly', 2
  ),
  (
    'b3000000-0000-4000-8000-000000000002',
    (select organization_id from public.profiles where id = 'b1000000-0000-4000-8000-000000000001'),
    'b2000000-0000-4000-8000-000000000002', 'Open reversal schedule',
    'Cost Avoidance', 'estimated', 8, 2026, 'monthly', 1
  ),
  (
    'b3000000-0000-4000-8000-000000000003',
    (select organization_id from public.profiles where id = 'b1000000-0000-4000-8000-000000000001'),
    'b2000000-0000-4000-8000-000000000003', 'Complete reversal schedule',
    'Cost Avoidance', 'estimated', 8, 2026, 'monthly', 1
  ),
  (
    'b3000000-0000-4000-8000-000000000004',
    (select organization_id from public.profiles where id = 'b1000000-0000-4000-8000-000000000002'),
    'b2000000-0000-4000-8000-000000000004', 'Procurement schedule',
    'Cost Avoidance', 'estimated', 8, 2026, 'monthly', 1
  );

insert into public.savings_periods (
  id, organization_id, event_id, savings_calculation_id,
  period_number, period_month, period_year, period_months,
  baseline_amount, opening_amount, final_amount,
  cost_reduction_amount, cost_avoidance_amount, total_savings_amount
)
values
  (
    'b4000000-0000-4000-8000-000000000001',
    (select organization_id from public.profiles where id = 'b1000000-0000-4000-8000-000000000001'),
    'b2000000-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-000000000001',
    1, 8, 2026, 1, 500, 600, 450, 50, 100, 150
  ),
  (
    'b4000000-0000-4000-8000-000000000002',
    (select organization_id from public.profiles where id = 'b1000000-0000-4000-8000-000000000001'),
    'b2000000-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-000000000001',
    2, 9, 2026, 1, 500, 600, 450, 50, 100, 150
  ),
  (
    'b4000000-0000-4000-8000-000000000003',
    (select organization_id from public.profiles where id = 'b1000000-0000-4000-8000-000000000001'),
    'b2000000-0000-4000-8000-000000000002', 'b3000000-0000-4000-8000-000000000002',
    1, 8, 2026, 1, 500, 600, 450, 50, 100, 150
  ),
  (
    'b4000000-0000-4000-8000-000000000004',
    (select organization_id from public.profiles where id = 'b1000000-0000-4000-8000-000000000001'),
    'b2000000-0000-4000-8000-000000000003', 'b3000000-0000-4000-8000-000000000003',
    1, 8, 2026, 1, 500, 600, 450, 50, 100, 150
  ),
  (
    'b4000000-0000-4000-8000-000000000005',
    (select organization_id from public.profiles where id = 'b1000000-0000-4000-8000-000000000002'),
    'b2000000-0000-4000-8000-000000000004', 'b3000000-0000-4000-8000-000000000004',
    1, 8, 2026, 1, 500, 600, 450, 50, 100, 150
  );

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b1000000-0000-4000-8000-000000000001', true);

select lives_ok(
  $$ select public.mark_savings_schedule_executed('b3000000-0000-4000-8000-000000000001', 'Initial execution') $$,
  'an administrator can execute an estimated schedule exactly once'
);
select ok(
  (select calculation_status = 'executed'
      and executed_at is not null
      and executed_by = 'b1000000-0000-4000-8000-000000000001'
      and not legacy_execution_actor_missing
   from public.savings_calculations where id = 'b3000000-0000-4000-8000-000000000001')
  and (select bool_and(executed_total_savings_amount = total_savings_amount)
       from public.savings_periods where savings_calculation_id = 'b3000000-0000-4000-8000-000000000001')
  and (select savings_disposition = 'executed'
       from public.sourcing_events where id = 'b2000000-0000-4000-8000-000000000001'),
  'execution atomically snapshots periods, stamps the calculation, and repairs disposition'
);
select throws_ok(
  $$ select public.mark_savings_schedule_executed('b3000000-0000-4000-8000-000000000001', 'Second execution') $$,
  'P0001', 'savings schedule is already executed',
  'executing the same schedule twice is refused'
);
select ok(
  exists (select 1 from public.audit_log where entity_type = 'savings_calculation' and entity_id = 'b3000000-0000-4000-8000-000000000001')
  and exists (select 1 from public.audit_log where entity_type = 'savings_period' and entity_id = 'b4000000-0000-4000-8000-000000000001')
  and exists (select 1 from public.audit_log where entity_type = 'sourcing_event' and entity_id = 'b2000000-0000-4000-8000-000000000001'),
  'execution records every coupled entity in the immutable audit stream'
);

update public.savings_calculations
set calculation_name = 'Tampered calculation'
where id = 'b3000000-0000-4000-8000-000000000001';
select is(
  (select calculation_name from public.savings_calculations where id = 'b3000000-0000-4000-8000-000000000001'),
  'Correction schedule',
  'ordinary authenticated calculation edits cannot change an executed record'
);

update public.savings_periods
set final_amount = 1
where id = 'b4000000-0000-4000-8000-000000000001';
select is(
  (select final_amount from public.savings_periods where id = 'b4000000-0000-4000-8000-000000000001'),
  450::numeric,
  'ordinary authenticated period edits cannot change an executed estimate'
);

select throws_ok(
  $$
    select public.correct_savings_execution(
      'b3000000-0000-4000-8000-000000000001', 'Attempt forged lifecycle change',
      '{"calculation_status":"estimated"}'::jsonb,
      '[]'::jsonb
    )
  $$,
  'P0001', 'calculation payload contains unsupported fields',
  'correction payloads reject lifecycle and protected fields'
);
select is(
  (select sum(executed_total_savings_amount) from public.savings_periods where savings_calculation_id = 'b3000000-0000-4000-8000-000000000001'),
  300::numeric,
  'a rejected correction leaves the executed values unchanged'
);

select lives_ok(
  $$
    select public.correct_savings_execution(
      'b3000000-0000-4000-8000-000000000001', 'Correct the first period final amount', '{}'::jsonb,
      '[
        {"id":"b4000000-0000-4000-8000-000000000001","period_number":1,"period_month":8,"period_year":2026,"period_months":1,"baseline_amount":500,"opening_amount":600,"final_amount":440,"cost_reduction_amount":60,"cost_avoidance_amount":100,"total_savings_amount":160,"is_edited":true},
        {"id":"b4000000-0000-4000-8000-000000000002","period_number":2,"period_month":9,"period_year":2026,"period_months":1,"baseline_amount":500,"opening_amount":600,"final_amount":450,"cost_reduction_amount":50,"cost_avoidance_amount":100,"total_savings_amount":150,"is_edited":false}
      ]'::jsonb
    )
  $$,
  'an administrator can atomically correct an executed schedule without realization rows'
);
select ok(
  (select gross_savings_amount = 310 and calculation_status = 'executed' and execution_note like '%Correction:%'
   from public.savings_calculations where id = 'b3000000-0000-4000-8000-000000000001')
  and (select total_savings_amount = 160 and executed_total_savings_amount = 160
       from public.savings_periods where id = 'b4000000-0000-4000-8000-000000000001'),
  'a correction changes the estimate and executed snapshot together and records its note'
);
select throws_ok(
  $$
    select public.correct_savings_execution(
      'b3000000-0000-4000-8000-000000000001', 'Invalid equation must roll back', '{}'::jsonb,
      '[
        {"id":"b4000000-0000-4000-8000-000000000001","period_number":1,"period_month":8,"period_year":2026,"period_months":1,"baseline_amount":500,"opening_amount":600,"final_amount":430,"cost_reduction_amount":70,"cost_avoidance_amount":100,"total_savings_amount":999},
        {"id":"b4000000-0000-4000-8000-000000000002","period_number":2,"period_month":9,"period_year":2026,"period_months":1,"baseline_amount":500,"opening_amount":600,"final_amount":450,"cost_reduction_amount":50,"cost_avoidance_amount":100,"total_savings_amount":150}
      ]'::jsonb
    )
  $$,
  'P0001', 'corrected periods must satisfy the approved savings equations',
  'a correction with inconsistent savings equations is refused'
);
select is(
  (select executed_total_savings_amount from public.savings_periods where id = 'b4000000-0000-4000-8000-000000000001'),
  160::numeric,
  'a failed correction rolls back every estimated and executed write'
);

do $$
begin
  perform public.sync_realization_periods('b2000000-0000-4000-8000-000000000001');
end
$$;
update public.realization_periods
set actual_amount = 400, realized_reduction_amount = 100,
    realized_avoidance_amount = 0
where savings_period_id = 'b4000000-0000-4000-8000-000000000001';

select lives_ok(
  $$ select public.set_finance_validation(
       (select id from public.realization_periods
        where savings_period_id = 'b4000000-0000-4000-8000-000000000001'), true
     ) $$,
  'finance validation setup uses the protected admin RPC'
);

select lives_ok(
  $$
    select public.correct_savings_execution(
      'b3000000-0000-4000-8000-000000000001', 'Rebase against corrected executed value', '{}'::jsonb,
      '[
        {"id":"b4000000-0000-4000-8000-000000000001","period_number":1,"period_month":8,"period_year":2026,"period_months":1,"baseline_amount":500,"opening_amount":600,"final_amount":430,"cost_reduction_amount":70,"cost_avoidance_amount":100,"total_savings_amount":170,"is_edited":true},
        {"id":"b4000000-0000-4000-8000-000000000002","period_number":2,"period_month":9,"period_year":2026,"period_months":1,"baseline_amount":500,"opening_amount":600,"final_amount":450,"cost_reduction_amount":50,"cost_avoidance_amount":100,"total_savings_amount":150,"is_edited":false}
      ]'::jsonb
    )
  $$,
  'an administrator can correct values in place after realization evidence exists'
);
select ok(
  (select actual_amount = 400
     and projected_reduction_amount = 70 and projected_avoidance_amount = 100
     and realized_reduction_amount = 100 and realized_avoidance_amount = 0
     and realized_savings = 100 and projected_savings = 170
     and leakage_amount = 0 and realization_status = 'Partially Realized'
     and not finance_validated and finance_validated_by is null
     and finance_validation_date is null and comparison_rebased_at is not null
   from public.realization_periods
   where savings_period_id = 'b4000000-0000-4000-8000-000000000001'),
  'correction preserves entered evidence, recomputes comparators, and supersedes validation'
);
select throws_ok(
  $$
    select public.correct_savings_execution(
      'b3000000-0000-4000-8000-000000000001', 'Attempt to reshape evidenced schedule', '{}'::jsonb,
      '[
        {"id":"b4000000-0000-4000-8000-000000000001","period_number":1,"period_month":10,"period_year":2026,"period_months":1,"baseline_amount":500,"opening_amount":600,"final_amount":430,"cost_reduction_amount":70,"cost_avoidance_amount":100,"total_savings_amount":170},
        {"id":"b4000000-0000-4000-8000-000000000002","period_number":2,"period_month":11,"period_year":2026,"period_months":1,"baseline_amount":500,"opening_amount":600,"final_amount":450,"cost_reduction_amount":50,"cost_avoidance_amount":100,"total_savings_amount":150}
      ]'::jsonb
    )
  $$,
  'P0001', 'schedule identity and dates cannot change after realization evidence exists',
  'schedule identity is frozen once entered realization evidence exists'
);
select ok(
  (select savings_period_id = 'b4000000-0000-4000-8000-000000000001' and actual_amount = 400
   from public.realization_periods
   where savings_period_id = 'b4000000-0000-4000-8000-000000000001'),
  'a rejected shape change never deletes, orphans, or reassigns realization evidence'
);
select throws_ok(
  $$ select public.reverse_savings_execution('b3000000-0000-4000-8000-000000000001', 'Execution was premature', 'clear') $$,
  'P0001', 'execution cannot be reversed after realization evidence exists; use a correction',
  'execution is permanently non-reversible once realization evidence exists'
);
select throws_ok(
  $$ delete from public.savings_periods where id = 'b4000000-0000-4000-8000-000000000001' $$,
  '42501', null,
  'direct schedule deletion is unavailable through the authenticated Data API'
);

select lives_ok(
  $$ select public.mark_savings_schedule_executed('b3000000-0000-4000-8000-000000000002', 'Execute before shell sync') $$,
  'a second admin schedule can be executed for reversal testing'
);
do $$
begin
  perform public.sync_realization_periods('b2000000-0000-4000-8000-000000000002');
end
$$;

select set_config('request.jwt.claim.sub', 'b1000000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$ select public.reverse_savings_execution('b3000000-0000-4000-8000-000000000002', 'Procurement cannot reverse', 'clear') $$,
  'P0001', 'administrator role required',
  'procurement users cannot reverse an execution'
);

select set_config('request.jwt.claim.sub', 'b1000000-0000-4000-8000-000000000001', true);
select lives_ok(
  $$ select public.reverse_savings_execution('b3000000-0000-4000-8000-000000000002', 'Schedule was executed before approval', 'clear') $$,
  'an administrator can reverse a premature execution with only empty shells'
);
select ok(
  (select calculation_status = 'estimated'
      and executed_at is null
      and executed_by is null
      and execution_note is null
      and not legacy_execution_actor_missing
   from public.savings_calculations where id = 'b3000000-0000-4000-8000-000000000002')
  and (select executed_total_savings_amount is null
       from public.savings_periods where id = 'b4000000-0000-4000-8000-000000000003')
  and not exists (
    select 1 from public.realization_periods
    where savings_period_id = 'b4000000-0000-4000-8000-000000000003'
  )
  and (select savings_disposition is null from public.sourcing_events where id = 'b2000000-0000-4000-8000-000000000002'),
  'reversal removes empty shells and returns every coupled surface to an estimated state'
);
select ok(
  exists (
    select 1 from public.audit_log
    where entity_type = 'savings_calculation'
      and entity_id = 'b3000000-0000-4000-8000-000000000002'
      and coalesce(before_data->>'execution_note', after_data->>'execution_note', '') like '%Reversal:%'
  ),
  'the reversal reason survives in the immutable calculation audit history'
);
select throws_ok(
  $$ select public.reverse_savings_execution('b3000000-0000-4000-8000-000000000002', 'Repeat reversal', 'clear') $$,
  'P0001', 'savings schedule is not executed',
  'a second reversal is refused'
);
update public.savings_calculations
set baseline_total_amount = 500,
    opening_proposal_amount = 600,
    award_total_amount = 449,
    cost_reduction_amount = 51,
    cost_avoidance_amount = 100,
    gross_savings_amount = 151,
    net_savings_amount = 151
where id = 'b3000000-0000-4000-8000-000000000002';
select is(
  (select gross_savings_amount from public.savings_calculations where id = 'b3000000-0000-4000-8000-000000000002'),
  151::numeric,
  'ordinary calculation edits remain available while the record is estimated'
);

update public.savings_periods
set final_amount = 449, cost_reduction_amount = 51, total_savings_amount = 151
where id = 'b4000000-0000-4000-8000-000000000003';
select is(
  (select total_savings_amount from public.savings_periods where id = 'b4000000-0000-4000-8000-000000000003'),
  151::numeric,
  'ordinary period edits remain available while the record is estimated'
);

select lives_ok(
  $$ select public.mark_savings_schedule_executed('b3000000-0000-4000-8000-000000000003', 'Execute before project completion') $$,
  'the completed-project reversal fixture can be executed'
);
update public.sourcing_events set event_status = 'Complete'
where id = 'b2000000-0000-4000-8000-000000000003';
select throws_ok(
  $$ select public.reverse_savings_execution('b3000000-0000-4000-8000-000000000003', 'Wrong disposition action', 'clear') $$,
  'P0001', 'reopen the completed project or choose no_executed_savings',
  'a completed project cannot be stranded by a bare reversal'
);
select lives_ok(
  $$ select public.reverse_savings_execution('b3000000-0000-4000-8000-000000000003', 'Execution was recorded before final approval', 'no_executed_savings') $$,
  'an administrator can reverse a completed project with an explicit no-savings disposition'
);
select ok(
  (select savings_disposition = 'no_executed_savings'
     and savings_disposition_reason = 'Execution was recorded before final approval'
   from public.sourcing_events where id = 'b2000000-0000-4000-8000-000000000003'),
  'completed-project reversal atomically repairs the required disposition'
);

select set_config('request.jwt.claim.sub', 'b1000000-0000-4000-8000-000000000002', true);
select lives_ok(
  $$ select public.mark_savings_schedule_executed('b3000000-0000-4000-8000-000000000004', 'Procurement execution') $$,
  'a procurement user can execute a schedule in their workspace'
);
select lives_ok(
  $$
    select public.correct_savings_execution(
      'b3000000-0000-4000-8000-000000000004', 'Procurement correction before realization', '{}'::jsonb,
      '[{"id":"b4000000-0000-4000-8000-000000000005","period_number":1,"period_month":8,"period_year":2026,"period_months":1,"baseline_amount":500,"opening_amount":600,"final_amount":440,"cost_reduction_amount":60,"cost_avoidance_amount":100,"total_savings_amount":160}]'::jsonb
    )
  $$,
  'a procurement user can correct an execution before realization evidence exists'
);

select set_config('request.jwt.claim.sub', 'b1000000-0000-4000-8000-000000000003', true);
select throws_ok(
  $$ select public.mark_savings_schedule_executed('b3000000-0000-4000-8000-000000000004', 'Viewer attempt') $$,
  'P0001', 'administrator or procurement role required',
  'a viewer cannot execute a savings schedule'
);

reset role;

select throws_ok(
  $$ delete from public.savings_periods where id = 'b4000000-0000-4000-8000-000000000001' $$,
  '23503', null,
  'the RESTRICT foreign key prevents privileged schedule deletion from erasing realization evidence'
);
select throws_ok(
  $$ delete from public.sourcing_events where id = 'b2000000-0000-4000-8000-000000000001' $$,
  'P0001', 'project deletion is blocked while savings realization history exists',
  'project deletion cannot cascade away realization history'
);
select throws_ok(
  $$ delete from public.savings_calculations where id = 'b3000000-0000-4000-8000-000000000001' $$,
  'P0001', 'savings calculation deletion is blocked while realization history exists',
  'calculation deletion cannot orphan realization history'
);

select throws_ok(
  $$
    insert into public.savings_calculations (
      id, organization_id, event_id, calculation_name, savings_type,
      calculation_status, executed_at, executed_by
    ) values (
      'b3000000-0000-4000-8000-000000000099',
      (select organization_id from public.profiles where id = 'b1000000-0000-4000-8000-000000000001'),
      null, 'Invalid zero-period execution', 'Cost Reduction', 'executed', now(),
      'b1000000-0000-4000-8000-000000000001'
    );
    set constraints all immediate;
  $$,
  'P0001', 'executed savings require at least one schedule period',
  'the deferred invariant rejects an executed calculation with zero periods'
);

select * from finish();
rollback;
