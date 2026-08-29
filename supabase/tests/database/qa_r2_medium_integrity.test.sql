begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select plan(15);

select has_index(
  'public', 'project_choice_options', 'uq_project_choice_options_org_type_label',
  'the pre-existing index already gives managed labels a case-insensitive workspace identity'
);

select ok(
  exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'public.realization_periods'::regclass
      and conname = 'chk_realization_finance_validation_actor'
      and convalidated
  ),
  'finance validation actor and date are a validated database invariant'
);

select ok(
  (select prosecdef from pg_catalog.pg_proc
   where oid = 'public.enforce_savings_execution_invariant()'::regprocedure)
  and (select prosecdef from pg_catalog.pg_proc
       where oid = 'public.enforce_savings_completion_invariant()'::regprocedure),
  'deferred financial invariants cannot fail open through caller RLS'
);

select ok(
  has_function_privilege('authenticated', 'public.save_estimated_savings_calculation(uuid,jsonb,uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.save_estimated_savings_calculation(uuid,jsonb,uuid)', 'EXECUTE'),
  'the estimated-calculation writer is authenticated only'
);

select ok(
  not has_table_privilege('authenticated', 'public.savings_calculations', 'INSERT')
  and not has_table_privilege('authenticated', 'public.savings_calculations', 'UPDATE')
  and not has_any_column_privilege('authenticated', 'public.savings_calculations', 'INSERT')
  and not has_any_column_privilege('authenticated', 'public.savings_calculations', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.savings_periods', 'UPDATE')
  and not has_any_column_privilege('authenticated', 'public.savings_periods', 'UPDATE'),
  'direct estimated money writes cannot bypass strict JSON validation'
);

select ok(
  (select pg_get_functiondef('public.clone_org_data(uuid,uuid,uuid)'::regprocedure)
    like '%supplier_performance_reviews%')
  and (select pg_get_functiondef('public.clone_org_data(uuid,uuid,uuid)'::regprocedure)
       like '%unclassified organization-scoped table in demo clone%'),
  'demo cloning covers current governance tables and fails on future unclassified tables'
);

select has_trigger(
  'public', 'savings_calculations',
  'savings_calculations_attribute_legacy_correction',
  'legacy execution corrections have an actor-attribution trigger'
);

insert into auth.users (id, email, raw_user_meta_data)
values
  ('f1000000-0000-4000-8000-000000000001', 'medium-admin@example.test', '{"full_name":"Medium Admin"}'),
  ('f1000000-0000-4000-8000-000000000002', 'medium-viewer@example.test', '{"full_name":"Medium Viewer"}');

update public.profiles set role = 'viewer'
where id = 'f1000000-0000-4000-8000-000000000002';

insert into public.project_choice_options (
  organization_id, choice_type, project_type, label, active_flag
)
select organization_id, 'event_status', 'Sourcing', 'Closable', true
from public.profiles where id = 'f1000000-0000-4000-8000-000000000001';

select throws_like(
  $$ insert into public.project_choice_options (
       organization_id, choice_type, project_type, label, active_flag
     ) select organization_id, 'event_status', 'Sourcing', ' cLoSaBlE ', true
       from public.profiles where id = 'f1000000-0000-4000-8000-000000000001' $$,
  '23505', '%uq_project_choice_options_org_type_label%',
  'a look-alike label cannot detach terminal metadata'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f1000000-0000-4000-8000-000000000001', true);

select throws_ok(
  $$ select public.save_estimated_savings_calculation(
       gen_random_uuid(),
       '{"award_total_amount":99.999,"gross_savings_amount":0,"cost_avoidance_amount":0,"net_savings_amount":0,"savings_percentage":null,"savings_type":"Cost Reduction"}'::jsonb,
       null
     ) $$,
  '22003', 'award_total_amount must have no more than two decimal places',
  'the calculation RPC rejects rather than rounds sub-cent money'
);

select throws_ok(
  $$ select public.replace_savings_schedule(
       gen_random_uuid(), 1, 2026, 'monthly',
       '[{"period_number":1,"period_month":1,"period_year":2026,"period_months":1,"baseline_amount":100,"opening_amount":100,"final_amount":90.001,"cost_reduction_amount":10,"cost_avoidance_amount":0,"total_savings_amount":10,"is_edited":false}]'::jsonb
     ) $$,
  '22003', 'final_amount must have no more than two decimal places',
  'the schedule RPC rejects rather than rounds sub-cent money'
);

select lives_ok(
  $$ insert into public.project_choice_options (
       organization_id, choice_type, project_type, label, active_flag,
       created_by, updated_by
     ) select organization_id, 'event_type', 'Sourcing', 'Stamped type', true,
              'f1000000-0000-4000-8000-000000000002',
              'f1000000-0000-4000-8000-000000000002'
       from public.profiles where id = 'f1000000-0000-4000-8000-000000000001' $$,
  'an administrator can create a managed option'
);

select ok(
  (select created_by = auth.uid() and updated_by = auth.uid()
   from public.project_choice_options
   where label = 'Stamped type'
     and organization_id = (select organization_id from public.profiles where id = auth.uid())),
  'managed-option actors are stamped instead of trusted from the payload'
);

reset role;

insert into public.project_choice_options (
  organization_id, choice_type, project_type, label, active_flag
)
select profile.organization_id, seed.choice_type, 'Sourcing', seed.label, true
from public.profiles profile
cross join (values ('event_type', 'Contract Renewal'), ('event_status', 'Pipeline')) seed(choice_type, label)
where profile.id = 'f1000000-0000-4000-8000-000000000002'
on conflict do nothing;

insert into public.sourcing_events (
  id, organization_id, event_name, event_type, event_status, project_type
)
select 'f2000000-0000-4000-8000-000000000002', organization_id,
       'Viewer project', 'Contract Renewal', 'Pipeline', 'Sourcing'
from public.profiles where id = 'f1000000-0000-4000-8000-000000000002';

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f1000000-0000-4000-8000-000000000002', true);

select throws_ok(
  $$ insert into public.project_updates (
       organization_id, event_id, body, created_by
     ) select organization_id, 'f2000000-0000-4000-8000-000000000002',
              'viewer should not post', auth.uid()
       from public.profiles where id = auth.uid() $$,
  '42501', 'new row violates row-level security policy for table "project_updates"',
  'a viewer cannot post project timeline entries'
);

select throws_ok(
  $$ select public.save_estimated_savings_calculation(
       'f2000000-0000-4000-8000-000000000002',
       '{"baseline_id":null,"calculation_name":"Viewer calc","savings_type":"Cost Reduction","baseline_total_amount":100,"opening_proposal_amount":100,"award_total_amount":90,"gross_savings_amount":10,"cost_reduction_amount":10,"cost_avoidance_amount":0,"savings_percentage":10,"net_savings_amount":10,"recognition_notes":"test"}'::jsonb,
       null
     ) $$,
  'P0001', 'administrator or procurement role required',
  'a viewer cannot use the estimated-calculation writer'
);

reset role;

select ok(
  (select count(*) = 6
   from pg_catalog.pg_trigger trigger_row
   where trigger_row.tgname = any(array[
     'project_choice_options_actor', 'supplier_contacts_stamp_actor',
     'supplier_certifications_stamp_actor', 'supplier_performance_reviews_stamp_actor',
     'supplier_risks_stamp_actor', 'supplier_notes_stamp_actor'
   ]) and not trigger_row.tgisinternal),
  'the one unstamped option table joins the five already-stamped governance tables'
);

select * from finish();
rollback;
