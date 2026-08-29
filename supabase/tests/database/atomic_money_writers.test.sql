begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select plan(36);

insert into auth.users (id, email, raw_user_meta_data)
values
  ('a1000000-0000-4000-8000-000000000001', 'atomic-admin@example.test', '{"full_name":"Atomic Admin"}'),
  ('a1000000-0000-4000-8000-000000000002', 'atomic-viewer@example.test', '{"full_name":"Atomic Viewer"}');

update public.profiles set role = 'viewer'
where id = 'a1000000-0000-4000-8000-000000000002';

insert into public.sourcing_events (
  id, organization_id, event_name, event_type, event_status, project_type
)
values
  (
    'a2000000-0000-4000-8000-000000000001',
    (select organization_id from public.profiles where id = 'a1000000-0000-4000-8000-000000000001'),
    'Atomic admin project', 'Contract Renewal', 'Pipeline', 'Sourcing'
  ),
  (
    'a2000000-0000-4000-8000-000000000002',
    (select organization_id from public.profiles where id = 'a1000000-0000-4000-8000-000000000002'),
    'Atomic viewer project', 'Contract Renewal', 'Pipeline', 'Sourcing'
  ),
  (
    'a2000000-0000-4000-8000-000000000003',
    (select organization_id from public.profiles where id = 'a1000000-0000-4000-8000-000000000001'),
    'Atomic soft-baseline project', 'Contract Renewal', 'Pipeline', 'Sourcing'
  );

insert into public.suppliers (id, organization_id, supplier_name, supplier_normalized_name)
values
  ('a4000000-0000-4000-8000-000000000001', (select organization_id from public.profiles where id = 'a1000000-0000-4000-8000-000000000001'), 'Atomic Supplier One', 'atomic supplier one'),
  ('a4000000-0000-4000-8000-000000000002', (select organization_id from public.profiles where id = 'a1000000-0000-4000-8000-000000000001'), 'Atomic Supplier Two', 'atomic supplier two'),
  ('a4000000-0000-4000-8000-000000000003', (select organization_id from public.profiles where id = 'a1000000-0000-4000-8000-000000000002'), 'Viewer Supplier', 'viewer supplier');

insert into public.baselines (
  id, organization_id, event_id, baseline_name, baseline_type,
  baseline_total_amount, is_selected
)
values
  ('a3000000-0000-4000-8000-000000000001', (select organization_id from public.profiles where id = 'a1000000-0000-4000-8000-000000000001'), 'a2000000-0000-4000-8000-000000000001', 'Old baseline', 'Current Contract', 1000, true),
  ('a3000000-0000-4000-8000-000000000002', (select organization_id from public.profiles where id = 'a1000000-0000-4000-8000-000000000001'), 'a2000000-0000-4000-8000-000000000001', 'New baseline', 'Current Contract', 1200, false),
  ('a3000000-0000-4000-8000-000000000003', (select organization_id from public.profiles where id = 'a1000000-0000-4000-8000-000000000002'), 'a2000000-0000-4000-8000-000000000002', 'Viewer baseline', 'Current Contract', 800, true),
  ('a3000000-0000-4000-8000-000000000004', (select organization_id from public.profiles where id = 'a1000000-0000-4000-8000-000000000001'), 'a2000000-0000-4000-8000-000000000003', 'Approved budget', 'Approved Budget', 1000, true);

insert into public.supplier_offers (
  id, organization_id, event_id, supplier_id, offer_type,
  offer_total_amount, offer_role
)
values
  ('a5000000-0000-4000-8000-000000000001', (select organization_id from public.profiles where id = 'a1000000-0000-4000-8000-000000000001'), 'a2000000-0000-4000-8000-000000000001', 'a4000000-0000-4000-8000-000000000001', 'Initial', 1100, null),
  ('a5000000-0000-4000-8000-000000000002', (select organization_id from public.profiles where id = 'a1000000-0000-4000-8000-000000000001'), 'a2000000-0000-4000-8000-000000000001', 'a4000000-0000-4000-8000-000000000002', 'Final', 900, null),
  ('a5000000-0000-4000-8000-000000000003', (select organization_id from public.profiles where id = 'a1000000-0000-4000-8000-000000000002'), 'a2000000-0000-4000-8000-000000000002', 'a4000000-0000-4000-8000-000000000003', 'Final', 700, null);

