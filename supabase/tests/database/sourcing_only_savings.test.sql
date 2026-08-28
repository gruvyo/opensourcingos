begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select plan(18);

select ok(
  not (select prosecdef from pg_catalog.pg_proc
       where oid = 'public.enforce_sourcing_project_savings()'::regprocedure)
  and (select array_to_string(proconfig, ',') like '%search_path=pg_catalog, public%'
       from pg_catalog.pg_proc
       where oid = 'public.enforce_sourcing_project_savings()'::regprocedure),
  'the Sourcing-only trigger is an invoker function with a fixed search path'
);

select ok(
  not has_function_privilege('anon', 'public.enforce_sourcing_project_savings()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.enforce_sourcing_project_savings()', 'EXECUTE')
  and has_function_privilege('service_role', 'public.enforce_sourcing_project_savings()', 'EXECUTE'),
  'only the trigger-owner path can invoke the Sourcing-only guard'
);

select is(
  (select count(*)::integer
   from pg_catalog.pg_trigger trigger
   join pg_catalog.pg_class relation on relation.oid = trigger.tgrelid
   join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
   where namespace.nspname = 'public'
     and relation.relname in (
       'sourcing_events', 'savings_calculations', 'savings_calculation_lines',
       'savings_periods', 'realization_periods'
     )
     and trigger.tgfoid = 'public.enforce_sourcing_project_savings()'::regprocedure
     and not trigger.tgisinternal),
  5,
  'every project-savings boundary uses the shared database guard'
);

insert into auth.users (id, email, raw_user_meta_data)
values (
  'd1000000-0000-4000-8000-000000000001',
  'sourcing-only-admin@example.test',
  '{"full_name":"Sourcing Only Admin"}'
);

insert into public.organization_settings (
  organization_id, support_projects_enabled, savings_realization_enabled
)
select organization_id, true, true
from public.profiles
where id = 'd1000000-0000-4000-8000-000000000001'
on conflict (organization_id) do update
set support_projects_enabled = excluded.support_projects_enabled,
    savings_realization_enabled = excluded.savings_realization_enabled;

insert into public.sourcing_events (
  id, organization_id, event_name, event_type, event_status, project_type
)
select event_id, profile.organization_id, event_name, event_type, event_status, project_type
from (values
  (
    'd2000000-0000-4000-8000-000000000001'::uuid,
    'Sourcing savings project', 'Contract Renewal', 'Pipeline', 'Sourcing'
  ),
  (
    'd2000000-0000-4000-8000-000000000002'::uuid,
    'Support zero-savings project', 'Vendor Performance or Service Issue', 'Not Started', 'Support'
  ),
  (
    'd2000000-0000-4000-8000-000000000003'::uuid,
    'Clean project type change', 'Contract Renewal', 'Pipeline', 'Sourcing'
  )
) seed(event_id, event_name, event_type, event_status, project_type)
cross join public.profiles profile
where profile.id = 'd1000000-0000-4000-8000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1000000-0000-4000-8000-000000000001', true);

select lives_ok(
  $$ insert into public.savings_calculations (
       id, organization_id, event_id, calculation_name, savings_type,
       gross_savings_amount
     ) values (
       'd3000000-0000-4000-8000-000000000001',
       (select organization_id from public.profiles where id = auth.uid()),
       'd2000000-0000-4000-8000-000000000001',
       'Allowed Sourcing calculation', 'Cost Reduction', 100
     ) $$,
  'an administrator can create savings for a Sourcing Project'
);

select ok(
  (select created_by = 'd1000000-0000-4000-8000-000000000001'
       and updated_by = 'd1000000-0000-4000-8000-000000000001'
   from public.savings_calculations
   where id = 'd3000000-0000-4000-8000-000000000001'),
  'an allowed Sourcing calculation retains server-owned actor stamping'
);

select throws_ok(
  $$ insert into public.savings_calculations (
       organization_id, event_id, calculation_name, savings_type
     ) values (
       (select organization_id from public.profiles where id = auth.uid()),
       'd2000000-0000-4000-8000-000000000002',
       'Blocked Support calculation', 'Cost Reduction'
     ) $$,
  '23514', 'Savings records require a Sourcing Project',
  'Support / Non-Commercial projects cannot receive savings calculations'
);

select lives_ok(
  $$ insert into public.savings_calculations (
       id, organization_id, calculation_name, savings_type
     ) values (
       'd3000000-0000-4000-8000-000000000099',
       (select organization_id from public.profiles where id = auth.uid()),
       'Legacy unlinked calculation', 'Cost Reduction'
     ) $$,
  'the legacy unlinked-calculation path remains compatible and report-excluded'
);

select throws_ok(
  $$ insert into public.savings_calculations (
       organization_id, event_id, calculation_name, savings_type
     ) values (
       gen_random_uuid(), 'd2000000-0000-4000-8000-000000000001',
       'Blocked workspace mismatch', 'Cost Reduction'
     ) $$,
  '23514', 'Savings records must use the project workspace',
  'a savings calculation cannot claim another workspace'
);

