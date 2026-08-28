begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select plan(26);

insert into auth.users (id, email, raw_user_meta_data)
values
  ('b1000000-0000-4000-8000-000000000001', 'money-admin@example.test', '{"full_name":"Money Admin"}'),
  ('b1000000-0000-4000-8000-000000000002', 'money-procurement@example.test', '{"full_name":"Money Procurement"}'),
  ('b1000000-0000-4000-8000-000000000003', 'money-viewer@example.test', '{"full_name":"Money Viewer"}');

update public.profiles set role = 'procurement_user'
where id = 'b1000000-0000-4000-8000-000000000002';
update public.profiles set role = 'viewer'
where id = 'b1000000-0000-4000-8000-000000000003';

insert into public.organization_settings (organization_id, savings_realization_enabled)
select organization_id, true
from public.profiles
where id in (
    'b1000000-0000-4000-8000-000000000001',
    'b1000000-0000-4000-8000-000000000002',
    'b1000000-0000-4000-8000-000000000003'
)
on conflict (organization_id) do update
set savings_realization_enabled = excluded.savings_realization_enabled;

insert into public.sourcing_events (
  id, organization_id, event_name, event_type, event_status, project_type
)
select
  event_id,
  profile.organization_id,
  event_name,
  'Contract Renewal',
  'Pipeline',
  'Sourcing'
from (
  values
    ('b2000000-0000-4000-8000-000000000001'::uuid, 'b1000000-0000-4000-8000-000000000001'::uuid, 'Admin money project'),
    ('b2000000-0000-4000-8000-000000000002'::uuid, 'b1000000-0000-4000-8000-000000000002'::uuid, 'Procurement money project'),
    ('b2000000-0000-4000-8000-000000000003'::uuid, 'b1000000-0000-4000-8000-000000000003'::uuid, 'Viewer money project')
) seed(event_id, profile_id, event_name)
join public.profiles profile on profile.id = seed.profile_id;

insert into public.baselines (
  id, organization_id, event_id, baseline_name, baseline_type,
  baseline_total_amount
)
select
  baseline_id, profile.organization_id, event_id, baseline_name,
  'Prior Year Actuals', 1000
from (
  values
    ('b3000000-0000-4000-8000-000000000001'::uuid, 'b1000000-0000-4000-8000-000000000001'::uuid, 'b2000000-0000-4000-8000-000000000001'::uuid, 'Admin baseline'),
    ('b3000000-0000-4000-8000-000000000002'::uuid, 'b1000000-0000-4000-8000-000000000002'::uuid, 'b2000000-0000-4000-8000-000000000002'::uuid, 'Procurement baseline'),
    ('b3000000-0000-4000-8000-000000000003'::uuid, 'b1000000-0000-4000-8000-000000000003'::uuid, 'b2000000-0000-4000-8000-000000000003'::uuid, 'Viewer baseline')
) seed(baseline_id, profile_id, event_id, baseline_name)
join public.profiles profile on profile.id = seed.profile_id;

insert into public.event_scope_lines (
  id, organization_id, event_id, line_number, item_service_name
)
select
  line_id, profile.organization_id, event_id, 1, line_name
from (
  values
    ('b4000000-0000-4000-8000-000000000001'::uuid, 'b1000000-0000-4000-8000-000000000001'::uuid, 'b2000000-0000-4000-8000-000000000001'::uuid, 'Admin scope line'),
    ('b4000000-0000-4000-8000-000000000002'::uuid, 'b1000000-0000-4000-8000-000000000002'::uuid, 'b2000000-0000-4000-8000-000000000002'::uuid, 'Procurement scope line'),
    ('b4000000-0000-4000-8000-000000000003'::uuid, 'b1000000-0000-4000-8000-000000000003'::uuid, 'b2000000-0000-4000-8000-000000000003'::uuid, 'Viewer scope line')
) seed(line_id, profile_id, event_id, line_name)
join public.profiles profile on profile.id = seed.profile_id;

insert into public.realization_periods (
  id, organization_id, event_id, period_name, period_start_date,
  period_end_date, finance_validated
)
select
  period_id, profile.organization_id, event_id, 'Aug 2026',
  '2026-08-01', '2026-08-31', false