insert into public.savings_calculations (
  id, organization_id, event_id, calculation_name, savings_type,
  calculation_status, baseline_total_amount, opening_proposal_amount,
  award_total_amount, cost_reduction_amount, cost_avoidance_amount,
  gross_savings_amount, net_savings_amount
)
values
  ('a6000000-0000-4000-8000-000000000001', (select organization_id from public.profiles where id = 'a1000000-0000-4000-8000-000000000001'), 'a2000000-0000-4000-8000-000000000001', 'Prior schedule', 'Cost Reduction', 'estimated', 100, 125, 100, 0, 25, 25, 25),
  ('a6000000-0000-4000-8000-000000000002', (select organization_id from public.profiles where id = 'a1000000-0000-4000-8000-000000000002'), 'a2000000-0000-4000-8000-000000000002', 'Viewer schedule', 'Cost Reduction', 'estimated', 100, 110, 100, 0, 10, 10, 10),
  ('a6000000-0000-4000-8000-000000000003', (select organization_id from public.profiles where id = 'a1000000-0000-4000-8000-000000000001'), 'a2000000-0000-4000-8000-000000000003', 'Soft schedule', 'Cost Avoidance', 'estimated', null, 1000, 900, null, 100, 100, 100);

insert into public.savings_periods (
  id, organization_id, event_id, savings_calculation_id,
  period_number, period_month, period_year, period_months,
  baseline_amount, opening_amount, final_amount,
  cost_reduction_amount, cost_avoidance_amount, total_savings_amount
)
values
  ('a7000000-0000-4000-8000-000000000001', (select organization_id from public.profiles where id = 'a1000000-0000-4000-8000-000000000001'), 'a2000000-0000-4000-8000-000000000001', 'a6000000-0000-4000-8000-000000000001', 1, 7, 2026, 1, 100, 125, 100, 0, 25, 25),
  ('a7000000-0000-4000-8000-000000000002', (select organization_id from public.profiles where id = 'a1000000-0000-4000-8000-000000000002'), 'a2000000-0000-4000-8000-000000000002', 'a6000000-0000-4000-8000-000000000002', 1, 7, 2026, 1, 100, 110, 100, 0, 10, 10);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000001', true);

select lives_ok(
  $$ select public.select_baseline('a3000000-0000-4000-8000-000000000002') $$,
  'an administrator can atomically select a baseline'
);
select ok(
  (select is_selected from public.baselines where id = 'a3000000-0000-4000-8000-000000000002')
  and not (select is_selected from public.baselines where id = 'a3000000-0000-4000-8000-000000000001'),
  'selecting a baseline clears the prior selection and sets the target together'
);
select lives_ok(
  $$ select public.select_baseline('a3000000-0000-4000-8000-000000000002') $$,
  'selecting the same baseline twice is idempotent'
);
select is(
  (select count(*)::bigint from public.baselines where event_id = 'a2000000-0000-4000-8000-000000000001' and is_selected),
  1::bigint,
  'idempotent baseline selection preserves exactly one selection'
);
select throws_ok(
  $$ select public.select_baseline('a3000000-0000-4000-8000-000000000003') $$,
  'P0001', 'baseline not found',
  'a cross-workspace baseline ID is rejected'
);