select throws_ok(
  $$ update public.sourcing_events
     set project_type = 'Support',
         event_type = 'Vendor Performance or Service Issue',
         event_status = 'Not Started'
     where id = 'd2000000-0000-4000-8000-000000000001' $$,
  '23514',
  'Projects with savings records cannot be changed to Support / Non-Commercial',
  'a Sourcing Project with savings cannot be reclassified as Support'
);

select lives_ok(
  $$ update public.sourcing_events
     set project_type = 'Support',
         event_type = 'Vendor Performance or Service Issue',
         event_status = 'Not Started'
     where id = 'd2000000-0000-4000-8000-000000000003' $$,
  'a project with no savings can be reclassified as Support'
);

select ok(
  (select project_type = 'Support'
   from public.sourcing_events
   where id = 'd2000000-0000-4000-8000-000000000003')
  and not exists (
    select 1 from public.savings_calculations
    where event_id = 'd2000000-0000-4000-8000-000000000003'
  ),
  'a reclassified Support project remains a $0-savings record'
);

reset role;

-- Create one deliberately malformed legacy calculation with triggers disabled,
-- then prove every child table still rejects that Support population. This row
-- exists only inside the rolled-back pgTAP transaction.
set local session_replication_role = replica;
insert into public.savings_calculations (
  id, organization_id, event_id, calculation_name, savings_type, calculation_status
)
select
  'd3000000-0000-4000-8000-000000000002', organization_id,
  'd2000000-0000-4000-8000-000000000002',
  'Malformed legacy Support calculation', 'Cost Reduction', 'estimated'
from public.profiles
where id = 'd1000000-0000-4000-8000-000000000001';
set local session_replication_role = origin;

select throws_ok(
  $$ insert into public.savings_calculation_lines (
       organization_id, savings_calculation_id, event_id, line_number, savings_type
     ) select organization_id,
       'd3000000-0000-4000-8000-000000000002',
       'd2000000-0000-4000-8000-000000000002', 1, 'Cost Reduction'
     from public.profiles
     where id = 'd1000000-0000-4000-8000-000000000001' $$,
  '23514', 'Savings records require a Sourcing Project',
  'Support projects cannot receive savings detail lines'
);

select throws_ok(
  $$ insert into public.savings_periods (
       organization_id, event_id, savings_calculation_id,
       period_number, period_month, period_year, period_months, final_amount
     ) select organization_id,
       'd2000000-0000-4000-8000-000000000002',
       'd3000000-0000-4000-8000-000000000002',
       1, 8, 2026, 1, 0
     from public.profiles
     where id = 'd1000000-0000-4000-8000-000000000001' $$,
  '23514', 'Savings records require a Sourcing Project',
  'Support projects cannot receive savings schedule periods'
);

select throws_ok(
  $$ insert into public.realization_periods (
       organization_id, event_id, savings_calculation_id,
       period_name, period_start_date, period_end_date
     ) select organization_id,
       'd2000000-0000-4000-8000-000000000002',
       'd3000000-0000-4000-8000-000000000002',
       'Aug 2026', '2026-08-01', '2026-08-31'
     from public.profiles
     where id = 'd1000000-0000-4000-8000-000000000001' $$,
  '23514', 'Savings records require a Sourcing Project',
  'Support projects cannot receive realization periods'
);

select throws_ok(
  $$ insert into public.savings_calculation_lines (
       organization_id, savings_calculation_id, event_id, line_number, savings_type
     ) select organization_id,
       'd3000000-0000-4000-8000-000000000001',
       'd2000000-0000-4000-8000-000000000002', 2, 'Cost Reduction'
     from public.profiles
     where id = 'd1000000-0000-4000-8000-000000000001' $$,
  '23514', 'Savings detail must use its calculation project',
  'a savings detail line cannot mismatch its calculation and project'
);

select throws_ok(
  $$ update public.savings_calculations
     set event_id = 'd2000000-0000-4000-8000-000000000002'
     where id = 'd3000000-0000-4000-8000-000000000001' $$,
  '23514', 'Savings records require a Sourcing Project',
  'an existing calculation cannot be reassigned to a Support project'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1000000-0000-4000-8000-000000000001', true);

select lives_ok(
  $$ update public.sourcing_events
     set event_status = 'Complete'
     where id = 'd2000000-0000-4000-8000-000000000002' $$,
  'Support project completion remains independent from savings disposition'
);

select ok(
  not exists (
    select 1 from public.savings_periods
    where event_id = 'd2000000-0000-4000-8000-000000000002'
  )
  and not exists (
    select 1 from public.realization_periods
    where event_id = 'd2000000-0000-4000-8000-000000000002'
  ),
  'blocked Support writes leave no schedule or realization residue'
);

select * from finish();
rollback;