from (
  values
    ('b5000000-0000-4000-8000-000000000001'::uuid, 'b1000000-0000-4000-8000-000000000001'::uuid, 'b2000000-0000-4000-8000-000000000001'::uuid),
    ('b5000000-0000-4000-8000-000000000002'::uuid, 'b1000000-0000-4000-8000-000000000002'::uuid, 'b2000000-0000-4000-8000-000000000002'::uuid),
    ('b5000000-0000-4000-8000-000000000003'::uuid, 'b1000000-0000-4000-8000-000000000003'::uuid, 'b2000000-0000-4000-8000-000000000003'::uuid)
) seed(period_id, profile_id, event_id)
join public.profiles profile on profile.id = seed.profile_id;

select ok(
  (select count(*) = 10
   from information_schema.columns
   where table_schema = 'public'
     and table_name in (
       'event_scope_lines', 'baseline_lines', 'supplier_offer_lines',
       'award_lines', 'savings_calculation_lines'
     )
     and column_name in ('created_by', 'updated_by')),
  'all five legacy detail tables now expose both actor columns'
);

select ok(
  not (select prosecdef from pg_catalog.pg_proc
       where oid = 'public.stamp_money_record_actor()'::regprocedure)
  and (select array_to_string(proconfig, ',') like '%search_path=pg_catalog, public%'
       from pg_catalog.pg_proc
       where oid = 'public.stamp_money_record_actor()'::regprocedure),
  'the actor trigger uses invoker rights and a fixed search path'
);

select ok(
  not has_function_privilege('anon', 'public.stamp_money_record_actor()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.stamp_money_record_actor()', 'EXECUTE')
  and has_function_privilege('service_role', 'public.stamp_money_record_actor()', 'EXECUTE'),
  'only the trigger-owner path can invoke actor stamping'
);

select ok(
  has_function_privilege('authenticated', 'public.set_hard_reduction_override(uuid,boolean,text)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.confirm_business_equivalency(uuid,boolean)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.set_finance_validation(uuid,boolean)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.set_hard_reduction_override(uuid,boolean,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.confirm_business_equivalency(uuid,boolean)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.set_finance_validation(uuid,boolean)', 'EXECUTE'),
  'the protected decision RPCs are authenticated-only'
);