select lives_ok(
  $$ select public.set_offer_role('a5000000-0000-4000-8000-000000000001', 'final') $$,
  'an administrator can atomically mark a final offer'
);
select ok(
  (select offer_role = 'final' from public.supplier_offers where id = 'a5000000-0000-4000-8000-000000000001')
  and (select awarded_supplier_id = 'a4000000-0000-4000-8000-000000000001' from public.sourcing_events where id = 'a2000000-0000-4000-8000-000000000001'),
  'the final role and awarded-supplier pointer agree'
);
select lives_ok(
  $$ select public.set_offer_role('a5000000-0000-4000-8000-000000000002', 'final') $$,
  'a new final offer atomically replaces the prior final'
);
select ok(
  (select offer_role is null from public.supplier_offers where id = 'a5000000-0000-4000-8000-000000000001')
  and (select offer_role = 'final' from public.supplier_offers where id = 'a5000000-0000-4000-8000-000000000002')
  and (select awarded_supplier_id = 'a4000000-0000-4000-8000-000000000002' from public.sourcing_events where id = 'a2000000-0000-4000-8000-000000000001'),
  'offer replacement and winner resolution use the locked database rows'
);
select lives_ok(
  $$ select public.set_offer_role('a5000000-0000-4000-8000-000000000002', null) $$,
  'the final role can be explicitly unset'
);
select ok(
  (select awarded_supplier_id is null from public.sourcing_events where id = 'a2000000-0000-4000-8000-000000000001')
  and not exists (select 1 from public.supplier_offers where event_id = 'a2000000-0000-4000-8000-000000000001' and offer_role = 'final'),
  'unsetting Final also clears the awarded-supplier pointer'
);
select lives_ok(
  $$ select public.set_offer_role('a5000000-0000-4000-8000-000000000002', null) $$,
  'unsetting an already-unset role is idempotent'
);
select throws_ok(
  $$ select public.set_offer_role('a5000000-0000-4000-8000-000000000003', 'final') $$,
  'P0001', 'offer not found',
  'a cross-workspace offer ID is rejected'
);
select throws_ok(
  $$ select public.set_offer_role('a5000000-0000-4000-8000-000000000001', 'winner') $$,
  'P0001', 'offer role must be opening, final, or null',
  'unsupported offer roles are rejected'
);

select lives_ok(
  $$
    select public.replace_savings_schedule(
      'a6000000-0000-4000-8000-000000000001', 8, 2026, 'monthly',
      '[
        {"period_number":1,"period_month":8,"period_year":2026,"period_months":1,"baseline_amount":500,"opening_amount":600,"final_amount":450,"cost_reduction_amount":50,"cost_avoidance_amount":100,"total_savings_amount":150,"is_edited":false},
        {"period_number":2,"period_month":9,"period_year":2026,"period_months":1,"baseline_amount":500,"opening_amount":600,"final_amount":450,"cost_reduction_amount":50,"cost_avoidance_amount":100,"total_savings_amount":150,"is_edited":false}
      ]'::jsonb
    )
  $$,
  'an administrator can atomically replace and publish a schedule'
);
select ok(
  (select count(*) = 2 and sum(total_savings_amount) = 300 from public.savings_periods where savings_calculation_id = 'a6000000-0000-4000-8000-000000000001')
  and (select gross_savings_amount = 300 and baseline_total_amount = 1000 and savings_percentage = 30 and schedule_period_count = 2 from public.savings_calculations where id = 'a6000000-0000-4000-8000-000000000001'),
  'schedule rows and published totals change together'
);
select ok(
  not exists (
    select 1 from public.savings_periods
    where savings_calculation_id = 'a6000000-0000-4000-8000-000000000001'
      and (created_by <> 'a1000000-0000-4000-8000-000000000001' or updated_by <> 'a1000000-0000-4000-8000-000000000001')
  ),
  'schedule rows stamp the authenticated actor instead of trusting payload identity'
);
select lives_ok(
  $$
    select public.replace_savings_schedule(
      'a6000000-0000-4000-8000-000000000001', 8, 2026, 'monthly',
      '[
        {"period_number":1,"period_month":8,"period_year":2026,"period_months":1,"baseline_amount":500,"opening_amount":600,"final_amount":450,"cost_reduction_amount":50,"cost_avoidance_amount":100,"total_savings_amount":150,"is_edited":false},
        {"period_number":2,"period_month":9,"period_year":2026,"period_months":1,"baseline_amount":500,"opening_amount":600,"final_amount":450,"cost_reduction_amount":50,"cost_avoidance_amount":100,"total_savings_amount":150,"is_edited":false}
      ]'::jsonb
    )
  $$,
  'replacing a schedule with the same values is idempotent'
);
select is(
  (select count(*)::bigint from public.savings_periods where savings_calculation_id = 'a6000000-0000-4000-8000-000000000001'),
  2::bigint,
  'idempotent schedule replacement does not duplicate periods'
);
select throws_ok(
  $$
    select public.replace_savings_schedule(
      'a6000000-0000-4000-8000-000000000001', 8, 2026, 'monthly',
      '[
        {"period_number":1,"period_month":8,"period_year":2026,"period_months":1,"baseline_amount":500,"opening_amount":600,"final_amount":450,"cost_reduction_amount":50,"cost_avoidance_amount":100,"total_savings_amount":150,"is_edited":true},
        {"period_number":2,"period_month":9,"period_year":2026,"period_months":1,"baseline_amount":null,"opening_amount":600,"final_amount":450,"cost_reduction_amount":null,"cost_avoidance_amount":150,"total_savings_amount":150,"is_edited":true}
      ]'::jsonb
    )
  $$,
  '23514',
  'A schedule cannot mix captured and missing baseline amounts. Capture every period or clear every period.',
  'mixed baseline capture is rejected before the aggregate constraint can leak'
);
select ok(
  (select count(*) = 2 and sum(total_savings_amount) = 300
   from public.savings_periods
   where savings_calculation_id = 'a6000000-0000-4000-8000-000000000001'),
  'a rejected mixed-baseline edit preserves the prior schedule'
);
select throws_ok(
  $$
    select public.replace_savings_schedule(
      'a6000000-0000-4000-8000-000000000003', 8, 2026, 'monthly',
      '[{"period_number":1,"period_month":8,"period_year":2026,"period_months":1,"baseline_amount":1000,"opening_amount":1000,"final_amount":900,"cost_reduction_amount":100,"cost_avoidance_amount":0,"total_savings_amount":100,"is_edited":false}]'::jsonb
    )
  $$,
  '23514',
  'Soft baselines cannot book hard cost reduction. Use cost avoidance or approve a documented hard-baseline override.',
  'a direct RPC cannot book hard reduction against a soft baseline'
);
select lives_ok(
  $$
    select public.replace_savings_schedule(
      'a6000000-0000-4000-8000-000000000003', 8, 2026, 'monthly',
      '[{"period_number":1,"period_month":8,"period_year":2026,"period_months":1,"baseline_amount":null,"opening_amount":1000,"final_amount":900,"cost_reduction_amount":null,"cost_avoidance_amount":100,"total_savings_amount":100,"is_edited":false}]'::jsonb
    )
  $$,
  'a soft baseline can publish a pure cost-avoidance schedule'
);
select throws_ok(
  $$
    select public.save_estimated_savings_calculation(
      'a2000000-0000-4000-8000-000000000003',
      '{"baseline_id":"a3000000-0000-4000-8000-000000000004","calculation_name":"Forged hard savings","savings_type":"Cost Reduction","baseline_total_amount":1000,"opening_proposal_amount":1000,"award_total_amount":900,"gross_savings_amount":100,"cost_reduction_amount":100,"cost_avoidance_amount":0,"savings_percentage":10,"net_savings_amount":100}'::jsonb,
      'a6000000-0000-4000-8000-000000000003'
    )
  $$,
  '23514',
  'Soft baselines cannot book hard cost reduction. Use cost avoidance or approve a documented hard-baseline override.',
  'the estimated-calculation RPC also rejects forged hard savings against a soft baseline'
);
select throws_ok(
  $$
    select public.replace_savings_schedule(
      'a6000000-0000-4000-8000-000000000001', 10, 2026, 'monthly',
      '[
        {"period_number":1,"period_month":10,"period_year":2026,"period_months":1,"baseline_amount":999,"opening_amount":999,"final_amount":1,"cost_reduction_amount":998,"cost_avoidance_amount":0,"total_savings_amount":998,"is_edited":false},
        {"period_number":1,"period_month":11,"period_year":2026,"period_months":1,"baseline_amount":999,"opening_amount":999,"final_amount":1,"cost_reduction_amount":998,"cost_avoidance_amount":0,"total_savings_amount":998,"is_edited":false}
      ]'::jsonb
    )
  $$,
  '23505', null,
  'a forced mid-replacement constraint failure aborts the RPC'
);
select ok(
  (select count(*) = 2 and sum(total_savings_amount) = 300 from public.savings_periods where savings_calculation_id = 'a6000000-0000-4000-8000-000000000001')
  and (select gross_savings_amount = 300 and schedule_start_month = 8 from public.savings_calculations where id = 'a6000000-0000-4000-8000-000000000001'),
  'a failed replacement restores both the prior rows and published header'
);
select throws_ok(
  $$ select public.replace_savings_schedule('a6000000-0000-4000-8000-000000000002', 8, 2026, 'monthly', '[{"period_number":1}]'::jsonb) $$,
  'P0001', 'savings calculation not found',
  'a cross-workspace calculation ID is rejected'
);