select ok(
  (select bool_and(prosecdef and array_to_string(proconfig, ',') like '%search_path=pg_catalog, public%')
   from pg_catalog.pg_proc
   where oid in (
     'public.set_hard_reduction_override(uuid,boolean,text)'::regprocedure,
     'public.confirm_business_equivalency(uuid,boolean)'::regprocedure,
     'public.set_finance_validation(uuid,boolean)'::regprocedure
   )),
  'all protected decision RPCs use definer rights with a fixed search path'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b1000000-0000-4000-8000-000000000001', true);

select lives_ok(
  $$ select public.set_hard_reduction_override('b3000000-0000-4000-8000-000000000001', true, 'Documented commercial exception') $$,
  'an administrator can enable a hard-reduction override'
);
select ok(
  (select hard_reduction_override
       and hard_reduction_override_reason = 'Documented commercial exception'
       and hard_reduction_override_by = 'b1000000-0000-4000-8000-000000000001'
       and hard_reduction_override_at is not null
   from public.baselines where id = 'b3000000-0000-4000-8000-000000000001'),
  'hard-reduction actor and timestamp are server stamped'
);
select throws_ok(
  $$ select public.set_hard_reduction_override('b3000000-0000-4000-8000-000000000001', true, 'too short') $$,
  'P0001', 'override reason must contain at least 10 characters',
  'short override reasons are rejected'
);
select throws_ok(
  $$ update public.baselines set hard_reduction_override_by = 'b1000000-0000-4000-8000-000000000003' where id = 'b3000000-0000-4000-8000-000000000001' $$,
  '42501', null,
  'direct hard-reduction actor forgery is denied'
);
select lives_ok(
  $$ select public.set_hard_reduction_override('b3000000-0000-4000-8000-000000000001', false, null) $$,
  'an administrator can clear a hard-reduction override'
);
select ok(
  (select not hard_reduction_override
       and hard_reduction_override_reason is null
       and hard_reduction_override_by is null
       and hard_reduction_override_at is null
   from public.baselines where id = 'b3000000-0000-4000-8000-000000000001'),
  'clearing an override clears the whole decision tuple'
);

select lives_ok(
  $$ select public.confirm_business_equivalency('b4000000-0000-4000-8000-000000000001', true) $$,
  'an administrator can confirm business equivalency'
);
select ok(
  (select business_equivalency_confirmed
       and business_equivalency_confirmed_by = 'b1000000-0000-4000-8000-000000000001'
   from public.event_scope_lines where id = 'b4000000-0000-4000-8000-000000000001'),
  'business-equivalency actor is server stamped'
);
select throws_ok(
  $$ update public.event_scope_lines set business_equivalency_confirmed = false where id = 'b4000000-0000-4000-8000-000000000001' $$,
  '42501', null,
  'direct business-equivalency writes are denied'
);
select throws_ok(
  $$ insert into public.event_scope_lines (organization_id, event_id, line_number, item_service_name, created_by) values ((select organization_id from public.profiles where id = 'b1000000-0000-4000-8000-000000000001'), 'b2000000-0000-4000-8000-000000000001', 2, 'Forged actor line', 'b1000000-0000-4000-8000-000000000003') $$,
  '42501', null,
  'direct line-actor forgery is denied'
);
select lives_ok(
  $$ insert into public.event_scope_lines (id, organization_id, event_id, line_number, item_service_name) values ('b4000000-0000-4000-8000-000000000004', (select organization_id from public.profiles where id = 'b1000000-0000-4000-8000-000000000001'), 'b2000000-0000-4000-8000-000000000001', 2, 'Stamped actor line') $$,
  'an ordinary scope-line insert remains available'
);
select ok(
  (select created_by = 'b1000000-0000-4000-8000-000000000001'
       and updated_by = 'b1000000-0000-4000-8000-000000000001'
   from public.event_scope_lines where id = 'b4000000-0000-4000-8000-000000000004'),
  'ordinary money-line writes stamp the authenticated actor'
);

select lives_ok(
  $$ select public.set_finance_validation('b5000000-0000-4000-8000-000000000001', true) $$,
  'an administrator can validate a realization period'
);
select ok(
  (select finance_validated
       and finance_validated_by = 'b1000000-0000-4000-8000-000000000001'
       and finance_validation_date is not null
   from public.realization_periods where id = 'b5000000-0000-4000-8000-000000000001'),
  'finance validation actor and timestamp are server stamped'
);
select throws_ok(
  $$ update public.realization_periods set finance_validated = false where id = 'b5000000-0000-4000-8000-000000000001' $$,
  '42501', null,
  'direct finance-validation writes are denied'
);

select set_config('request.jwt.claim.sub', 'b1000000-0000-4000-8000-000000000002', true);
select lives_ok(
  $$ select public.set_hard_reduction_override('b3000000-0000-4000-8000-000000000002', true, 'Procurement documented exception') $$,
  'procurement can make a commercial classification decision'
);
select throws_ok(
  $$ select public.set_finance_validation('b5000000-0000-4000-8000-000000000002', true) $$,
  'P0001', 'administrator role required',
  'procurement cannot make a finance attestation'
);

select set_config('request.jwt.claim.sub', 'b1000000-0000-4000-8000-000000000003', true);
select throws_ok(
  $$ select public.set_hard_reduction_override('b3000000-0000-4000-8000-000000000003', true, 'Viewer attempted exception') $$,
  'P0001', 'administrator or procurement role required',
  'a viewer cannot enable a hard-reduction override'
);
select throws_ok(
  $$ select public.confirm_business_equivalency('b4000000-0000-4000-8000-000000000003', true) $$,
  'P0001', 'administrator or procurement role required',
  'a viewer cannot confirm business equivalency'
);
select throws_ok(
  $$ select public.set_finance_validation('b5000000-0000-4000-8000-000000000003', true) $$,
  'P0001', 'administrator role required',
  'a viewer cannot make a finance attestation'
);

select set_config('request.jwt.claim.sub', 'b1000000-0000-4000-8000-000000000001', true);
select throws_ok(
  $$ select public.set_hard_reduction_override('b3000000-0000-4000-8000-000000000002', true, 'Cross workspace exception') $$,
  'P0001', 'baseline not found',
  'a cross-workspace protected decision is rejected'
);

reset role;
select * from finish();
rollback;