select throws_ok(
  $$ update public.baselines set is_selected = false where id = 'a3000000-0000-4000-8000-000000000002' $$,
  '42501', null,
  'direct baseline-selection writes are denied'
);
select throws_ok(
  $$ update public.supplier_offers set offer_role = 'final' where id = 'a5000000-0000-4000-8000-000000000001' $$,
  '42501', null,
  'direct offer-role writes are denied'
);
select throws_ok(
  $$ update public.sourcing_events set awarded_supplier_id = 'a4000000-0000-4000-8000-000000000001' where id = 'a2000000-0000-4000-8000-000000000001' $$,
  '42501', null,
  'direct award-pointer writes are denied'
);
select throws_ok(
  $$ insert into public.savings_periods (organization_id, event_id, savings_calculation_id, period_number, period_month, period_year) values ((select organization_id from public.profiles where id = 'a1000000-0000-4000-8000-000000000001'), 'a2000000-0000-4000-8000-000000000001', 'a6000000-0000-4000-8000-000000000001', 3, 10, 2026) $$,
  '42501', null,
  'direct schedule-period inserts are denied'
);
select throws_ok(
  $$ delete from public.savings_periods where savings_calculation_id = 'a6000000-0000-4000-8000-000000000001' $$,
  '42501', null,
  'direct schedule-period deletes are denied'
);
select throws_ok(
  $$ update public.savings_periods set executed_final_amount = final_amount where savings_calculation_id = 'a6000000-0000-4000-8000-000000000001' $$,
  '42501', null,
  'direct executed-snapshot edits are denied'
);

select set_config('request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$ select public.select_baseline('a3000000-0000-4000-8000-000000000003') $$,
  'P0001', 'administrator or procurement role required',
  'a viewer cannot select a baseline in their own workspace'
);
select throws_ok(
  $$ select public.set_offer_role('a5000000-0000-4000-8000-000000000003', 'final') $$,
  'P0001', 'administrator or procurement role required',
  'a viewer cannot set an offer role in their own workspace'
);
select throws_ok(
  $$ select public.replace_savings_schedule('a6000000-0000-4000-8000-000000000002', 8, 2026, 'monthly', '[{"period_number":1}]'::jsonb) $$,
  'P0001', 'administrator or procurement role required',
  'a viewer cannot replace a schedule in their own workspace'
);

reset role;
select * from finish();
rollback;
